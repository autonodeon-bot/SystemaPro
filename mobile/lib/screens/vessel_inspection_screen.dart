import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as Path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/equipment.dart';
import '../models/vessel_checklist.dart';
import '../models/compressor_checklist.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/location_service.dart';
import '../services/auto_save_service.dart';
import '../services/photo_annotation_service.dart';
import '../services/image_resize_service.dart';
import '../services/checklist_pdf_service.dart';
import 'package:printing/printing.dart';
import '../data/checklist_constants.dart';
import '../widgets/inspection/inspection_form_fields.dart';
import '../widgets/inspection/inspection_general_info_section.dart';
import '../widgets/inspection/inspection_documents_section.dart';
import '../widgets/inspection/inspection_survey_card_section.dart';
import '../widgets/inspection/inspection_checks_section.dart';
import '../widgets/inspection/inspection_safety_devices_section.dart';
import '../widgets/inspection/inspection_measurements_section.dart';
import '../widgets/inspection/inspection_defects_section.dart';
import '../widgets/inspection/inspection_conclusion_section.dart';

class VesselInspectionScreen extends StatefulWidget {
  final Equipment equipment;
  final String? assignmentId;
  final String? existingInspectionId;
  final String? inspectionType;
  /// Предзаполнение из шаблона обследования объекта.
  final Map<String, dynamic>? initialChecklistJson;

  const VesselInspectionScreen({
    super.key,
    required this.equipment,
    this.assignmentId,
    this.existingInspectionId,
    this.inspectionType,
    this.initialChecklistJson,
  });

  @override
  State<VesselInspectionScreen> createState() => _VesselInspectionScreenState();
}

class _VesselInspectionScreenState extends State<VesselInspectionScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormBuilderState>();
  final _scrollController = ScrollController();
  // Постраничная навигация (П.3.1)
  final _pageController = PageController();
  int _currentPage = 0;
  bool _showPageNav = false; // показывать/скрывать навигацию
  static const _pageLabels = [
    '1. Основная информация',
    '2. Документы',
    '3. Карта обследования',
    '4. Проверки + Дефекты',
    '5. ЗРА + СППК',
    '6. Измерения (7-10)',
    '7. Заключение',
  ];
  final ApiService _apiService = ApiService();
  final SyncService _syncService = SyncService();
  final LocationService _locationService = LocationService();
  final AutoSaveService _autoSaveService = AutoSaveService();
  final PhotoAnnotationService _photoAnnotationService = PhotoAnnotationService();
  bool _isSubmitting = false;
  bool _hasUnsavedChanges = false;
  bool _isAutoSaving = false;
  Map<String, double>? _gpsCoordinates;
  DateTime? _lastAutoSaveTime;
  int _formSeed = 0;

  late final VesselChecklist _checklist;

  bool get _isCompressor {
    final typeCode = widget.equipment.typeCode?.toUpperCase() ?? '';
    final typeName = widget.equipment.typeName?.toUpperCase() ?? '';
    return typeCode.contains('COMPRESSOR') ||
        typeCode.contains('КОМПРЕССОР') ||
        typeName.contains('COMPRESSOR') ||
        typeName.contains('КОМПРЕССОР');
  }

  File? _factoryPlatePhoto;
  File? _controlSchemeImage;
  List<String> _additionalObjectPhotos = [];

  final Map<String, String> _documentFiles = {};
  String? _questionnaireId;
  List<String> _selectedEquipmentIds = [];
  List<Map<String, String>> _manualVerificationEquipment = [];
  List<Map<String, dynamic>> _engineers = [];
  bool _loadingEngineers = false;
  bool _showAllEngineersList = false;
  final Map<String, Map<String, dynamic>> _selectedEngineerByMethod = {};
  List<Map<String, dynamic>> _opos = [];
  bool _loadingOpos = false;
  String? _selectedOpoId;

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _checklist = _isCompressor ? CompressorChecklist() : VesselChecklist();
      _checklist.inspectionType = widget.inspectionType;

      for (var doc in ChecklistConstants.documents) {
        _checklist.documents[doc['number']!] = false;
      }

      _prefillFromEquipment();
      _applyTemplateDefaults();

      Future.microtask(_loadEngineers);
      Future.microtask(_loadOpos);
      Future.microtask(_getGpsCoordinates);
      Future.microtask(_startAutoSaveTimer);
      
      Future.microtask(() async {
        final hadLocal = await _loadLocalPendingIfExists();
        if (!hadLocal) {
          await _prefillFromPreviousInspections();
        }
        await _prefillFromOpo();
      });
    } catch (e) {
      _checklist = VesselChecklist();
      _checklist.inspectionType = widget.inspectionType;
      for (var doc in ChecklistConstants.documents) {
        _checklist.documents[doc['number']!] = false;
      }
      print('Ошибка инициализации чек-листа: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    if (_hasUnsavedChanges && !_isSubmitting) {
      _autoSaveDraft();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_hasUnsavedChanges && !_isSubmitting) {
        _autoSaveDraft();
      }
    }
  }

  // ====================================================================
  //  GPS / Таймеры
  // ====================================================================

  Future<void> _getGpsCoordinates() async {
    try {
      final coords = await _locationService.getLastKnownLocation();
      if (coords != null) {
        setState(() {
          _gpsCoordinates = coords;
        });
        if (_checklist.additionalData == null) {
          _checklist.additionalData = {};
        }
        _checklist.additionalData!['gps_coordinates'] = coords;
      }
    } catch (e) {
      print('Ошибка получения GPS координат: $e');
    }
  }

  void _startAutoSaveTimer() {
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && _hasUnsavedChanges && !_isSubmitting) {
        _autoSaveDraft();
        _startAutoSaveTimer();
      }
    });
  }

  // ====================================================================
  //  Автосохранение
  // ====================================================================

  Future<void> _autoSaveDraft() async {
    if (_isAutoSaving) return;
    _isAutoSaving = true;

    try {
      _formKey.currentState?.save();

      final inspectionDateStr = _resolveInspectionDateIso();

      if (_gpsCoordinates == null) {
        await _getGpsCoordinates();
      }

      if (_selectedOpoId != null && _selectedOpoId!.isNotEmpty) {
        try {
          await _apiService.updateEquipmentOpo(
            equipmentId: widget.equipment.id,
            opoId: _selectedOpoId,
          );
        } catch (e) {
          print('Ошибка обновления ОПО оборудования: $e');
        }
      }

      _syncManualEquipmentToChecklist();
      _syncObjectPhotosToChecklist();
      final checklistData = _checklist.toJson();
      checklistData['gps_coordinates'] = _gpsCoordinates;
      
      await _autoSaveService.saveDraft(
        equipmentId: widget.equipment.id,
        checklistData: checklistData,
        assignmentId: widget.assignmentId,
        inspectionId: widget.existingInspectionId,
      );

      await _syncService.saveInspectionOffline(
        equipmentId: widget.equipment.id,
        checklist: _checklist,
        conclusion: _checklist.conclusion,
        inspectionDate: inspectionDateStr,
        documentFiles: _documentFiles,
        assignmentId: widget.assignmentId,
        verificationEquipmentIds: _selectedEquipmentIds,
        status: 'DRAFT',
      );

      setState(() {
        _hasUnsavedChanges = false;
        _lastAutoSaveTime = DateTime.now();
      });
      print('Черновик автоматически сохранен');
    } catch (e) {
      print('Ошибка автосохранения черновика: $e');
    } finally {
      _isAutoSaving = false;
    }
  }

  // ====================================================================
  //  Загрузка данных (ОПО, инженеры, черновики)
  // ====================================================================

  Future<void> _loadOpos() async {
    if (widget.equipment.opoId != null && widget.equipment.opoId!.isNotEmpty) {
      _selectedOpoId = widget.equipment.opoId;
      return;
    }

    setState(() => _loadingOpos = true);
    try {
      var opos = await _syncService.getOfflineOpos();
      
      if (opos.isEmpty) {
        try {
          String? enterpriseId;
          if (widget.assignmentId != null) {
            try {
              final assignments = await _apiService.getAssignments();
              final assignment = assignments.firstWhere(
                (a) => a.id == widget.assignmentId,
                orElse: () => assignments.first,
              );
              enterpriseId = assignment.enterpriseId;
            } catch (_) {}
          }
          
          if (enterpriseId != null && enterpriseId.isNotEmpty) {
            opos = await _apiService.getOposByEnterprise(enterpriseId);
            await _syncService.saveOposOffline(opos);
          } else {
            opos = await _apiService.getOpos();
            await _syncService.saveOposOffline(opos);
          }
        } catch (_) {}
      }
      
      if (!mounted) return;
      String? lastOpoId;
      if (_selectedOpoId == null || _selectedOpoId!.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          lastOpoId = prefs.getString('last_opo_id');
        } catch (_) {}
      }
      setState(() {
        _opos = opos;
        _loadingOpos = false;
        if ((_selectedOpoId == null || _selectedOpoId!.isEmpty) &&
            lastOpoId != null &&
            lastOpoId.isNotEmpty &&
            opos.any((o) => (o['id'] as String? ?? '') == lastOpoId)) {
          _selectedOpoId = lastOpoId;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingOpos = false);
    }
  }

  Future<void> _loadEngineers() async {
    setState(() => _loadingEngineers = true);
    try {
      var engineers = await _syncService.getOfflineEngineers();
      
      try {
        final freshEngineers = await _apiService.getEngineers();
        for (final eng in freshEngineers) {
          final quals = eng['qualifications'];
          if (quals is String) {
            try {
              eng['qualifications'] = json.decode(quals);
            } catch (_) {
              eng['qualifications'] = [];
            }
          }
        }
        await _syncService.saveEngineersOffline(freshEngineers);
        engineers = freshEngineers;
      } catch (_) {
        for (final eng in engineers) {
          final quals = eng['qualifications'];
          if (quals is String) {
            try {
              eng['qualifications'] = json.decode(quals);
            } catch (_) {
              eng['qualifications'] = [];
            }
          }
        }
      }
      
      if (!mounted) return;
      Map<String, String> lastEngineersByMethod = {};
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('last_engineers_by_method');
        if (saved != null && saved.isNotEmpty) {
          final decoded = json.decode(saved) as Map<String, dynamic>?;
          if (decoded != null) {
            for (final e in decoded.entries) {
              final id = e.value?.toString();
              if (id != null && id.isNotEmpty) {
                lastEngineersByMethod[e.key] = id;
              }
            }
          }
        }
      } catch (_) {}
      setState(() {
        _engineers = engineers;
        _loadingEngineers = false;
        _selectedEngineerByMethod.clear();
        for (final ie in _checklist.inspectionEngineers) {
          final match = engineers.firstWhere(
            (e) => e['id']?.toString() == ie.engineerId,
            orElse: () => <String, dynamic>{},
          );
          if (match.isNotEmpty) {
            _selectedEngineerByMethod[ie.method] = match;
          }
        }
        for (final entry in lastEngineersByMethod.entries) {
          final method = entry.key;
          final id = entry.value;
          if (_selectedEngineerByMethod.containsKey(method)) continue;
          final match = engineers.firstWhere(
            (e) => e['id']?.toString() == id,
            orElse: () => <String, dynamic>{},
          );
          if (match.isNotEmpty) {
            _selectedEngineerByMethod[method] = match;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingEngineers = false);
    }
  }

  Future<bool> _loadLocalPendingIfExists() async {
    try {
      final pending = await _syncService.getLatestPendingInspection(
        equipmentId: widget.equipment.id,
        assignmentId: widget.assignmentId,
      );
      if (pending == null) return false;

      final data = (pending['data'] as Map?)?.cast<String, dynamic>();
      if (data == null) return false;

      final equipmentType = data['equipment_type']?.toString();
      final isCompressor = equipmentType != null &&
          equipmentType.toUpperCase().contains('COMPRESSOR');

      final loadedChecklist = isCompressor
          ? CompressorChecklist.fromJson(data)
          : VesselChecklist.fromJson(data);

      final ve = pending['verification_equipment_ids'];
      if (ve is List) {
        _selectedEquipmentIds =
            ve.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
      final manualEqRaw = data['additional_data'] is Map
          ? (data['additional_data'] as Map)['manual_verification_equipment']
          : null;
      if (manualEqRaw is List) {
        _manualVerificationEquipment = manualEqRaw
            .whereType<Map>()
            .map((e) => <String, String>{
                  'name': (e['name'] ?? '').toString(),
                  'serial_number': (e['serial_number'] ?? '').toString(),
                  'verification_certificate_number':
                      (e['verification_certificate_number'] ?? '').toString(),
                  'next_verification_date':
                      (e['next_verification_date'] ?? '').toString(),
                })
            .where((e) =>
                e['name']!.isNotEmpty ||
                e['serial_number']!.isNotEmpty ||
                e['verification_certificate_number']!.isNotEmpty ||
                e['next_verification_date']!.isNotEmpty)
            .toList();
      }
      final objectPhotosRaw = data['additional_data'] is Map
          ? (data['additional_data'] as Map)['object_photos']
          : null;
      if (objectPhotosRaw is List) {
        _additionalObjectPhotos = objectPhotosRaw
            .map((e) => e?.toString() ?? '')
            .where((p) => p.trim().isNotEmpty)
            .toList();
      }

      final docs = pending['document_files'];
      if (docs is Map) {
        _documentFiles.clear();
        for (final entry in docs.entries) {
          final key = entry.key.toString();
          final val = entry.value;
          if (val is String) {
            _documentFiles[key] = val;
          } else if (val is Map) {
            final m = Map<String, dynamic>.from(val);
            final fp = m['file_path']?.toString();
            if (fp != null && fp.isNotEmpty) {
              _documentFiles[key] = fp;
            }
          }
        }
      }

      setState(() {
        final j = loadedChecklist.toJson();
        final merged = isCompressor
            ? CompressorChecklist.fromJson(j)
            : VesselChecklist.fromJson(j);

        _checklist.inspectionDate = merged.inspectionDate;
        _checklist.executors = merged.executors;
        _checklist.organization = merged.organization;
        _checklist.documents = merged.documents;
        _checklist.vesselName = merged.vesselName;
        _checklist.serialNumber = merged.serialNumber;
        _checklist.regNumber = merged.regNumber;
        _checklist.manufacturer = merged.manufacturer;
        _checklist.manufactureYear = merged.manufactureYear;
        _checklist.diameter = merged.diameter;
        _checklist.workingPressure = merged.workingPressure;
        _checklist.wallThickness = merged.wallThickness;
        _checklist.factoryPlatePhoto = merged.factoryPlatePhoto;
        _checklist.controlSchemeImage = merged.controlSchemeImage;
        _checklist.matchesDrawing = merged.matchesDrawing;
        _checklist.hasThermalInsulation = merged.hasThermalInsulation;
        _checklist.anticorrosionCoatingState = merged.anticorrosionCoatingState;
        _checklist.supportState = merged.supportState;
        _checklist.fastenersState = merged.fastenersState;
        _checklist.hasFlangeMisalignment = merged.hasFlangeMisalignment;
        _checklist.hasNozzleMisalignment = merged.hasNozzleMisalignment;
        _checklist.hasVesselRepairs = merged.hasVesselRepairs;
        _checklist.hasTpaRepairs = merged.hasTpaRepairs;
        _checklist.internalDevicesState = merged.internalDevicesState;
        _checklist.zraItems = merged.zraItems;
        _checklist.sppkItems = merged.sppkItems;
        _checklist.switchingDevice = merged.switchingDevice;
        _checklist.gauge = merged.gauge;
        _checklist.levelSensor = merged.levelSensor;
        _checklist.levelAlarm = merged.levelAlarm;
        _checklist.valveInspections = merged.valveInspections;
        _checklist.ovalityMeasurements = merged.ovalityMeasurements;
        _checklist.deflectionMeasurements = merged.deflectionMeasurements;
        _checklist.hasLocalDeformations = merged.hasLocalDeformations;
        _checklist.hasExternalDefects = merged.hasExternalDefects;
        _checklist.hasInternalDefects = merged.hasInternalDefects;
        _checklist.hasArmatureDefects = merged.hasArmatureDefects;
        _checklist.hardnessTests = merged.hardnessTests;
        _checklist.weldInspections = merged.weldInspections;
        _checklist.thicknessMeasurements = merged.thicknessMeasurements;
        _checklist.inspectionEngineers = merged.inspectionEngineers;
        _checklist.visualDefects = merged.visualDefects;
        _checklist.additionalData = merged.additionalData;
        _checklist.conclusion = merged.conclusion;
        if (merged is VesselChecklist) {
          _checklist.purpose = merged.purpose;
          _checklist.commissioningYear = merged.commissioningYear;
          _checklist.designPressure = merged.designPressure;
          _checklist.testPressure = merged.testPressure;
          _checklist.workingTemperature = merged.workingTemperature;
          _checklist.designTemperature = merged.designTemperature;
          _checklist.workingMedium = merged.workingMedium;
          _checklist.mediumCharacteristics = merged.mediumCharacteristics;
          _checklist.vesselGroup = merged.vesselGroup;
          _checklist.mediumGroup = merged.mediumGroup;
          _checklist.corrosionAllowance = merged.corrosionAllowance;
          _checklist.previousInspectionResult = merged.previousInspectionResult;
        }

        _selectedEngineerByMethod.clear();
        for (final ie in merged.inspectionEngineers) {
          final method = ie.method;
          final match = _engineers.firstWhere(
            (e) => e['id']?.toString() == ie.engineerId,
            orElse: () => {},
          );
          if (match.isNotEmpty) {
            _selectedEngineerByMethod[method] = match;
          }
        }

        if (_checklist is CompressorChecklist &&
            merged is CompressorChecklist) {
          final cur = _checklist as CompressorChecklist;
          cur.compressorType = merged.compressorType;
          cur.powerRating = merged.powerRating;
          cur.pressureRatio = merged.pressureRatio;
          cur.flowRate = merged.flowRate;
          cur.rotationSpeed = merged.rotationSpeed;
          cur.numberOfStages = merged.numberOfStages;
          cur.coolingSystem = merged.coolingSystem;
          cur.lubricationSystem = merged.lubricationSystem;
          cur.cylinderState = merged.cylinderState;
          cur.pistonState = merged.pistonState;
          cur.valvesState = merged.valvesState;
          cur.crankshaftState = merged.crankshaftState;
          cur.bearingsState = merged.bearingsState;
          cur.sealsState = merged.sealsState;
          cur.vibrationMeasurements = merged.vibrationMeasurements;
          cur.temperatureMeasurements = merged.temperatureMeasurements;
          cur.oilLevel = merged.oilLevel;
          cur.oilCondition = merged.oilCondition;
          cur.oilFilterState = merged.oilFilterState;
          cur.airFilterState = merged.airFilterState;
        }

        final fpPath = _checklist.factoryPlatePhoto?.trim() ?? '';
        if (fpPath.isNotEmpty && File(fpPath).existsSync()) {
          _factoryPlatePhoto = File(fpPath);
        } else {
          _factoryPlatePhoto = null;
        }
        final csPath = _checklist.controlSchemeImage?.trim() ?? '';
        if (csPath.isNotEmpty && File(csPath).existsSync()) {
          _controlSchemeImage = File(csPath);
        } else {
          _controlSchemeImage = null;
        }
        _formSeed++;
      });
      return true;
    } catch (e) {
      print('Ошибка загрузки локальных данных: $e');
      return false;
    }
  }

  // ====================================================================
  //  Автозаполнение
  // ====================================================================

  /// Поля шаблона обследования — только если в чек-листе ещё пусто.
  void _applyTemplateDefaults() {
    final raw = widget.initialChecklistJson;
    if (raw == null || raw.isEmpty || _isCompressor) return;
    try {
      final tpl = VesselChecklist.fromJson(Map<String, dynamic>.from(raw));

      void mergeStr(String? from, void Function(String v) set, String? current) {
        if (from != null && from.trim().isNotEmpty &&
            (current == null || current.trim().isEmpty)) {
          set(from.trim());
        }
      }

      mergeStr(tpl.purpose, (v) => _checklist.purpose = v, _checklist.purpose);
      mergeStr(
        tpl.organization,
        (v) => _checklist.organization = v,
        _checklist.organization,
      );
      mergeStr(
        tpl.previousInspectionResult,
        (v) => _checklist.previousInspectionResult = v,
        _checklist.previousInspectionResult,
      );
      mergeStr(tpl.workingMedium, (v) => _checklist.workingMedium = v, _checklist.workingMedium);

      if (tpl.inspectionType != null && tpl.inspectionType!.isNotEmpty) {
        _checklist.inspectionType = tpl.inspectionType;
      }
      _checklist.includeOpoData = tpl.includeOpoData;
    } catch (e) {
      debugPrint('Шаблон обследования: $e');
    }
  }

  void _prefillFromEquipment() {
    final attrs = widget.equipment.attributes ?? {};
    String? getAttr(String key) {
      final v = attrs[key];
      if (v == null) return null;
      final s = v.toString();
      return s.trim().isEmpty ? null : s.trim();
    }

    _checklist.vesselName = getAttr('vessel_name') ?? widget.equipment.name;
    _checklist.serialNumber =
        getAttr('serial_number') ?? widget.equipment.serialNumber;
    _checklist.regNumber = getAttr('reg_number');
    _checklist.manufacturer = getAttr('manufacturer');
    _checklist.manufactureYear = getAttr('manufacture_year');
    _checklist.organization =
        _checklist.organization ?? getAttr('organization');

    if (!_isCompressor) {
      _checklist.diameter = getAttr('diameter');
      _checklist.workingPressure = getAttr('working_pressure');
      _checklist.wallThickness = getAttr('wall_thickness');
      _checklist.purpose = getAttr('purpose');
      _checklist.commissioningYear =
          getAttr('commissioning_year') ?? widget.equipment.commissioningDate?.substring(0, 4);
      _checklist.designPressure = getAttr('design_pressure');
      _checklist.testPressure = getAttr('test_pressure');
      _checklist.workingTemperature = getAttr('working_temperature');
      _checklist.designTemperature = getAttr('design_temperature');
      _checklist.workingMedium = getAttr('working_medium');
      _checklist.mediumCharacteristics = getAttr('medium_characteristics');
      _checklist.vesselGroup = getAttr('vessel_group');
      _checklist.mediumGroup = getAttr('medium_group');
      _checklist.corrosionAllowance = getAttr('corrosion_allowance');
      _checklist.previousInspectionResult = getAttr('previous_inspection_result');
      final objectPhotosRaw = attrs['object_photos'];
      if (objectPhotosRaw is List) {
        _additionalObjectPhotos = objectPhotosRaw
            .map((e) => e?.toString() ?? '')
            .where((e) => e.trim().isNotEmpty)
            .toList();
        _syncObjectPhotosToChecklist();
      }
    } else {
      final compressorChecklist = _checklist as CompressorChecklist;
      compressorChecklist.compressorType = getAttr('compressor_type');
      compressorChecklist.powerRating = getAttr('power_rating');
      compressorChecklist.pressureRatio = getAttr('pressure_ratio');
      compressorChecklist.flowRate = getAttr('flow_rate');
      compressorChecklist.rotationSpeed = getAttr('rotation_speed');
      compressorChecklist.numberOfStages = getAttr('number_of_stages');
      compressorChecklist.coolingSystem = getAttr('cooling_system');
      compressorChecklist.lubricationSystem = getAttr('lubrication_system');
    }
  }

  Future<void> _prefillFromPreviousInspections() async {
    try {
      final inspections = await _apiService.getInspections(widget.equipment.id);
      if (inspections.isEmpty) return;
      
      Map<String, dynamic>? previousInspection;
      for (var insp in inspections) {
        if (insp['status'] == 'COMPLETED' || insp['status'] == 'SIGNED') {
          previousInspection = insp;
          break;
        }
      }
      if (previousInspection == null && inspections.isNotEmpty) {
        previousInspection = inspections.first;
      }
      if (previousInspection == null) return;
      
      final prevData = previousInspection['data'] as Map<String, dynamic>?;
      if (prevData == null) return;
      
      if (_checklist.organization == null || _checklist.organization!.isEmpty) {
        final org = prevData['organization']?.toString();
        if (org != null && org.isNotEmpty) _checklist.organization = org;
      }
      
      if (_checklist.executors == null || _checklist.executors!.isEmpty) {
        final exec = prevData['executors']?.toString();
        if (exec != null && exec.isNotEmpty) _checklist.executors = exec;
      }
      
      final prevDocs = prevData['documents'] as Map<String, dynamic>?;
      if (prevDocs != null && _checklist.documents.isEmpty) {
        for (var entry in prevDocs.entries) {
          if (entry.value == true) _checklist.documents[entry.key] = true;
        }
      }
      
      final prevDocsInfo = prevData['documents_info'] as Map<String, dynamic>?;
      if (prevDocsInfo != null) {
        _checklist.documentsInfo ??= {};
        for (var entry in prevDocsInfo.entries) {
          if (!_checklist.documentsInfo!.containsKey(entry.key)) {
            _checklist.documentsInfo![entry.key] = entry.value;
          }
        }
      }

      if (!_isCompressor && _checklist is VesselChecklist) {
        final v = _checklist as VesselChecklist;
        if ((v.purpose == null || v.purpose!.isEmpty) && prevData['purpose'] != null) v.purpose = prevData['purpose']?.toString();
        if ((v.commissioningYear == null || v.commissioningYear!.isEmpty) && prevData['commissioning_year'] != null) v.commissioningYear = prevData['commissioning_year']?.toString();
        if ((v.designPressure == null || v.designPressure!.isEmpty) && prevData['design_pressure'] != null) v.designPressure = prevData['design_pressure']?.toString();
        if ((v.testPressure == null || v.testPressure!.isEmpty) && prevData['test_pressure'] != null) v.testPressure = prevData['test_pressure']?.toString();
        if ((v.workingTemperature == null || v.workingTemperature!.isEmpty) && prevData['working_temperature'] != null) v.workingTemperature = prevData['working_temperature']?.toString();
        if ((v.designTemperature == null || v.designTemperature!.isEmpty) && prevData['design_temperature'] != null) v.designTemperature = prevData['design_temperature']?.toString();
        if ((v.workingMedium == null || v.workingMedium!.isEmpty) && prevData['working_medium'] != null) v.workingMedium = prevData['working_medium']?.toString();
        if ((v.mediumCharacteristics == null || v.mediumCharacteristics!.isEmpty) && prevData['medium_characteristics'] != null) v.mediumCharacteristics = prevData['medium_characteristics']?.toString();
        if ((v.vesselGroup == null || v.vesselGroup!.isEmpty) && prevData['vessel_group'] != null) v.vesselGroup = prevData['vessel_group']?.toString();
        if ((v.mediumGroup == null || v.mediumGroup!.isEmpty) && prevData['medium_group'] != null) v.mediumGroup = prevData['medium_group']?.toString();
        if ((v.corrosionAllowance == null || v.corrosionAllowance!.isEmpty) && prevData['corrosion_allowance'] != null) v.corrosionAllowance = prevData['corrosion_allowance']?.toString();
        if ((v.previousInspectionResult == null || v.previousInspectionResult!.isEmpty) && prevData['previous_inspection_result'] != null) v.previousInspectionResult = prevData['previous_inspection_result']?.toString();
      }

      if (!_isCompressor && _checklist is VesselChecklist) {
        final v = _checklist as VesselChecklist;
        if (prevData['matches_drawing'] != null) v.matchesDrawing = prevData['matches_drawing'] == true;
        if (prevData['has_thermal_insulation'] != null) v.hasThermalInsulation = prevData['has_thermal_insulation'] == true;
        if (prevData['anticorrosion_coating_state'] != null) v.anticorrosionCoatingState = prevData['anticorrosion_coating_state']?.toString();
        if (prevData['support_state'] != null) v.supportState = prevData['support_state']?.toString();
        if (prevData['fasteners_state'] != null) v.fastenersState = prevData['fasteners_state']?.toString();
        if (prevData['has_flange_misalignment'] != null) v.hasFlangeMisalignment = prevData['has_flange_misalignment'] == true;
        if (prevData['has_nozzle_misalignment'] != null) v.hasNozzleMisalignment = prevData['has_nozzle_misalignment'] == true;
        if (prevData['has_vessel_repairs'] != null) v.hasVesselRepairs = prevData['has_vessel_repairs'] == true;
        if (prevData['has_tpa_repairs'] != null) v.hasTpaRepairs = prevData['has_tpa_repairs'] == true;
        if (prevData['internal_devices_state'] != null) v.internalDevicesState = prevData['internal_devices_state']?.toString();
        if (prevData['has_local_deformations'] != null) v.hasLocalDeformations = prevData['has_local_deformations'] == true;
        if (prevData['has_external_defects'] != null) v.hasExternalDefects = prevData['has_external_defects'] == true;
        if (prevData['has_internal_defects'] != null) v.hasInternalDefects = prevData['has_internal_defects'] == true;
        if (prevData['has_armature_defects'] != null) v.hasArmatureDefects = prevData['has_armature_defects'] == true;
      }
      
      if (mounted) setState(() => _formSeed++);
    } catch (e) {
      print('Ошибка автозаполнения из предыдущих обследований: $e');
    }
  }

  Future<void> _prefillFromOpo() async {
    if (_selectedOpoId == null || _selectedOpoId!.isEmpty) return;
    try {
      final opo = _opos.firstWhere(
        (o) => o['id'] == _selectedOpoId,
        orElse: () => {},
      );
      if (opo.isEmpty) return;
      final surveyData = opo['survey_data'] as Map<String, dynamic>?;
      if (surveyData == null) return;
      if ((_checklist.organization == null || _checklist.organization!.isEmpty) &&
          surveyData['organization'] != null) {
        _checklist.organization = surveyData['organization'].toString();
      }
      if ((_checklist.executors == null || _checklist.executors!.isEmpty) &&
          surveyData['executors'] != null) {
        _checklist.executors = surveyData['executors'].toString();
      }
      setState(() {});
    } catch (e) {
      print('Ошибка автозаполнения из ОПО: $e');
    }
  }

  // ====================================================================
  //  Фото / файлы
  // ====================================================================

  Future<String> _maybeAddDateTimeGpsToPhoto(String imagePath, {bool force = false}) async {
    if (!force) {
      bool addMeta = true;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setInner) => AlertDialog(
            backgroundColor: const Color(0xFF1e293b),
            title: const Text('Добавить на фото?', style: TextStyle(color: Colors.white)),
            content: CheckboxListTile(
              value: addMeta,
              onChanged: (v) => setInner(() => addMeta = v ?? true),
              title: const Text(
                'Добавить дату и GPS-координаты',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              activeColor: const Color(0xFF3b82f6),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Пропустить', style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, addMeta),
                child: const Text('ОК', style: TextStyle(color: Color(0xFF3b82f6))),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return imagePath;
    }

    final now = DateTime.now();
    final dateStr = intl.DateFormat('dd.MM.yyyy HH:mm').format(now);
    Map<String, double>? coords;
    try { coords = await _locationService.getCurrentLocation(); } catch (_) {}
    coords ??= _gpsCoordinates;
    if (coords == null) {
      try { coords = await _locationService.getLastKnownLocation(); } catch (_) {}
    }
    if (coords == null && force && mounted) {
      final issue = await _locationService.ensureLocationAccess(openSettingsOnFailure: true);
      if (issue != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS не получен: $issue. Включите геолокацию и разрешение для приложения, затем сделайте фото повторно.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      try { coords = await _locationService.getCurrentLocation(); } catch (_) {}
    }
    final gpsStr = coords != null
        ? '${coords['latitude']!.toStringAsFixed(6)}, ${coords['longitude']!.toStringAsFixed(6)}'
        : null;

    final result = await _photoAnnotationService.annotatePhotoWithDateTimeAndGps(
      imagePath: imagePath,
      dateTimeText: dateStr,
      gpsText: gpsStr,
    );
    return result ?? imagePath;
  }

  Future<void> _pickImage(ImageSource source, bool isFactoryPlate) async {
    try {
      if (source == ImageSource.camera) {
        final prefs = await SharedPreferences.getInstance();
        final key = isFactoryPlate ? 'photo_factory_plate_hint_shown' : 'photo_control_scheme_hint_shown';
        if (!(prefs.getBool(key) ?? false)) {
          await prefs.setBool(key, true);
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1e293b),
              title: Text(
                isFactoryPlate ? 'Фото заводской таблички' : 'Схема контроля',
                style: const TextStyle(color: Colors.white),
              ),
              content: Text(
                isFactoryPlate
                    ? 'Снимите крупно заводскую табличку на корпусе оборудования, чтобы были видны все надписи.'
                    : 'Снимите схему контроля или карту обследования крупно и чётко для нанесения точек замера.',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Понятно', style: TextStyle(color: Color(0xFF3b82f6))),
                ),
              ],
            ),
          );
          if (!mounted) return;
        }
      }
      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image != null) {
        String finalImagePath = await _maybeAddDateTimeGpsToPhoto(image.path, force: isFactoryPlate);

        final shouldAnnotate = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1e293b),
            title: const Text('Добавить текст на фото?', style: TextStyle(color: Colors.white)),
            content: const Text('Хотите добавить текст или пометки на фото?', style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Пропустить', style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Добавить', style: TextStyle(color: Color(0xFF3b82f6))),
              ),
            ],
          ),
        );

        if (shouldAnnotate == true) {
          final annotationText = await showDialog<String>(
            context: context,
            builder: (context) {
              final controller = TextEditingController();
              return AlertDialog(
                title: const Text('Текст аннотации'),
                content: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'Введите текст для фото',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                  TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Добавить')),
                ],
              );
            },
          );

          if (annotationText != null && annotationText.isNotEmpty) {
            final annotatedPath = await _photoAnnotationService.annotatePhoto(
              imagePath: finalImagePath,
              annotationText: annotationText,
            );
            if (annotatedPath != null) finalImagePath = annotatedPath;
          }
        }

        try {
          if (await File(finalImagePath).exists()) {
            final docKey = isFactoryPlate ? 'factory_plate_photo' : 'control_scheme_image';
            final persisted = await _persistPickedFile(
              sourcePath: finalImagePath,
              fileName: Path.basename(finalImagePath),
              documentNumber: docKey,
            );
            finalImagePath = persisted;
          }
        } catch (_) {}

        setState(() {
          if (isFactoryPlate) {
            _factoryPlatePhoto = File(finalImagePath);
            _checklist.factoryPlatePhoto = finalImagePath;
          } else {
            _controlSchemeImage = File(finalImagePath);
            _checklist.controlSchemeImage = finalImagePath;
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка выбора изображения: $e')),
      );
    }
  }

  Future<void> _pickImageFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
      if (result == null || result.files.isEmpty || !mounted) return;
      final path = result.files.single.path;
      if (path == null || path.isEmpty) return;
      final file = File(path);
      if (!await file.exists()) return;
      final finalImagePath = await _persistPickedFile(
        sourcePath: path,
        fileName: Path.basename(path),
        documentNumber: 'control_scheme_image',
      );
      setState(() {
        _controlSchemeImage = File(finalImagePath);
        _checklist.controlSchemeImage = finalImagePath;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл выбран'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора файла: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickBuiltInTemplate() async {
    try {
      final byteData = await rootBundle.load('assets/images/vessel_template.png');
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/vessel_template.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      final persistedPath = await _persistPickedFile(
        sourcePath: file.path,
        fileName: 'vessel_template.png',
        documentNumber: 'control_scheme_image',
      );
      setState(() {
        _controlSchemeImage = File(persistedPath);
        _checklist.controlSchemeImage = persistedPath;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Встроенный шаблон выбран'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки шаблона: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickStandardDrawing() async {
    try {
      final templates = await _apiService.getVesselTemplates();
      if (!mounted) return;
      if (templates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступных шаблонов чертежей на сервере'), backgroundColor: Colors.orange),
        );
        return;
      }
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1e293b),
          title: const Text('Выбрать стандартный чертёж', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: templates.map((t) {
                final name = t['name'] as String? ?? '';
                return ListTile(
                  title: Text(name, style: const TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context, t),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена', style: TextStyle(color: Colors.white70))),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      final templateName = selected['name'] as String? ?? '';
      if (templateName.isEmpty) return;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Загрузка чертежа...')));
      final localPath = await _apiService.getVesselTemplate(templateName);
      if (!mounted) return;
      if (localPath == null || localPath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить шаблон'), backgroundColor: Colors.red),
        );
        return;
      }
      final persistedPath = await _persistPickedFile(
        sourcePath: localPath,
        fileName: templateName,
        documentNumber: 'control_scheme_image',
      );
      setState(() {
        _controlSchemeImage = File(persistedPath);
        _checklist.controlSchemeImage = persistedPath;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Стандартный чертёж выбран'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора чертежа: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickAdditionalObjectPhoto(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      final withMeta = await _maybeAddDateTimeGpsToPhoto(picked.path);
      final persistedPath = await _persistPickedFile(
        sourcePath: withMeta,
        fileName: Path.basename(withMeta),
        documentNumber: 'object_photo',
      );
      setState(() {
        _additionalObjectPhotos.add(persistedPath);
        _hasUnsavedChanges = true;
        _syncObjectPhotosToChecklist();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка добавления фото: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<String> _persistPickedFile({
    required String sourcePath,
    required String fileName,
    required String documentNumber,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final storageDir = Directory(Path.join(dir.path, 'offline_documents'));
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = Path.extension(fileName).toLowerCase();
    final isImage = ext == '.jpg' || ext == '.jpeg' || ext == '.png';
    final outFileName = isImage
        ? '${documentNumber}_${ts}_${Path.basenameWithoutExtension(fileName)}.jpg'
        : '${documentNumber}_${ts}_$fileName';
    final targetPath = Path.join(storageDir.path, outFileName);
    final pathToWrite = isImage
        ? await ImageResizeService.resizeIfNeeded(sourcePath)
        : sourcePath;
    await File(pathToWrite).copy(targetPath);
    return targetPath;
  }

  // ====================================================================
  //  Утилиты
  // ====================================================================

  String _resolveInspectionDateIso() {
    if (_checklist.inspectionDate != null && _checklist.inspectionDate!.isNotEmpty) {
      try {
        DateTime.parse(_checklist.inspectionDate!);
        return _checklist.inspectionDate!;
      } catch (_) {
        return DateTime.now().toIso8601String();
      }
    }
    return DateTime.now().toIso8601String();
  }

  void _syncManualEquipmentToChecklist() {
    _checklist.additionalData ??= <String, dynamic>{};
    _checklist.additionalData!['manual_verification_equipment'] =
        _manualVerificationEquipment
            .map((e) => <String, String>{
                  'name': e['name'] ?? '',
                  'serial_number': e['serial_number'] ?? '',
                  'verification_certificate_number': e['verification_certificate_number'] ?? '',
                  'next_verification_date': e['next_verification_date'] ?? '',
                })
            .toList();
  }

  void _syncObjectPhotosToChecklist() {
    _checklist.additionalData ??= <String, dynamic>{};
    _checklist.additionalData!['object_photos'] = List<String>.from(
      _additionalObjectPhotos.where((p) => p.trim().isNotEmpty),
    );
  }

  void _updateInspectionEngineers() {
    final result = <InspectionEngineer>[];
    final methods = <String>[];
    for (final entry in _selectedEngineerByMethod.entries) {
      final m = entry.key;
      final e = entry.value;
      final ie = InspectionEngineer(method: m);
      ie.engineerId = e['id']?.toString();
      ie.fullName = e['full_name']?.toString();
      final cert = InspectionGeneralInfoSection.extractCertificateForMethod(
          e['qualifications'], m);
      ie.certificateNumber = cert['certificate_number'];
      ie.validUntil = cert['valid_until'];
      result.add(ie);
      if (m.isNotEmpty) methods.add(m);
    }
    _checklist.inspectionEngineers = result;
    _checklist.ndtMethods = methods;
  }

  // ====================================================================
  //  Сохранение / Подписание
  // ====================================================================

  Future<void> _exportToPdf() async {
    try {
      final name = widget.equipment.name ?? 'Сосуд';
      final pdfBytes = await ChecklistPdfService.buildPdf(_checklist, name);
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'obsledovanie_${name.replaceAll(RegExp(r'[^\w\s-]'), '_').replaceAll(RegExp(r'\s+'), '_')}.pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF создан и готов к отправке')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта в PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveDraft() async {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, заполните все обязательные поля'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final inspectionDateStr = _resolveInspectionDateIso();
      _syncManualEquipmentToChecklist();
      _syncObjectPhotosToChecklist();

      await _syncService.saveInspectionOffline(
        equipmentId: widget.equipment.id,
        checklist: _checklist,
        conclusion: _checklist.conclusion,
        inspectionDate: inspectionDateStr,
        documentFiles: _documentFiles,
        assignmentId: widget.assignmentId,
        verificationEquipmentIds: _selectedEquipmentIds,
        status: 'DRAFT',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Черновик сохранен локально. Отправка на сервер при синхронизации.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _signAndFinish() async {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, заполните все обязательные поля'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (widget.assignmentId == null || widget.assignmentId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подписание доступно только для работ по заданию'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_selectedEquipmentIds.isEmpty && _manualVerificationEquipment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Перед завершением необходимо выбрать оборудование для поверок или добавить прибор вручную'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final inspectionDateStr = _resolveInspectionDateIso();
    _syncManualEquipmentToChecklist();
    _syncObjectPhotosToChecklist();
    final summary = [
      'Оборудование: ${widget.equipment.name}',
      'Дата: $inspectionDateStr',
      if (_checklist.conclusion?.isNotEmpty ?? false)
        'Заключение: ${_checklist.conclusion!.length > 80 ? "${_checklist.conclusion!.substring(0, 80)}…" : _checklist.conclusion}',
      'Оборудование для поверок: ${_selectedEquipmentIds.length + _manualVerificationEquipment.length}',
    ].join('\n');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подписать и завершить?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Краткая сводка перед подписанием:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Text(summary, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              const Text(
                'После синхронизации задание будет отмечено как выполненное. Вы сможете сформировать отчёт в веб-версии.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Подписать')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _isSubmitting = true);
    try {
      if (_selectedOpoId != null && _selectedOpoId!.isNotEmpty) {
        try {
          await _apiService.updateEquipmentOpo(equipmentId: widget.equipment.id, opoId: _selectedOpoId);
        } catch (e) {
          print('Ошибка обновления ОПО оборудования: $e');
        }
      }

      await _syncService.saveInspectionOffline(
        equipmentId: widget.equipment.id,
        checklist: _checklist,
        conclusion: _checklist.conclusion,
        inspectionDate: inspectionDateStr,
        documentFiles: _documentFiles,
        assignmentId: widget.assignmentId,
        verificationEquipmentIds: _selectedEquipmentIds,
        status: 'SIGNED',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Чек-лист подписан локально. Отправка на сервер при синхронизации.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ====================================================================
  //  BUILD
  // ====================================================================

  @override
  Widget build(BuildContext context) {
    final initialValues = <String, dynamic>{
      'executors': _checklist.executors,
      'organization': _checklist.organization,
      'vessel_name': _checklist.vesselName,
      'serial_number': _checklist.serialNumber,
      'reg_number': _checklist.regNumber,
      'manufacturer': _checklist.manufacturer,
      'manufacture_year': _checklist.manufactureYear,
    };

    if (!_isCompressor) {
      initialValues['diameter'] = _checklist.diameter;
      initialValues['working_pressure'] = _checklist.workingPressure;
      initialValues['wall_thickness'] = _checklist.wallThickness;
      initialValues['purpose'] = _checklist.purpose;
      initialValues['commissioning_year'] = _checklist.commissioningYear;
      initialValues['design_pressure'] = _checklist.designPressure;
      initialValues['test_pressure'] = _checklist.testPressure;
      initialValues['working_temperature'] = _checklist.workingTemperature;
      initialValues['design_temperature'] = _checklist.designTemperature;
      initialValues['working_medium'] = _checklist.workingMedium;
      initialValues['medium_characteristics'] = _checklist.mediumCharacteristics;
      initialValues['vessel_group'] = _checklist.vesselGroup;
      initialValues['medium_group'] = _checklist.mediumGroup;
      initialValues['corrosion_allowance'] = _checklist.corrosionAllowance;
      initialValues['previous_inspection_result'] = _checklist.previousInspectionResult;
    } else {
      final c = _checklist as CompressorChecklist;
      initialValues['compressor_type'] = c.compressorType;
      initialValues['power_rating'] = c.powerRating;
      initialValues['pressure_ratio'] = c.pressureRatio;
      initialValues['flow_rate'] = c.flowRate;
      initialValues['rotation_speed'] = c.rotationSpeed;
      initialValues['number_of_stages'] = c.numberOfStages;
    }

    if (_checklist.inspectionDate != null && _checklist.inspectionDate!.isNotEmpty) {
      try {
        initialValues['inspection_date'] = DateTime.parse(_checklist.inspectionDate!);
      } catch (_) {}
    }

    if (!_isCompressor) {
      final v = _checklist as VesselChecklist;
      initialValues['matches_drawing'] = v.matchesDrawing == true ? 'yes' : (v.matchesDrawing == false ? 'no' : null);
      initialValues['has_thermal_insulation'] = v.hasThermalInsulation == true ? 'yes' : (v.hasThermalInsulation == false ? 'no' : null);
      initialValues['anticorrosion_coating'] = v.anticorrosionCoatingState;
      initialValues['support_state'] = v.supportState;
      initialValues['fasteners_state'] = v.fastenersState;
      initialValues['has_flange_misalignment'] = v.hasFlangeMisalignment == true ? 'yes' : (v.hasFlangeMisalignment == false ? 'no' : null);
      initialValues['has_nozzle_misalignment'] = v.hasNozzleMisalignment == true ? 'yes' : (v.hasNozzleMisalignment == false ? 'no' : null);
      initialValues['has_vessel_repairs'] = v.hasVesselRepairs == true ? 'yes' : (v.hasVesselRepairs == false ? 'no' : null);
      initialValues['has_tpa_repairs'] = v.hasTpaRepairs == true ? 'yes' : (v.hasTpaRepairs == false ? 'no' : null);
      initialValues['internal_devices_state'] = v.internalDevicesState;
      initialValues['has_local_deformations'] = v.hasLocalDeformations == true ? 'yes' : (v.hasLocalDeformations == false ? 'no' : null);
      initialValues['has_external_defects'] = v.hasExternalDefects == true ? 'yes' : (v.hasExternalDefects == false ? 'no' : null);
      initialValues['has_internal_defects'] = v.hasInternalDefects == true ? 'yes' : (v.hasInternalDefects == false ? 'no' : null);
      initialValues['has_armature_defects'] = v.hasArmatureDefects == true ? 'yes' : (v.hasArmatureDefects == false ? 'no' : null);
    }

    final conclusionSection = InspectionConclusionSection(
      checklist: _checklist,
      isSubmitting: _isSubmitting,
      hasAssignment: widget.assignmentId != null && widget.assignmentId!.isNotEmpty,
      lastAutoSaveTime: _lastAutoSaveTime,
      selectedEquipmentIds: _selectedEquipmentIds,
      factoryPlatePhoto: _factoryPlatePhoto,
      onSaveDraft: _saveDraft,
      onSignAndFinish: _signAndFinish,
    );

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvoked: (didPop) async {
        if (!didPop && _hasUnsavedChanges) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Несохраненные изменения'),
              content: const Text('У вас есть несохраненные изменения. Сохранить черновик перед выходом?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Выйти без сохранения')),
                ElevatedButton(
                  onPressed: () async {
                    await _autoSaveDraft();
                    if (mounted) Navigator.pop(context, true);
                  },
                  child: const Text('Сохранить и выйти'),
                ),
              ],
            ),
          );
          if (shouldPop == true && mounted) context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Обследование: ${widget.equipment.name}'),
          backgroundColor: kInspectionScaffoldBg,
          foregroundColor: Colors.white,
          actions: [
            if (_isSubmitting)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              )
            else ...[
              IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _exportToPdf, tooltip: 'Экспорт чек-листа в PDF'),
              IconButton(icon: const Icon(Icons.save), onPressed: _saveDraft, tooltip: 'Сохранить черновик локально (отправка при синхронизации)'),
            ],
          ],
        ),
        backgroundColor: kInspectionScaffoldBg,
        body: KeyedSubtree(
          key: ValueKey(_formSeed),
          child: FormBuilder(
            key: _formKey,
            onChanged: () {
              if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
            },
            initialValue: initialValues,
            child: Stack(
              children: [
                // PageView по разделам
                _buildPageView(conclusionSection),
                // Полупрозрачная навигация по страницам (П.3.1)
                _buildPageNavOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageView(dynamic conclusionSection) {
    // Страница 0: Основная информация
    final page0 = _buildSinglePage(
      pageIndex: 0,
      progressWidget: conclusionSection.buildProgressIndicator(),
      child: InspectionGeneralInfoSection(
        checklist: _checklist,
        selectedEquipmentIds: _selectedEquipmentIds,
        manualVerificationEquipment: _manualVerificationEquipment,
        engineers: _engineers,
        loadingEngineers: _loadingEngineers,
        showAllEngineersList: _showAllEngineersList,
        selectedEngineerByMethod: _selectedEngineerByMethod,
        opos: _opos,
        loadingOpos: _loadingOpos,
        selectedOpoId: _selectedOpoId,
        equipmentOpoId: widget.equipment.opoId,
        onStateChanged: () => setState(() => _hasUnsavedChanges = true),
        onEquipmentIdsChanged: (ids) => setState(() => _selectedEquipmentIds = ids),
        onManualEquipmentChanged: (items) {
          setState(() {
            _manualVerificationEquipment = items;
            _hasUnsavedChanges = true;
            _syncManualEquipmentToChecklist();
          });
        },
        onShowAllEngineersChanged: (v) => setState(() => _showAllEngineersList = v),
        onEngineerSelected: (methodKey, value) {
          setState(() {
            _selectedEngineerByMethod[methodKey] = value;
            _updateInspectionEngineers();
            _hasUnsavedChanges = true;
          });
          final id = value['id']?.toString();
          if (id != null && id.isNotEmpty) {
            SharedPreferences.getInstance().then((prefs) async {
              try {
                final saved = prefs.getString('last_engineers_by_method');
                final map = (saved != null && saved.isNotEmpty)
                    ? Map<String, String>.from(
                        (json.decode(saved) as Map).map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
                    : <String, String>{};
                map[methodKey] = id;
                await prefs.setString('last_engineers_by_method', json.encode(map));
              } catch (_) {}
            });
          }
        },
        onOpoChanged: (value) {
          setState(() => _selectedOpoId = value);
          if (value != null && value.isNotEmpty) {
            SharedPreferences.getInstance().then((prefs) => prefs.setString('last_opo_id', value));
            _apiService.updateEquipmentOpo(equipmentId: widget.equipment.id, opoId: value).catchError((e) {
              print('Ошибка обновления ОПО оборудования: $e');
            });
          }
        },
      ),
    );

    // Страница 1: Перечень документов + анализ предыдущих обследований
    final page1 = _buildSinglePage(
      pageIndex: 1,
      child: InspectionDocumentsSection(
        checklist: _checklist,
        documentFiles: _documentFiles,
        questionnaireId: _questionnaireId,
        apiService: _apiService,
        imagePicker: _imagePicker,
        onStateChanged: () => setState(() => _hasUnsavedChanges = true),
      ),
    );

    // Страница 2: Карта обследования (фото таблички, доп.фото, схема)
    final page2 = _buildSinglePage(
      pageIndex: 2,
      child: InspectionSurveyCardSection(
        checklist: _checklist,
        isCompressor: _isCompressor,
        factoryPlatePhoto: _factoryPlatePhoto,
        controlSchemeImage: _controlSchemeImage,
        additionalObjectPhotos: _additionalObjectPhotos,
        onStateChanged: () => setState(() => _hasUnsavedChanges = true),
        onPickImage: _pickImage,
        onPickImageFromFile: _pickImageFromFile,
        onPickBuiltInTemplate: _pickBuiltInTemplate,
        onPickStandardDrawing: _pickStandardDrawing,
        onPickAdditionalObjectPhoto: _pickAdditionalObjectPhoto,
        onRemoveObjectPhoto: (idx) {
          setState(() {
            _additionalObjectPhotos.removeAt(idx);
            _hasUnsavedChanges = true;
            _syncObjectPhotosToChecklist();
          });
        },
      ),
    );

    // Страница 3: Проверки + Дефекты (р.11)
    final page3 = _buildSinglePage(
      pageIndex: 3,
      children: [
        InspectionChecksSection(
          checklist: _checklist,
          onStateChanged: () => setState(() => _hasUnsavedChanges = true),
        ),
        const SizedBox(height: 24),
        InspectionDefectsSection(
          checklist: _checklist,
          imagePicker: _imagePicker,
          onStateChanged: () => setState(() => _hasUnsavedChanges = true),
          maybeAddDateTimeGpsToPhoto: _maybeAddDateTimeGpsToPhoto,
        ),
      ],
    );

    // Страница 4: ЗРА + СППК
    final page4 = _buildSinglePage(
      pageIndex: 4,
      child: InspectionSafetyDevicesSection(
        checklist: _checklist,
        onStateChanged: () => setState(() => _hasUnsavedChanges = true),
      ),
    );

    // Страница 5: Измерения 7-10 (овальность, твёрдость, ПВК/УЗК, УЗТ)
    final page5 = _buildSinglePage(
      pageIndex: 5,
      child: InspectionMeasurementsSection(
        checklist: _checklist,
        controlSchemeImage: _controlSchemeImage,
        equipment: widget.equipment,
        onStateChanged: () => setState(() => _hasUnsavedChanges = true),
        onThicknessSave: (measurements, image) {
          setState(() {
            _checklist.thicknessMeasurements = measurements;
            if (image != null) _controlSchemeImage = image;
          });
        },
        onUztSchemeSave: (schemeIndex, measurements, image) {
          setState(() => _hasUnsavedChanges = true);
        },
      ),
    );

    // Страница 6: Заключение + кнопки
    final page6 = _buildSinglePage(
      pageIndex: 6,
      child: conclusionSection,
    );

    return GestureDetector(
      onTap: () => setState(() => _showPageNav = !_showPageNav),
      child: PageView(
        controller: _pageController,
        onPageChanged: (idx) => setState(() {
          _currentPage = idx;
          _showPageNav = true;
        }),
        children: [page0, page1, page2, page3, page4, page5, page6],
      ),
    );
  }

  /// Оборачивает один виджет или список виджетов в ScrollView с заголовком страницы
  Widget _buildSinglePage({
    required int pageIndex,
    Widget? child,
    List<Widget>? children,
    Widget? progressWidget,
  }) {
    final bottomPad = 88.0 + MediaQuery.viewPaddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
      children: [
        if (progressWidget != null) ...[
          progressWidget,
          const SizedBox(height: 12),
        ],
        _buildPageHeader(pageIndex),
        const SizedBox(height: 12),
        if (child != null) child,
        if (children != null) ...children,
        // Кнопки навигации внизу страницы
        const SizedBox(height: 24),
        _buildPageNavButtons(pageIndex),
      ],
    );
  }

  /// Заголовок страницы с номером и индикатором прогресса
  Widget _buildPageHeader(int pageIndex) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kInspectionAccentBlue.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: kInspectionAccentBlue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${pageIndex + 1}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _pageLabels[pageIndex],
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14),
            ),
          ),
          Text(
            '${pageIndex + 1} / ${_pageLabels.length}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Кнопки «Назад» / «Далее» внизу страницы
  Widget _buildPageNavButtons(int pageIndex) {
    return Row(
      children: [
        if (pageIndex > 0)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut),
              icon: const Icon(Icons.arrow_back_ios, size: 14),
              label: const Text('Назад'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white30),
              ),
            ),
          ),
        if (pageIndex > 0 && pageIndex < _pageLabels.length - 1)
          const SizedBox(width: 12),
        if (pageIndex < _pageLabels.length - 1)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut),
              icon: const Icon(Icons.arrow_forward_ios, size: 14),
              label: const Text('Далее'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kInspectionAccentBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  /// Полупрозрачная навигация по страницам (П.3.1) — снизу экрана
  Widget _buildPageNavOverlay() {
    if (!_showPageNav) return const SizedBox.shrink();
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      // SafeArea исключает overlap с системной панелью жестов/кнопок Android.
      child: SafeArea(
        top: false,
        child: GestureDetector(
        onTap: () {}, // Не скрывать при тапе на само меню
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.82),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Навигация по разделам',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  GestureDetector(
                    onTap: () => setState(() => _showPageNav = false),
                    child: const Icon(Icons.close, color: Colors.white54, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(_pageLabels.length, (idx) {
                  final isCurrent = idx == _currentPage;
                  return GestureDetector(
                    onTap: () {
                      _pageController.animateToPage(idx,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut);
                      setState(() => _showPageNav = false);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? kInspectionAccentBlue
                            : Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _pageLabels[idx],
                        style: TextStyle(
                          color: isCurrent ? Colors.white : Colors.white70,
                          fontSize: 11,
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
