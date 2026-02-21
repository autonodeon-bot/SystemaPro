import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'dart:io';
import 'dart:typed_data';
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
import '../widgets/checklist_progress_indicator.dart';
import 'package:printing/printing.dart';
import '../data/checklist_constants.dart';
import 'thickness_measurement_screen.dart';
import 'verification_equipment_selection_screen.dart';

class VesselInspectionScreen extends StatefulWidget {
  final Equipment equipment;
  final String? assignmentId; // ID задания (версия 3.3.0)
  final String? existingInspectionId; // ID существующей инспекции для редактирования
  final String? inspectionType; // VISUAL, NDT, QUESTIONNAIRE, EXPERTISE

  const VesselInspectionScreen({
    super.key,
    required this.equipment,
    this.assignmentId,
    this.existingInspectionId,
    this.inspectionType,
  });

  @override
  State<VesselInspectionScreen> createState() => _VesselInspectionScreenState();
}

class _VesselInspectionScreenState extends State<VesselInspectionScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormBuilderState>();
  final _scrollController = ScrollController();
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
  /// Счётчик пересоздания формы (увеличивается после загрузки черновика, чтобы подставились сохранённые значения радиокнопок/состояний)
  int _formSeed = 0;

  // Определяем тип чек-листа на основе типа оборудования
  late final VesselChecklist _checklist;

  // Проверяем, является ли оборудование компрессором
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

  // Храним загруженные файлы документов: document_number -> file_path
  final Map<String, String> _documentFiles = {};
  // Храним questionnaire_id после создания
  String? _questionnaireId;
  // Выбранное оборудование для поверок
  List<String> _selectedEquipmentIds = [];
  List<Map<String, dynamic>> _engineers = [];
  bool _loadingEngineers = false;
  /// Галочка: показывать весь список специалистов (даже без удостоверения по виду НК)
  bool _showAllEngineersList = false;
  final Map<String, Map<String, dynamic>> _selectedEngineerByMethod = {};
  // Выбранные методы контроля (галочки)
  final Map<String, bool> _selectedNdtMethods = {
    'VIK': false,
    'UZK': false,
    'UZT': false,
    'PVK': false,
  };
  // ОПО
  List<Map<String, dynamic>> _opos = [];
  bool _loadingOpos = false;
  String? _selectedOpoId;

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      // Создаем чек-лист в зависимости от типа оборудования
      _checklist = _isCompressor ? CompressorChecklist() : VesselChecklist();
      _checklist.inspectionType = widget.inspectionType;

      // Инициализация документов
      for (var doc in ChecklistConstants.documents) {
        _checklist.documents[doc['number']!] = false;
      }

      // Базовое автозаполнение из карточки оборудования
      _prefillFromEquipment();

      Future.microtask(_loadEngineers);
      Future.microtask(_loadOpos);
      Future.microtask(_getGpsCoordinates);
      Future.microtask(_startAutoSaveTimer);
      
      // Сначала локальный черновик; если его нет — подставляем из последней инспекции с сервера (проверки, состояния)
      Future.microtask(() async {
        final hadLocal = await _loadLocalPendingIfExists();
        if (!hadLocal) {
          await _prefillFromPreviousInspections();
        }
        await _prefillFromOpo();
      });
    } catch (e) {
      // Если ошибка при инициализации, создаем базовый чек-лист
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
    // Автосохранение при закрытии экрана
    if (_hasUnsavedChanges && !_isSubmitting) {
      _autoSaveDraft();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Автосохранение при сворачивании/закрытии приложения
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_hasUnsavedChanges && !_isSubmitting) {
        _autoSaveDraft();
      }
    }
  }

  /// Получить GPS координаты
  Future<void> _getGpsCoordinates() async {
    try {
      final coords = await _locationService.getLastKnownLocation();
      if (coords != null) {
        setState(() {
          _gpsCoordinates = coords;
        });
        // Сохраняем координаты в чек-лист
        if (_checklist.additionalData == null) {
          _checklist.additionalData = {};
        }
        _checklist.additionalData!['gps_coordinates'] = coords;
      }
    } catch (e) {
      print('Ошибка получения GPS координат: $e');
    }
  }

  /// Запустить таймер автосохранения
  void _startAutoSaveTimer() {
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && _hasUnsavedChanges && !_isSubmitting) {
        _autoSaveDraft();
        _startAutoSaveTimer(); // Продолжаем цикл
      }
    });
  }

  Future<void> _autoSaveDraft() async {
    if (_isAutoSaving) return;
    _isAutoSaving = true;

    try {
      // Сохраняем форму без валидации (черновик)
      _formKey.currentState?.save();

      final inspectionDateStr = _resolveInspectionDateIso();

      // Обновляем GPS координаты если их еще нет
      if (_gpsCoordinates == null) {
        await _getGpsCoordinates();
      }

      // Обновляем ОПО оборудования, если было выбрано
      if (_selectedOpoId != null && _selectedOpoId!.isNotEmpty) {
        try {
          await _apiService.updateEquipmentOpo(
            equipmentId: widget.equipment.id,
            opoId: _selectedOpoId,
          );
        } catch (e) {
          // Не блокируем сохранение из-за ошибки обновления ОПО
          print('Ошибка обновления ОПО оборудования: $e');
        }
      }

      // Сохраняем через новый сервис автосохранения
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

  Future<void> _loadOpos() async {
    // Загружаем ОПО только если у оборудования нет opo_id
    if (widget.equipment.opoId != null && widget.equipment.opoId!.isNotEmpty) {
      _selectedOpoId = widget.equipment.opoId;
      return;
    }

    setState(() {
      _loadingOpos = true;
    });
    try {
      // Пытаемся загрузить из локального хранилища
      var opos = await _syncService.getOfflineOpos();
      
      // Если нет локально, загружаем с сервера
      if (opos.isEmpty) {
        try {
          // Получаем enterprise_id из задания или оборудования
          String? enterpriseId;
          if (widget.assignmentId != null) {
            try {
              final assignments = await _apiService.getAssignments();
              final assignment = assignments.firstWhere(
                (a) => a.id == widget.assignmentId,
                orElse: () => assignments.first,
              );
              enterpriseId = assignment.enterpriseId;
            } catch (_) {
              // Игнорируем ошибки
            }
          }
          
          if (enterpriseId != null && enterpriseId.isNotEmpty) {
            opos = await _apiService.getOposByEnterprise(enterpriseId);
            await _syncService.saveOposOffline(opos);
          } else {
            // Если нет enterprise_id, загружаем все ОПО
            opos = await _apiService.getOpos();
            await _syncService.saveOposOffline(opos);
          }
        } catch (_) {
          // Игнорируем ошибки загрузки
        }
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
      setState(() {
        _loadingOpos = false;
      });
    }
  }

  Future<void> _loadEngineers() async {
    setState(() {
      _loadingEngineers = true;
    });
    try {
      // Сначала загружаем локальные данные для быстрого отображения
      var engineers = await _syncService.getOfflineEngineers();
      
      // Пытаемся загрузить свежие данные с сервера (если есть интернет)
      try {
        final freshEngineers = await _apiService.getEngineers();
        // Нормализуем qualifications (может быть строкой JSON)
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
        engineers = freshEngineers; // Используем свежие данные
      } catch (_) {
        // Если не удалось загрузить с сервера, используем локальные
        // Нормализуем qualifications в локальных данных тоже
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
        // Восстанавливаем выбранных инженеров из чек-листа
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
      setState(() {
        _loadingEngineers = false;
      });
    }
  }

  /// Возвращает true, если был загружен и подставлен локальный черновик.
  Future<bool> _loadLocalPendingIfExists() async {
    try {
      final pending = await _syncService.getLatestPendingInspection(
        equipmentId: widget.equipment.id,
        assignmentId: widget.assignmentId,
      );
      if (pending == null) return false;

      final data = (pending['data'] as Map?)?.cast<String, dynamic>();
      if (data == null) return false;

      // Определяем тип по equipment_type в data (для компрессора)
      final equipmentType = data['equipment_type']?.toString();
      final isCompressor = equipmentType != null &&
          equipmentType.toUpperCase().contains('COMPRESSOR');

      final loadedChecklist = isCompressor
          ? CompressorChecklist.fromJson(data)
          : VesselChecklist.fromJson(data);

      // Восстанавливаем выбор поверенного оборудования
      final ve = pending['verification_equipment_ids'];
      if (ve is List) {
        _selectedEquipmentIds =
            ve.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }

      // Восстанавливаем пути к вложениям документов
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

      // Подменяем текущий чек-лист данными из локального сохранения
      setState(() {
        // копируем поля в существующий объект (потому что _checklist late final)
        final j = loadedChecklist.toJson();
        final merged = isCompressor
            ? CompressorChecklist.fromJson(j)
            : VesselChecklist.fromJson(j);

        // переносим значения
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

        // Компрессор-специфичные поля
        if (_checklist is CompressorChecklist &&
            merged is CompressorChecklist) {
          final cur = _checklist;
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

        // Файлы для UI только если файл реально существует (путь мог устареть после перезапуска)
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
        // Пересоздаём форму, чтобы initialValues подхватили загруженные радиокнопки и состояния
        _formSeed++;
      });
      return true;
    } catch (e) {
      // Не роняем экран
      print('Ошибка загрузки локальных данных: $e');
      return false;
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

    // Общие поля для всех типов оборудования
    _checklist.vesselName = getAttr('vessel_name') ?? widget.equipment.name;
    _checklist.serialNumber =
        getAttr('serial_number') ?? widget.equipment.serialNumber;
    _checklist.regNumber = getAttr('reg_number');
    _checklist.manufacturer = getAttr('manufacturer');
    _checklist.manufactureYear = getAttr('manufacture_year');
    _checklist.organization =
        _checklist.organization ?? getAttr('organization');

    // Поля специфичные для сосудов и техническая характеристика (таблица 6)
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
    } else {
      // Поля специфичные для компрессоров
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

  /// Автозаполнение из предыдущих обследований
  Future<void> _prefillFromPreviousInspections() async {
    try {
      // Получаем предыдущие обследования для этого оборудования
      final inspections = await _apiService.getInspections(widget.equipment.id);
      
      if (inspections.isEmpty) return;
      
      // Берем последнее завершенное обследование
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
      
      // Автозаполняем только если поля пустые
      if (_checklist.organization == null || _checklist.organization!.isEmpty) {
        final org = prevData['organization']?.toString();
        if (org != null && org.isNotEmpty) {
          _checklist.organization = org;
        }
      }
      
      if (_checklist.executors == null || _checklist.executors!.isEmpty) {
        final exec = prevData['executors']?.toString();
        if (exec != null && exec.isNotEmpty) {
          _checklist.executors = exec;
        }
      }
      
      // Автозаполняем документы, если они были в предыдущем обследовании
      final prevDocs = prevData['documents'] as Map<String, dynamic>?;
      if (prevDocs != null && _checklist.documents.isEmpty) {
        for (var entry in prevDocs.entries) {
          if (entry.value == true) {
            _checklist.documents[entry.key] = true;
          }
        }
      }
      
      // Автозаполняем информацию о документах (номера и даты)
      final prevDocsInfo = prevData['documents_info'] as Map<String, dynamic>?;
      if (prevDocsInfo != null) {
        if (_checklist.documentsInfo == null) {
          _checklist.documentsInfo = {};
        }
        for (var entry in prevDocsInfo.entries) {
          if (!_checklist.documentsInfo!.containsKey(entry.key)) {
            _checklist.documentsInfo![entry.key] = entry.value;
          }
        }
      }

      // Техническая характеристика и анализ предыдущих обследований
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

      // Проверки и состояния (радиокнопки и выпадающие списки) — подставляем из последней инспекции
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
      
      if (mounted) setState(() {
        _formSeed++;
      });
    } catch (e) {
      print('Ошибка автозаполнения из предыдущих обследований: $e');
    }
  }

  /// Автозаполнение из данных ОПО
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
      
      // Автозаполняем организацию из ОПО, если не заполнена
      if ((_checklist.organization == null || _checklist.organization!.isEmpty) &&
          surveyData['organization'] != null) {
        _checklist.organization = surveyData['organization'].toString();
      }
      
      // Автозаполняем исполнителей из ОПО, если не заполнены
      if ((_checklist.executors == null || _checklist.executors!.isEmpty) &&
          surveyData['executors'] != null) {
        _checklist.executors = surveyData['executors'].toString();
      }
      
      setState(() {});
    } catch (e) {
      print('Ошибка автозаполнения из ОПО: $e');
    }
  }

  /// Показывает диалог с чекбоксом «Добавить дату и GPS на фото», при подтверждении накладывает оверлей
  Future<String> _maybeAddDateTimeGpsToPhoto(String imagePath) async {
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

    final now = DateTime.now();
    final dateStr = intl.DateFormat('dd.MM.yyyy HH:mm').format(now);
    Map<String, double>? coords;
    try {
      coords = await _locationService.getCurrentLocation();
    } catch (_) {}
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
        String finalImagePath = await _maybeAddDateTimeGpsToPhoto(image.path);

        // Показываем диалог для текстовой аннотации
        final shouldAnnotate = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1e293b),
            title: const Text('Добавить текст на фото?', style: TextStyle(color: Colors.white)),
            content: const Text(
              'Хотите добавить текст или пометки на фото?',
              style: TextStyle(color: Colors.white70),
            ),
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
          // Показываем диалог для ввода текста аннотации
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
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: const Text('Добавить'),
                  ),
                ],
              );
            },
          );

          if (annotationText != null && annotationText.isNotEmpty) {
            // Добавляем текстовую аннотацию к фото
            final annotatedPath = await _photoAnnotationService.annotatePhoto(
              imagePath: finalImagePath,
              annotationText: annotationText,
            );
            if (annotatedPath != null) {
              finalImagePath = annotatedPath;
            }
          }
        }

        // Копируем в постоянную папку приложения, чтобы фото было доступно при синхронизации
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
        } catch (_) {
          // Оставляем исходный путь при ошибке копирования
        }

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

  /// Выбор файла изображения (из документов/загрузок)
  Future<void> _pickImageFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
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

  /// Встроенный шаблон чертежа (из assets приложения)
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

  /// Выбор стандартного чертежа сосуда с сервера (для схемы контроля)
  Future<void> _pickStandardDrawing() async {
    try {
      final templates = await _apiService.getVesselTemplates();
      if (!mounted) return;
      if (templates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет доступных шаблонов чертежей на сервере'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1e293b),
          title: const Text(
            'Выбрать стандартный чертёж',
            style: TextStyle(color: Colors.white),
          ),
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      final templateName = selected['name'] as String? ?? '';
      if (templateName.isEmpty) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Загрузка чертежа...')),
      );
      final localPath = await _apiService.getVesselTemplate(templateName);
      if (!mounted) return;
      if (localPath == null || localPath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось загрузить шаблон'),
            backgroundColor: Colors.red,
          ),
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
          const SnackBar(
            content: Text('Стандартный чертёж выбран'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора чертежа: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _resolveInspectionDateIso() {
    if (_checklist.inspectionDate != null &&
        _checklist.inspectionDate!.isNotEmpty) {
      try {
        DateTime.parse(_checklist.inspectionDate!);
        return _checklist.inspectionDate!;
      } catch (_) {
        return DateTime.now().toIso8601String();
      }
    }
    return DateTime.now().toIso8601String();
  }

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
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка экспорта в PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveDraft() async {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пожалуйста, заполните все обязательные поля'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final inspectionDateStr = _resolveInspectionDateIso();

      // Черновик: разрешаем сохранять даже без оборудования для поверок,
      // чтобы инженер мог заполнить часть данных и вернуться позже.
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
            content: Text(
                'Черновик сохранен локально. Отправка на сервер при синхронизации.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _signAndFinish() async {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пожалуйста, заполните все обязательные поля'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (widget.assignmentId == null || widget.assignmentId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Подписание доступно только для работ по заданию'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Подписание: требуем выбор оборудования для поверок
    if (_selectedEquipmentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Перед завершением необходимо выбрать оборудование для поверок'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final inspectionDateStr = _resolveInspectionDateIso();
    final summary = [
      'Оборудование: ${widget.equipment.name}',
      'Дата: $inspectionDateStr',
      if (_checklist.conclusion?.isNotEmpty ?? false) 'Заключение: ${_checklist.conclusion!.length > 80 ? "${_checklist.conclusion!.substring(0, 80)}…" : _checklist.conclusion}',
      'Оборудование для поверок: ${_selectedEquipmentIds.length}',
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
              const Text(
                'Краткая сводка перед подписанием:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(summary, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              const Text(
                'После синхронизации задание будет отмечено как выполненное. '
                'Вы сможете сформировать отчёт в веб-версии.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Подписать')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _isSubmitting = true);
    try {
      // Обновляем ОПО оборудования, если было выбрано
      if (_selectedOpoId != null && _selectedOpoId!.isNotEmpty) {
        try {
          await _apiService.updateEquipmentOpo(
            equipmentId: widget.equipment.id,
            opoId: _selectedOpoId,
          );
        } catch (e) {
          // Не блокируем сохранение из-за ошибки обновления ОПО
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

      // Важно: НЕ ставим задание COMPLETED на клиенте.
      // COMPLETED выставит backend после успешной синхронизации create_inspection(status=SIGNED).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Чек-лист подписан локально. Отправка на сервер при синхронизации.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialValues = <String, dynamic>{
      'executors': _checklist.executors,
      'organization': _checklist.organization,

      // Карта обследования (общие поля)
      'vessel_name': _checklist.vesselName,
      'serial_number': _checklist.serialNumber,
      'reg_number': _checklist.regNumber,
      'manufacturer': _checklist.manufacturer,
      'manufacture_year': _checklist.manufactureYear,
    };

    // Добавляем поля в зависимости от типа оборудования
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
      final compressorChecklist = _checklist as CompressorChecklist;
      initialValues['compressor_type'] = compressorChecklist.compressorType;
      initialValues['power_rating'] = compressorChecklist.powerRating;
      initialValues['pressure_ratio'] = compressorChecklist.pressureRatio;
      initialValues['flow_rate'] = compressorChecklist.flowRate;
      initialValues['rotation_speed'] = compressorChecklist.rotationSpeed;
      initialValues['number_of_stages'] = compressorChecklist.numberOfStages;
    }

    // Дата (если уже есть строка ISO)
    if (_checklist.inspectionDate != null &&
        _checklist.inspectionDate!.isNotEmpty) {
      try {
        initialValues['inspection_date'] =
            DateTime.parse(_checklist.inspectionDate!);
      } catch (_) {}
    }

    // Проверки и состояния (радиокнопки Да/Нет и выпадающие списки) — чтобы при повторном входе выбор сохранялся
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

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvoked: (didPop) async {
        if (!didPop && _hasUnsavedChanges) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Несохраненные изменения'),
              content: const Text(
                  'У вас есть несохраненные изменения. Сохранить черновик перед выходом?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Выйти без сохранения'),
                ),
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
          if (shouldPop == true && mounted) {
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Обследование: ${widget.equipment.name}'),
          backgroundColor: const Color(0xFF0f172a),
          foregroundColor: Colors.white,
          actions: [
            if (_isSubmitting)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: _exportToPdf,
                tooltip: 'Экспорт чек-листа в PDF',
              ),
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _saveDraft,
                tooltip:
                    'Сохранить черновик локально (отправка при синхронизации)',
              ),
            ],
          ],
        ),
        backgroundColor: const Color(0xFF0f172a),
        body: KeyedSubtree(
          key: ValueKey(_formSeed),
          child: FormBuilder(
            key: _formKey,
            onChanged: () {
              if (!_hasUnsavedChanges) {
                setState(() {
                  _hasUnsavedChanges = true;
                });
              }
            },
            initialValue: initialValues,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                // Виджет прогресса заполнения
                _buildProgressIndicator(),
              const SizedBox(height: 16),
              _buildSectionHeader('1. Основная информация'),
              // Кнопка выбора оборудования для поверок
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final selected = await Navigator.push<List<String>>(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            VerificationEquipmentSelectionScreen(
                          preselectedIds: _selectedEquipmentIds,
                        ),
                      ),
                    );
                    if (selected != null) {
                      setState(() {
                        _selectedEquipmentIds = selected;
                      });
                    }
                  },
                  icon: Icon(
                    _selectedEquipmentIds.isEmpty
                        ? Icons.warning
                        : Icons.check_circle,
                    color: _selectedEquipmentIds.isEmpty
                        ? Colors.orange
                        : Colors.green,
                  ),
                  label: Text(
                    _selectedEquipmentIds.isEmpty
                        ? 'Выбрать оборудование для поверок *'
                        : 'Выбрано оборудования: ${_selectedEquipmentIds.length}',
                    style: TextStyle(
                      color: _selectedEquipmentIds.isEmpty
                          ? Colors.orange
                          : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedEquipmentIds.isEmpty
                        ? Colors.orange.withOpacity(0.2)
                        : Colors.green.withOpacity(0.2),
                    padding: const EdgeInsets.all(16),
                    side: BorderSide(
                      color: _selectedEquipmentIds.isEmpty
                          ? Colors.orange
                          : Colors.green,
                      width: 2,
                    ),
                  ),
                ),
              ),
              if (_selectedEquipmentIds.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Внимание! Необходимо выбрать поверенное оборудование перед началом работ.',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              _buildDateField('inspection_date', 'Дата обследования', (date) {
                _checklist.inspectionDate = date?.toIso8601String();
              }),
              _buildTextField('executors', 'Исполнители', (value) {
                _checklist.executors = value;
              }),
              _buildTextField(
                  'organization', 'Организация (НГДУ, цех, месторождение)',
                  (value) {
                _checklist.organization = value;
              }),
              // Выбор ОПО (если не задано)
              if (widget.equipment.opoId == null || widget.equipment.opoId!.isEmpty)
                _buildOpoSelectionField(),
              const SizedBox(height: 16),
              _buildEngineerSelectionSection(),
              const SizedBox(height: 24),
              _buildSectionHeader('2. Перечень рассмотренных документов'),

              // Галочка: включать ли пункты 1-9 (ОПО) в этот чек-лист
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.25)),
                ),
                child: SwitchListTile.adaptive(
                  value: _checklist.includeOpoData,
                  onChanged: (v) {
                    setState(() {
                      _checklist.includeOpoData = v;
                    });
                  },
                  title: const Text(
                    'Данные по ОПО (пункты 1–9)',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    _checklist.includeOpoData
                        ? 'Включено: заполните весь опросный лист'
                        : 'Выключено: чек-лист только по оборудованию (начиная с пункта 10)',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  activeColor: Colors.green,
                ),
              ),

              ...ChecklistConstants.documents.where((doc) {
                final n = int.tryParse(doc['number'] ?? '0') ?? 0;
                if (_checklist.includeOpoData) return true;
                return n >= 10; // без ОПО показываем только 10-17
              }).map((doc) => _buildDocumentCheckbox(doc)),
              const SizedBox(height: 24),
              _buildSectionHeader('3. Карта обследования'),
              _buildTextField(
                  'vessel_name',
                  _isCompressor
                      ? 'Наименование компрессора'
                      : 'Наименование сосуда', (value) {
                _checklist.vesselName = value;
              }),
              _buildTextField('serial_number', 'Заводской номер', (value) {
                _checklist.serialNumber = value;
              }),
              _buildTextField('reg_number', 'Регистрационный номер', (value) {
                _checklist.regNumber = value;
              }),
              _buildTextField('manufacturer', 'Изготовитель', (value) {
                _checklist.manufacturer = value;
              }),
              _buildTextField('manufacture_year', 'Год изготовления', (value) {
                _checklist.manufactureYear = value;
              }),
              // Поля для сосудов (скрыты для компрессоров)
              if (!_isCompressor) ...[
                _buildTextField('diameter', 'Диаметр сосуда', (value) {
                  _checklist.diameter = value;
                }),
                _buildTextField('working_pressure', 'Рабочее давление',
                    (value) {
                  _checklist.workingPressure = value;
                }),
                _buildTextField(
                    'wall_thickness', 'Толщина стенки (обечайка / днище)',
                    (value) {
                  _checklist.wallThickness = value;
                }),
                _buildSectionHeader('Краткая техническая характеристика (таблица 6)'),
                _buildTextField('purpose', 'Назначение', (v) => _checklist.purpose = v),
                _buildTextField('commissioning_year', 'Год ввода в эксплуатацию', (v) => _checklist.commissioningYear = v),
                _buildTextField('design_pressure', 'Расчётное давление, МПа', (v) => _checklist.designPressure = v),
                _buildTextField('test_pressure', 'Пробное давление гидравлического испытания, МПа', (v) => _checklist.testPressure = v),
                _buildTextField('working_temperature', 'Допустимая рабочая температура стенки, ℃', (v) => _checklist.workingTemperature = v),
                _buildTextField('design_temperature', 'Расчётная температура стенки, ℃', (v) => _checklist.designTemperature = v),
                _buildTextField('working_medium', 'Наименование рабочей среды', (v) => _checklist.workingMedium = v),
                _buildTextField('medium_characteristics', 'Характеристика рабочей среды', (v) => _checklist.mediumCharacteristics = v),
                _buildTextField('vessel_group', 'Группа сосуда', (v) => _checklist.vesselGroup = v),
                _buildTextField('medium_group', 'Группа рабочей среды', (v) => _checklist.mediumGroup = v),
                _buildTextField('corrosion_allowance', 'Прибавка для компенсации коррозии, мм', (v) => _checklist.corrosionAllowance = v),
                _buildSectionHeader('Анализ результатов предыдущих обследований'),
                _buildMultilineField('previous_inspection_result', 'Замечания по результатам предыдущих обследований', (v) => _checklist.previousInspectionResult = v),
              ],
              // Поля для компрессоров
              if (_isCompressor) ...[
                Builder(
                  builder: (context) {
                    final compressorChecklist =
                        _checklist as CompressorChecklist;
                    return Column(
                      children: [
                        _buildTextField('compressor_type', 'Тип компрессора',
                            (value) {
                          compressorChecklist.compressorType = value;
                        }),
                        _buildTextField('power_rating', 'Мощность', (value) {
                          compressorChecklist.powerRating = value;
                        }),
                        _buildTextField('pressure_ratio', 'Степень сжатия',
                            (value) {
                          compressorChecklist.pressureRatio = value;
                        }),
                        _buildTextField('flow_rate', 'Производительность',
                            (value) {
                          compressorChecklist.flowRate = value;
                        }),
                        _buildTextField('rotation_speed', 'Частота вращения',
                            (value) {
                          compressorChecklist.rotationSpeed = value;
                        }),
                        _buildTextField(
                            'number_of_stages', 'Количество ступеней', (value) {
                          compressorChecklist.numberOfStages = value;
                        }),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              _buildPhotoSection(
                  'Фото заводской таблички', _factoryPlatePhoto, true),
              const SizedBox(height: 24),
              _buildSectionHeader('4. Проверки'),
              _buildYesNoField(
                  'matches_drawing', 'Соответствует ли сосуд чертежу', (value) {
                _checklist.matchesDrawing = value == 'yes';
              }),
              _buildYesNoField(
                  'has_thermal_insulation', 'Наличие тепловой изоляции',
                  (value) {
                _checklist.hasThermalInsulation = value == 'yes';
              }),
              _buildDropdownField(
                  'anticorrosion_coating',
                  'Состояние антикоррозионного покрытия',
                  ChecklistConstants.states, (value) {
                _checklist.anticorrosionCoatingState = value;
              }),
              _buildDropdownField('support_state', 'Состояние опор сосуда',
                  ChecklistConstants.states, (value) {
                _checklist.supportState = value;
              }),
              _buildDropdownField(
                  'fasteners_state',
                  'Состояние крепежных элементов',
                  ChecklistConstants.states, (value) {
                _checklist.fastenersState = value;
              }),
              _buildYesNoField(
                  'has_flange_misalignment', 'Перекосы фланцевых соединений',
                  (value) {
                _checklist.hasFlangeMisalignment = value == 'yes';
              }),
              _buildYesNoField(
                  'has_nozzle_misalignment', 'Непрямолинейность патрубков',
                  (value) {
                _checklist.hasNozzleMisalignment = value == 'yes';
              }),
              _buildYesNoField(
                  'has_vessel_repairs', 'Имеются ли места ремонта сосуда',
                  (value) {
                _checklist.hasVesselRepairs = value == 'yes';
              }),
              _buildYesNoField(
                  'has_tpa_repairs', 'Имеются ли места ремонта ТПА', (value) {
                _checklist.hasTpaRepairs = value == 'yes';
              }),
              _buildTextField(
                  'internal_devices_state', 'Состояние внутренних устройств',
                  (value) {
                _checklist.internalDevicesState = value;
              }),
              const SizedBox(height: 24),
              _buildSectionHeader('5. ЗРА (Запорно-регулирующая арматура)'),
              _buildAddItemButton('Добавить ЗРА', () {
                _showZraDialog();
              }),
              ..._checklist.zraItems.asMap().entries.map((e) {
                final idx = e.key;
                final item = e.value;
                return _buildListItemCard(
                  title: 'ЗРА №${idx + 1}',
                  subtitle: [
                    if (item.typeSize != null && item.typeSize!.isNotEmpty)
                      'Тип/размер: ${item.typeSize}',
                    if (item.serialNumber != null &&
                        item.serialNumber!.isNotEmpty)
                      'Зав.№: ${item.serialNumber}',
                    if (item.locationOnScheme != null &&
                        item.locationOnScheme!.isNotEmpty)
                      'Место: ${item.locationOnScheme}',
                  ].join(' • '),
                  onDelete: () {
                    setState(() {
                      _checklist.zraItems.removeAt(idx);
                    });
                  },
                );
              }),
              const SizedBox(height: 24),
              _buildSectionHeader(
                  '6. СППК (Система предохранительных клапанов)'),
              _buildAddItemButton('Добавить СППК', () {
                _showSppkDialog();
              }),
              ..._checklist.sppkItems.asMap().entries.map((e) {
                final idx = e.key;
                final item = e.value;
                return _buildListItemCard(
                  title: 'СППК №${idx + 1}',
                  subtitle: [
                    if (item.typeSize != null && item.typeSize!.isNotEmpty)
                      'Тип/размер: ${item.typeSize}',
                    if (item.serialNumber != null &&
                        item.serialNumber!.isNotEmpty)
                      'Зав.№: ${item.serialNumber}',
                    if (item.locationOnScheme != null &&
                        item.locationOnScheme!.isNotEmpty)
                      'Место: ${item.locationOnScheme}',
                  ].join(' • '),
                  onDelete: () {
                    setState(() {
                      _checklist.sppkItems.removeAt(idx);
                    });
                  },
                );
              }),
              const SizedBox(height: 24),
              _buildSectionHeader('7. Измерительный контроль'),
              _buildSubsectionHeader('Овальность'),
              _buildAddItemButton('Добавить измерение овальности', () {
                _showOvalityDialog();
              }),
              ..._checklist.ovalityMeasurements.asMap().entries.map((e) {
                final idx = e.key;
                final m = e.value;
                return _buildListItemCard(
                  title: 'Овальность, сечение ${m.sectionNumber}',
                  subtitle: [
                    if (m.maxDiameter != null) 'Dmax=${m.maxDiameter}',
                    if (m.minDiameter != null) 'Dmin=${m.minDiameter}',
                    if (m.deviationPercent != null) 'Δ%=${m.deviationPercent}',
                  ].join(' • '),
                  onTap: () => _showOvalityDialog(editM: m, editIndex: idx),
                  onDelete: () => setState(
                      () => _checklist.ovalityMeasurements.removeAt(idx)),
                );
              }),
              _buildSubsectionHeader('Прогиб'),
              _buildAddItemButton('Добавить измерение прогиба', () {
                _showDeflectionDialog();
              }),
              ..._checklist.deflectionMeasurements.asMap().entries.map((e) {
                final idx = e.key;
                final m = e.value;
                return _buildListItemCard(
                  title: 'Прогиб, участок ${m.sectionNumber}',
                  subtitle: [
                    if (m.deflectionMm != null) 'мм=${m.deflectionMm}',
                    if (m.deflectionPercent != null) '%=${m.deflectionPercent}',
                  ].join(' • '),
                  onDelete: () => setState(
                      () => _checklist.deflectionMeasurements.removeAt(idx)),
                );
              }),
              const SizedBox(height: 24),
              _buildSectionHeader('8. Результаты контроля твердости'),
              _buildAddItemButton('Добавить измерение твердости', () {
                _showHardnessDialog();
              }),
              ..._checklist.hardnessTests.asMap().entries.map((e) {
                final idx = e.key;
                final t = e.value;
                return _buildListItemCard(
                  title: 'Твердость, шов ${t.weldNumber}',
                  subtitle: [
                    if (t.areaNumber != null && t.areaNumber!.isNotEmpty)
                      'Участок: ${t.areaNumber}',
                    if (t.hardnessBase != null && t.hardnessBase!.isNotEmpty)
                      'Осн: ${t.hardnessBase}',
                    if (t.hardnessWeld != null && t.hardnessWeld!.isNotEmpty)
                      'Шов: ${t.hardnessWeld}',
                    if (t.hardnessHaz != null && t.hardnessHaz!.isNotEmpty)
                      'ЗТВ: ${t.hardnessHaz}',
                  ].join(' • '),
                  onDelete: () =>
                      setState(() => _checklist.hardnessTests.removeAt(idx)),
                );
              }),
              const SizedBox(height: 24),
              _buildSectionHeader('9. Результаты ПВК (МК) и УЗК'),
              _buildAddItemButton('Добавить сварное соединение', () {
                _showWeldInspectionDialog();
              }),
              ..._checklist.weldInspections.asMap().entries.map((e) {
                final idx = e.key;
                final w = e.value;
                return _buildListItemCard(
                  title: 'Сварное соединение ${w.weldNumber}',
                  subtitle: [
                    if (w.pvkDefect != null && w.pvkDefect!.isNotEmpty)
                      'ПВК/МК: ${w.pvkDefect}',
                    if (w.uzkDefect != null && w.uzkDefect!.isNotEmpty)
                      'УЗК: ${w.uzkDefect}',
                    if (w.xPercent != null && w.yPercent != null)
                      'Схема: ${w.xPercent!.toStringAsFixed(0)}%, ${w.yPercent!.toStringAsFixed(0)}%',
                    if (w.conclusion != null && w.conclusion!.isNotEmpty)
                      'Заключение: ${w.conclusion}',
                  ].where((s) => s.isNotEmpty).join(' • '),
                  onTap: () => _showWeldInspectionDialog(editWeld: w, editIndex: idx),
                  onDelete: () =>
                      setState(() => _checklist.weldInspections.removeAt(idx)),
                );
              }),
              const SizedBox(height: 24),
              _buildSectionHeader('10. УЗТ (Ультразвуковая толщинометрия)'),
              _buildPhotoSection('Схема контроля', _controlSchemeImage, false),
              _buildAddItemButton('Открыть карту замеров', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ThicknessMeasurementScreen(
                      schemeImage: _controlSchemeImage,
                      existingMeasurements: _checklist.thicknessMeasurements,
                      equipment: widget.equipment,
                      onSave: (measurements, image) {
                        setState(() {
                          _checklist.thicknessMeasurements = measurements;
                          if (image != null) {
                            _controlSchemeImage = image;
                          }
                        });
                      },
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
              _buildSectionHeader('11. Дефекты'),
              _buildYesNoField(
                  'has_local_deformations', 'Локально деформированные зоны',
                  (value) {
                _checklist.hasLocalDeformations = value == 'yes';
              }),
              _buildYesNoField(
                  'has_external_defects', 'Дефекты при наружном осмотре',
                  (value) {
                _checklist.hasExternalDefects = value == 'yes';
              }),
              _buildYesNoField(
                  'has_internal_defects', 'Дефекты при внутреннем осмотре',
                  (value) {
                _checklist.hasInternalDefects = value == 'yes';
              }),
              _buildYesNoField('has_armature_defects', 'Дефекты арматуры',
                  (value) {
                _checklist.hasArmatureDefects = value == 'yes';
              }),
              const SizedBox(height: 12),
              _buildVisualDefectsSection(),
              const SizedBox(height: 24),
              _buildSectionHeader('12. Заключение'),
              _buildMultilineField('conclusion', 'Заключение', (value) {
                _checklist.conclusion = value;
              }),
              const SizedBox(height: 32),
              if (_lastAutoSaveTime != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Последнее сохранение черновика: ${intl.DateFormat('dd.MM HH:mm').format(_lastAutoSaveTime!)}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              _buildSubmitButton(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF3b82f6),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildListItemCard({
    required String title,
    required String subtitle,
    required VoidCallback onDelete,
    VoidCallback? onTap,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            tooltip: 'Удалить',
          ),
        ],
      ),
    );
    return Card(
      color: const Color(0xFF1e293b),
      margin: const EdgeInsets.only(bottom: 8),
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: content,
            )
          : content,
    );
  }

  Future<void> _showZraDialog() async {
    final qty = TextEditingController();
    final typeSize = TextEditingController();
    final tech = TextEditingController();
    final serial = TextEditingController();
    final loc = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title:
            const Text('Добавить ЗРА', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogTextField(qty, 'Кол-во'),
              _dialogTextField(typeSize, 'Тип/размер'),
              _dialogTextField(tech, 'Тех. №'),
              _dialogTextField(serial, 'Зав. №'),
              _dialogTextField(loc, 'Место на схеме'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Добавить')),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        final item = ZraItem();
        item.quantity = qty.text.trim().isEmpty ? null : qty.text.trim();
        item.typeSize =
            typeSize.text.trim().isEmpty ? null : typeSize.text.trim();
        item.techNumber = tech.text.trim().isEmpty ? null : tech.text.trim();
        item.serialNumber =
            serial.text.trim().isEmpty ? null : serial.text.trim();
        item.locationOnScheme =
            loc.text.trim().isEmpty ? null : loc.text.trim();
        _checklist.zraItems.add(item);
      });
    }
  }

  Future<void> _showSppkDialog() async {
    final qty = TextEditingController();
    final typeSize = TextEditingController();
    final tech = TextEditingController();
    final serial = TextEditingController();
    final loc = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title:
            const Text('Добавить СППК', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogTextField(qty, 'Кол-во'),
              _dialogTextField(typeSize, 'Тип/размер'),
              _dialogTextField(tech, 'Тех. №'),
              _dialogTextField(serial, 'Зав. №'),
              _dialogTextField(loc, 'Место на схеме'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Добавить')),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        final item = SppkItem();
        item.quantity = qty.text.trim().isEmpty ? null : qty.text.trim();
        item.typeSize =
            typeSize.text.trim().isEmpty ? null : typeSize.text.trim();
        item.techNumber = tech.text.trim().isEmpty ? null : tech.text.trim();
        item.serialNumber =
            serial.text.trim().isEmpty ? null : serial.text.trim();
        item.locationOnScheme =
            loc.text.trim().isEmpty ? null : loc.text.trim();
        _checklist.sppkItems.add(item);
      });
    }
  }

  Future<void> _showOvalityDialog({OvalityMeasurement? editM, int? editIndex}) async {
    final section = TextEditingController(
        text: editM?.sectionNumber ?? '${_checklist.ovalityMeasurements.length + 1}');
    final maxD = TextEditingController(
        text: editM?.maxDiameter != null ? editM!.maxDiameter!.toString() : '');
    final minD = TextEditingController(
        text: editM?.minDiameter != null ? editM!.minDiameter!.toString() : '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: Text(editM != null ? 'Редактировать овальность' : 'Овальность (сечение)',
            style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogTextField(section, 'Номер сечения (I, II, III, 1, 2...)'),
              _dialogTextField(maxD, 'Макс. диаметр (мм)',
                  keyboard: TextInputType.number),
              _dialogTextField(minD, 'Мин. диаметр (мм)',
                  keyboard: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(editM != null ? 'Сохранить' : 'Добавить')),
        ],
      ),
    );

    if (ok == true) {
      final maxVal = double.tryParse(maxD.text.replaceAll(',', '.'));
      final minVal = double.tryParse(minD.text.replaceAll(',', '.'));
      double? dev;
      if (maxVal != null && minVal != null && maxVal != 0) {
        dev = ((maxVal - minVal) / maxVal) * 100.0;
      }
      setState(() {
        final m = OvalityMeasurement(
          sectionNumber: section.text.trim().isEmpty
              ? '${_checklist.ovalityMeasurements.length + 1}'
              : section.text.trim(),
          maxDiameter: maxVal,
          minDiameter: minVal,
          deviationPercent: dev,
        );
        if (editIndex != null) {
          _checklist.ovalityMeasurements[editIndex] = m;
        } else {
          _checklist.ovalityMeasurements.add(m);
        }
      });
    }
  }

  Future<void> _showDeflectionDialog() async {
    final section = TextEditingController(
        text: '${_checklist.deflectionMeasurements.length + 1}');
    final mm = TextEditingController();
    final pct = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text('Прогиб', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogTextField(section, 'Номер участка'),
              _dialogTextField(mm, 'Прогиб (мм)',
                  keyboard: TextInputType.number),
              _dialogTextField(pct, 'Прогиб (%)',
                  keyboard: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Добавить')),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        _checklist.deflectionMeasurements.add(
          DeflectionMeasurement(
            sectionNumber: section.text.trim().isEmpty
                ? '${_checklist.deflectionMeasurements.length + 1}'
                : section.text.trim(),
            deflectionMm: double.tryParse(mm.text.replaceAll(',', '.')),
            deflectionPercent: double.tryParse(pct.text.replaceAll(',', '.')),
          ),
        );
      });
    }
  }

  Future<void> _showHardnessDialog() async {
    final weld = TextEditingController();
    final area = TextEditingController();
    final allowedBase = TextEditingController();
    final allowedWeld = TextEditingController();
    final base = TextEditingController();
    final w = TextEditingController();
    final haz = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text('Твердость', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogTextField(weld, 'Номер шва *'),
              _dialogTextField(area, 'Номер участка'),
              _dialogTextField(allowedBase, 'Допустимая твердость (осн.)'),
              _dialogTextField(allowedWeld, 'Допустимая твердость (шов)'),
              _dialogTextField(base, 'Твердость (осн.)'),
              _dialogTextField(w, 'Твердость (шов)'),
              _dialogTextField(haz, 'Твердость (ЗТВ)'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Добавить')),
        ],
      ),
    );

    if (ok == true && weld.text.trim().isNotEmpty) {
      setState(() {
        final t = HardnessTest(weldNumber: weld.text.trim());
        t.areaNumber = area.text.trim().isEmpty ? null : area.text.trim();
        t.allowedHardnessBase =
            allowedBase.text.trim().isEmpty ? null : allowedBase.text.trim();
        t.allowedHardnessWeld =
            allowedWeld.text.trim().isEmpty ? null : allowedWeld.text.trim();
        t.hardnessBase = base.text.trim().isEmpty ? null : base.text.trim();
        t.hardnessWeld = w.text.trim().isEmpty ? null : w.text.trim();
        t.hardnessHaz = haz.text.trim().isEmpty ? null : haz.text.trim();
        _checklist.hardnessTests.add(t);
      });
    }
  }

  Future<void> _showWeldInspectionDialog({WeldInspection? editWeld, int? editIndex}) async {
    final weld = TextEditingController(text: editWeld?.weldNumber ?? '');
    final loc = TextEditingController(text: editWeld?.locationOnControlMap ?? '');
    final pvk = TextEditingController(text: editWeld?.pvkDefect ?? '');
    final uzk = TextEditingController(text: editWeld?.uzkDefect ?? '');
    final xPercent = TextEditingController(
        text: editWeld?.xPercent != null ? editWeld!.xPercent!.toStringAsFixed(1) : '');
    final yPercent = TextEditingController(
        text: editWeld?.yPercent != null ? editWeld!.yPercent!.toStringAsFixed(1) : '');
    String conclusion = editWeld?.conclusion ?? ChecklistConstants.weldConclusions.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: Text(editWeld != null ? 'Редактировать сварное соединение' : 'Сварное соединение',
            style: const TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (context, setInner) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogTextField(weld, 'Номер шва *'),
                _dialogTextField(loc, 'Место на карте контроля'),
                _dialogTextField(pvk, 'Дефект (ПВК/МК)'),
                _dialogTextField(uzk, 'Дефект (УЗК)'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _dialogTextField(
                        xPercent,
                        'X % на схеме',
                        keyboard: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _dialogTextField(
                        yPercent,
                        'Y % на схеме',
                        keyboard: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: conclusion,
                  decoration: const InputDecoration(
                    labelText: 'Заключение',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue)),
                  ),
                  dropdownColor: const Color(0xFF1e293b),
                  items: ChecklistConstants.weldConclusions
                      .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c,
                              style: const TextStyle(color: Colors.white))))
                      .toList(),
                  onChanged: (v) =>
                      setInner(() => conclusion = v ?? conclusion),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(editWeld != null ? 'Сохранить' : 'Добавить')),
        ],
      ),
    );

    if (ok == true && weld.text.trim().isNotEmpty) {
      setState(() {
        final w = editWeld ?? WeldInspection(weldNumber: weld.text.trim());
        w.weldNumber = weld.text.trim();
        w.locationOnControlMap =
            loc.text.trim().isEmpty ? null : loc.text.trim();
        w.pvkDefect = pvk.text.trim().isEmpty ? null : pvk.text.trim();
        w.uzkDefect = uzk.text.trim().isEmpty ? null : uzk.text.trim();
        w.conclusion = conclusion;
        final xVal = double.tryParse(xPercent.text.trim().replaceAll(',', '.'));
        final yVal = double.tryParse(yPercent.text.trim().replaceAll(',', '.'));
        w.xPercent = (xVal != null && xVal >= 0 && xVal <= 100) ? xVal : null;
        w.yPercent = (yVal != null && yVal >= 0 && yVal <= 100) ? yVal : null;
        if (editIndex != null) {
          _checklist.weldInspections[editIndex] = w;
        } else {
          _checklist.weldInspections.add(w);
        }
      });
    }
  }

  Widget _dialogTextField(
    TextEditingController controller,
    String label, {
    TextInputType keyboard = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.blue)),
        ),
      ),
    );
  }

  Widget _buildSubsectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTextField(
      String name, String label, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FormBuilderTextField(
        name: name,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF1e293b),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3b82f6), width: 2),
          ),
        ),
        style: const TextStyle(color: Colors.white),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildMultilineField(
      String name, String label, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FormBuilderTextField(
        name: name,
        maxLines: 5,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF1e293b),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3b82f6), width: 2),
          ),
        ),
        style: const TextStyle(color: Colors.white),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDateField(
      String name, String label, Function(DateTime?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FormBuilderDateTimePicker(
        name: name,
        inputType: InputType.date,
        format: intl.DateFormat('yyyy-MM-dd'),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF1e293b),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3b82f6), width: 2),
          ),
          suffixIcon: const Icon(Icons.calendar_today, color: Colors.white70),
        ),
        style: const TextStyle(color: Colors.white),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildYesNoField(
      String name, String label, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FormBuilderRadioGroup<String>(
        name: name,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF1e293b),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3b82f6), width: 2),
          ),
        ),
        options: const [
          FormBuilderFieldOption(
              value: 'yes',
              child: Text('Да', style: TextStyle(color: Colors.white))),
          FormBuilderFieldOption(
              value: 'no',
              child: Text('Нет', style: TextStyle(color: Colors.white))),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildEngineerSelectionSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Инженеры по видам обследований',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_loadingEngineers)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_engineers.isEmpty)
            const Text(
              'Список инженеров не загружен. Подключитесь к интернету и выполните синхронизацию.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            )
          else ...[
            CheckboxListTile(
              value: _showAllEngineersList,
              onChanged: (v) {
                setState(() {
                  _showAllEngineersList = v ?? false;
                });
              },
              title: const Text(
                'Показать весь список специалистов (выбрать любого, даже без удостоверения по виду)',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              activeColor: Colors.blue,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            _buildEngineerRow('ВИК', 'VIK'),
            const SizedBox(height: 10),
            _buildEngineerRow('УЗК', 'UZK'),
            const SizedBox(height: 10),
            _buildEngineerRow('УЗТ', 'UZT'),
            const SizedBox(height: 10),
            _buildEngineerRow('ПВК/МК', 'PVK'),
          ],
        ],
      ),
    );
  }

  Widget _buildEngineerRow(String label, String methodKey) {
    final content = _buildEngineerDropdown(label, methodKey);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildEngineerDropdown(String label, String methodKey) {
    final filteredEngineers = _engineers.where((engineer) {
      var qualifications = engineer['qualifications'];
      if (qualifications == null) return false;
      if (qualifications is String) {
        try {
          qualifications = json.decode(qualifications);
        } catch (_) {
          return false;
        }
      }
      if (qualifications is List) {
        for (final qual in qualifications) {
          if (qual is Map) {
            final method = qual['method']?.toString().toUpperCase() ??
                qual['ndt_method']?.toString().toUpperCase() ??
                '';
            final methodCode =
                qual['method_code']?.toString().toUpperCase() ?? '';
            if (methodKey == 'VIK' &&
                (method.contains('ВИК') ||
                    method.contains('VIK') ||
                    methodCode == 'VIK')) {
              return true;
            }
            if (methodKey == 'UZK' &&
                (method.contains('УЗК') ||
                    method.contains('UZK') ||
                    methodCode == 'UZK')) {
              return true;
            }
            if (methodKey == 'UZT' &&
                (method.contains('УЗТ') ||
                    method.contains('UZT') ||
                    methodCode == 'UZT')) {
              return true;
            }
            if (methodKey == 'PVK' &&
                (method.contains('ПВК') ||
                    method.contains('МК') ||
                    method.contains('PVK') ||
                    method.contains('MK') ||
                    methodCode == 'PVK' ||
                    methodCode == 'MK')) {
              return true;
            }
          }
        }
      }
      return false;
    }).toList();

    final engineersToShow = _showAllEngineersList ? _engineers : filteredEngineers;
    final selected = _selectedEngineerByMethod[methodKey];

    if (engineersToShow.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange),
          ),
          child: Text(
            '$label: нет специалистов с соответствующим удостоверением. Включите «Показать весь список» выше.',
            style: const TextStyle(color: Colors.orange, fontSize: 12),
          ),
        ),
      );
    }

    return InputDecorator(
      decoration: InputDecoration(
        labelText: _showAllEngineersList ? 'весь список' : null,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
        filled: true,
        fillColor: const Color(0xFF0f172a),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Map<String, dynamic>>(
          value: selected,
          isExpanded: true,
          dropdownColor: const Color(0xFF1e293b),
          selectedItemBuilder: (context) {
            return engineersToShow.map((e) {
              final name = (e['full_name'] ?? '').toString();
              return Text(
                name,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            }).toList();
          },
          items: engineersToShow.map((e) {
            final name = (e['full_name'] ?? '').toString();
            final position = (e['position'] ?? '').toString();
            final qualifications = e['qualifications'];
            String certInfo = '';
            if (qualifications is List && qualifications.isNotEmpty) {
              for (final qual in qualifications) {
                if (qual is Map) {
                  final method = qual['method']?.toString() ??
                      qual['ndt_method']?.toString() ?? '';
                  final methodCode = qual['method_code']?.toString() ?? '';
                  bool matches = false;
                  if (methodKey == 'VIK' &&
                      (method.contains('ВИК') || method.contains('VIK') ||
                          methodCode == 'VIK')) {
                    matches = true;
                  }
                  if (methodKey == 'UZK' &&
                      (method.contains('УЗК') || method.contains('UZK') ||
                          methodCode == 'UZK')) {
                    matches = true;
                  }
                  if (methodKey == 'UZT' &&
                      (method.contains('УЗТ') || method.contains('UZT') ||
                          methodCode == 'UZT')) {
                    matches = true;
                  }
                  if (methodKey == 'PVK' &&
                      (method.contains('ПВК') || method.contains('МК') ||
                          method.contains('PVK') || method.contains('MK') ||
                          methodCode == 'PVK' || methodCode == 'MK')) {
                    matches = true;
                  }
                  if (matches) {
                    final certNum = qual['number']?.toString() ??
                        qual['certificate_number']?.toString() ?? '';
                    final validUntil = qual['valid_until']?.toString() ??
                        qual['expiry_date']?.toString() ?? '';
                    if (certNum.isNotEmpty) {
                      certInfo = 'Удост. $certNum';
                      if (validUntil.isNotEmpty) {
                        certInfo += ', до $validUntil';
                      }
                    }
                    break;
                  }
                }
              }
            }
            return DropdownMenuItem<Map<String, dynamic>>(
              value: e,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      position.isNotEmpty ? '$name — $position' : name,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (certInfo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        certInfo,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
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
                          (json.decode(saved) as Map).map(
                            (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
                          ))
                      : <String, String>{};
                  map[methodKey] = id;
                  await prefs.setString(
                      'last_engineers_by_method', json.encode(map));
                } catch (_) {}
              });
            }
          },
        ),
      ),
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
      // Пытаемся достать сведения о сертификатах (если есть)
      final qualifications = e['qualifications'];
      if (qualifications is List && qualifications.isNotEmpty) {
        final q = qualifications.first;
        if (q is Map) {
          ie.certificateNumber =
              q['number']?.toString() ?? q['certificate_number']?.toString();
          ie.validUntil =
              q['valid_until']?.toString() ?? q['expiry_date']?.toString();
        }
      }
      result.add(ie);
      if (m.isNotEmpty) methods.add(m);
    }
    _checklist.inspectionEngineers = result;
    _checklist.ndtMethods = methods;
  }

  Widget _buildVisualDefectsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Дефекты ВИК (фото/замеры)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_checklist.visualDefects.isEmpty)
            const Text(
              'Дефекты не добавлены',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            )
          else
            Column(
              children: _checklist.visualDefects.asMap().entries.map((entry) {
                final idx = entry.key;
                final d = entry.value;
                return ListTile(
                  dense: true,
                  title: Text(
                    d.defectType ?? 'Дефект',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    [
                      if (d.location != null && d.location!.isNotEmpty)
                        'Место: ${d.location}',
                      if (d.size != null && d.size!.isNotEmpty)
                        'Размер: ${d.size}',
                      if (d.description != null && d.description!.isNotEmpty)
                        d.description,
                    ].join(' | '),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () {
                      setState(() {
                        _checklist.visualDefects.removeAt(idx);
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: _addVisualDefectDialog,
              icon: const Icon(Icons.add),
              label: const Text('Добавить дефект'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3b82f6),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addVisualDefectDialog() async {
    String? defectType;
    String? location;
    String? size;
    String? description;
    String? photoPath;

    final defectTypes = [
      'Коррозия',
      'Вмятина',
      'Трещина',
      'Разрыв',
      'Скол',
      'Потеря металла',
      'Другое',
    ];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Дефект ВИК'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: defectType,
                  decoration: const InputDecoration(labelText: 'Тип дефекта'),
                  items: defectTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setLocalState(() => defectType = v),
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Место/узел'),
                  onChanged: (v) => location = v,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Размер (мм)'),
                  onChanged: (v) => size = v,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Описание'),
                  onChanged: (v) => description = v,
                ),
                const SizedBox(height: 8),
                if (photoPath != null)
                  Text(
                    'Фото: ${Path.basename(photoPath!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final p = await _pickDefectPhoto(ImageSource.camera);
                        if (p != null) {
                          setLocalState(() => photoPath = p);
                        }
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Камера'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final p = await _pickDefectPhoto(ImageSource.gallery);
                        if (p != null) {
                          setLocalState(() => photoPath = p);
                        }
                      },
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Галерея'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                final d = VisualDefect();
                d.defectType = defectType;
                d.location = location;
                d.size = size;
                d.description = description;
                if (photoPath != null) {
                  d.photos = [photoPath!];
                }
                setState(() {
                  _checklist.visualDefects.add(d);
                });
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickDefectPhoto(ImageSource source) async {
    try {
      final picked =
          await _imagePicker.pickImage(source: source, imageQuality: 80);
      if (picked == null) return null;
      final withMeta = await _maybeAddDateTimeGpsToPhoto(picked.path);
      final persistedPath = await _persistPickedFile(
        sourcePath: withMeta,
        fileName: Path.basename(withMeta),
        documentNumber: 'vik_defect',
      );
      return persistedPath;
    } catch (_) {
      return null;
    }
  }

  Widget _buildOpoSelectionField() {
    if (_loadingOpos) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_opos.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: FormBuilderDropdown<String>(
        name: 'opo_id',
        decoration: InputDecoration(
          labelText: 'ОПО (Опасный производственный объект)',
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF1e293b),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.blue),
          ),
        ),
        initialValue: _selectedOpoId,
        items: _opos.map((opo) {
          final id = opo['id'] as String? ?? '';
          final name = opo['name'] as String? ?? 'Без названия';
          final code = opo['code'] as String?;
          final displayName = code != null ? '$name ($code)' : name;
          return DropdownMenuItem<String>(
            value: id,
            child: Text(
              displayName,
              style: const TextStyle(color: Colors.white),
            ),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            _selectedOpoId = value;
          });
          if (value != null && value.isNotEmpty) {
            SharedPreferences.getInstance().then((prefs) {
              prefs.setString('last_opo_id', value);
            });
          }
          // Обновляем оборудование на сервере с выбранным ОПО
          if (value != null && value.isNotEmpty) {
            _apiService.updateEquipmentOpo(
              equipmentId: widget.equipment.id,
              opoId: value,
            ).catchError((e) {
              print('Ошибка обновления ОПО оборудования: $e');
            });
          }
        },
        style: const TextStyle(color: Colors.white),
        dropdownColor: const Color(0xFF1e293b),
      ),
    );
  }

  Widget _buildDropdownField(String name, String label, List<String> items,
      Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FormBuilderDropdown<String>(
        name: name,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF1e293b),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3b82f6), width: 2),
          ),
        ),
        items: items
            .map((item) => DropdownMenuItem(
                  value: item,
                  child:
                      Text(item, style: const TextStyle(color: Colors.white)),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _pickDocumentFile(String documentNumber) async {
    try {
      // Показываем диалог выбора типа файла
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1e293b),
          title: const Text(
            'Выберите файл',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue, size: 28),
                title: const Text(
                  'Камера',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final image =
                      await _imagePicker.pickImage(source: ImageSource.camera);
                  if (image != null) {
                    _handleDocumentFile(documentNumber, image.path, image.name);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green, size: 28),
                title: const Text(
                  'Галерея',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final image =
                      await _imagePicker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    _handleDocumentFile(documentNumber, image.path, image.name);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('PDF файл',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf'],
                    withData:
                        true, // чтобы поддержать случаи, когда path == null
                  );
                  if (result != null) {
                    final picked = result.files.single;
                    String? pickedPath = picked.path;
                    if (pickedPath == null && picked.bytes != null) {
                      pickedPath = await _persistPickedBytes(
                        fileName: picked.name,
                        bytes: picked.bytes!,
                        documentNumber: documentNumber,
                      );
                    }
                    if (pickedPath != null) {
                      _handleDocumentFile(
                        documentNumber,
                        pickedPath,
                        picked.name,
                      );
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Не удалось получить путь к файлу PDF'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора файла: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String> _persistPickedBytes({
    required String fileName,
    required Uint8List bytes,
    required String documentNumber,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final storageDir = Directory(Path.join(dir.path, 'offline_documents'));
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    final safeName =
        fileName.isNotEmpty ? fileName : 'document_$documentNumber.pdf';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final targetPath = Path.join(
      storageDir.path,
      '${documentNumber}_${ts}_$safeName',
    );
    final f = File(targetPath);
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
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

  Future<void> _handleDocumentFile(
      String documentNumber, String filePath, String fileName) async {
    // Копируем файл в директорию приложения, чтобы он гарантированно был доступен при последующей синхронизации
    String persistedPath = filePath;
    try {
      if (await File(filePath).exists()) {
        persistedPath = await _persistPickedFile(
          sourcePath: filePath,
          fileName: fileName,
          documentNumber: documentNumber,
        );
      }
    } catch (_) {
      // Если не удалось скопировать, оставляем исходный путь
    }

    setState(() {
      _documentFiles[documentNumber] = persistedPath;
    });

    // Если questionnaire_id уже есть, загружаем файл сразу
    if (_questionnaireId != null) {
      try {
        await _apiService.uploadDocumentFile(
          questionnaireId: _questionnaireId!,
          documentNumber: documentNumber,
          filePath: persistedPath,
          fileName: fileName,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Файл успешно загружен'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки файла: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildDocumentCheckbox(Map<String, String> doc) {
    final documentNumber = doc['number']!;
    final hasFile = _documentFiles.containsKey(documentNumber);
    final isChecked = _checklist.documents[documentNumber] ?? false;
    final info = _checklist.documentsInfo[documentNumber] ?? {'number': '', 'date': ''};
    DateTime? infoDate;
    if ((info['date'] ?? '').isNotEmpty) {
      try {
        infoDate = DateTime.parse(info['date']!);
      } catch (_) {
        infoDate = null;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: const Color(0xFF1e293b),
        child: Column(
          children: [
            CheckboxListTile(
              title: Text(
                '${doc['number']}. ${doc['name']}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              value: isChecked,
              onChanged: (value) {
                setState(() {
                  _checklist.documents[documentNumber] = value ?? false;
                  if ((value ?? false) &&
                      !_checklist.documentsInfo.containsKey(documentNumber)) {
                    _checklist.documentsInfo[documentNumber] = {
                      'number': '',
                      'date': '',
                    };
                  }
                  // Если снимаем галочку, удаляем файл
                  if (value == false && hasFile) {
                    _documentFiles.remove(documentNumber);
                    // Удаляем файл с сервера, если questionnaire_id есть
                    if (_questionnaireId != null) {
                      _apiService
                          .deleteDocumentFile(
                        questionnaireId: _questionnaireId!,
                        documentNumber: documentNumber,
                      )
                          .catchError((e) {
                        // Игнорируем ошибки при удалении
                      });
                    }
                  }
                });
              },
              activeColor: const Color(0xFF3b82f6),
              secondary: hasFile
                  ? const Icon(Icons.attach_file, color: Colors.green, size: 20)
                  : null,
            ),
            if (isChecked)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    FormBuilderTextField(
                      name: 'doc_number_$documentNumber',
                      initialValue: info['number'],
                      decoration: const InputDecoration(
                        labelText: 'Номер документа',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF3b82f6)),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onChanged: (value) {
                        setState(() {
                          final current = _checklist.documentsInfo[documentNumber] ?? {};
                          _checklist.documentsInfo[documentNumber] = {
                            'number': value ?? '',
                            'date': current['date'] ?? '',
                          };
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    FormBuilderDateTimePicker(
                      name: 'doc_date_$documentNumber',
                      inputType: InputType.date,
                      initialValue: infoDate,
                      decoration: const InputDecoration(
                        labelText: 'Дата документа',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF3b82f6)),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onChanged: (value) {
                        setState(() {
                          final current = _checklist.documentsInfo[documentNumber] ?? {};
                          _checklist.documentsInfo[documentNumber] = {
                            'number': current['number'] ?? '',
                            'date': value != null
                                ? value.toIso8601String().split('T')[0]
                                : '',
                          };
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickDocumentFile(documentNumber),
                            icon: Icon(hasFile ? Icons.edit : Icons.attach_file),
                            label: Text(
                                hasFile ? 'Изменить файл' : 'Прикрепить файл'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              side: const BorderSide(color: Colors.blue),
                            ),
                          ),
                        ),
                        if (hasFile) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _documentFiles.remove(documentNumber);
                              });
                              if (_questionnaireId != null) {
                                _apiService
                                    .deleteDocumentFile(
                                  questionnaireId: _questionnaireId!,
                                  documentNumber: documentNumber,
                                )
                                    .catchError((e) {
                                  // Игнорируем ошибки
                                });
                              }
                            },
                            tooltip: 'Удалить файл',
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection(String title, File? image, bool isFactoryPlate) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (image != null)
            GestureDetector(
              onTap: () {
                if (!image.existsSync()) return;
                showDialog(
                  context: context,
                  barrierColor: Colors.black87,
                  builder: (ctx) => Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: EdgeInsets.zero,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: Center(
                            child: Image.file(image, fit: BoxFit.contain),
                          ),
                        ),
                        Positioned(
                          top: MediaQuery.of(ctx).padding.top + 8,
                          right: 16,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 28),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(image, fit: BoxFit.cover),
                ),
              ),
            )
          else
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1e293b),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF334155), style: BorderStyle.solid),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.camera_alt, color: Colors.white70, size: 48),
                  const SizedBox(height: 8),
                  const Text('Нет фото',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isFactoryPlate
                            ? 'Выберите способ получения фото заводской таблички:'
                            : 'Выберите способ получения схемы контроля:',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _pickImage(
                                  ImageSource.camera, isFactoryPlate),
                              icon: const Icon(Icons.camera, color: Colors.white),
                              label: Text(
                                isFactoryPlate
                                    ? 'Сфотографировать табличку'
                                    : 'Сфотографировать схему',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3b82f6),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _pickImage(
                                  ImageSource.gallery, isFactoryPlate),
                              icon: const Icon(Icons.photo_library, color: Colors.white),
                              label: const Text(
                                'Выбрать из галереи',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3b82f6),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!isFactoryPlate) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickImageFromFile,
                                icon: const Icon(Icons.folder_open, color: Color(0xFF3b82f6), size: 20),
                                label: const Text(
                                  'Файл',
                                  style: TextStyle(
                                    color: Color(0xFF3b82f6),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF3b82f6)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickBuiltInTemplate,
                                icon: const Icon(Icons.dashboard_customize, color: Color(0xFF3b82f6), size: 20),
                                label: const Text(
                                  'Встроенный шаблон',
                                  style: TextStyle(
                                    color: Color(0xFF3b82f6),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF3b82f6)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _pickStandardDrawing,
                            icon: const Icon(Icons.cloud_download, color: Color(0xFF3b82f6)),
                            label: const Text(
                              'Шаблон с сервера',
                              style: TextStyle(
                                color: Color(0xFF3b82f6),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF3b82f6)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddItemButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF3b82f6),
          side: const BorderSide(color: Color(0xFF3b82f6)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  /// Подсчет заполненных полей для прогресса
  Map<String, int> _calculateProgress() {
    int completed = 0;
    int total = 0;
    List<String> missingRequired = [];

    // Основная информация
    total += 3;
    if (_checklist.inspectionDate != null && _checklist.inspectionDate!.isNotEmpty) completed++;
    else missingRequired.add('Дата обследования');
    if (_checklist.executors != null && _checklist.executors!.isNotEmpty) completed++;
    else missingRequired.add('Исполнители');
    if (_checklist.organization != null && _checklist.organization!.isNotEmpty) completed++;
    else missingRequired.add('Организация');

    // Оборудование для поверок
    total += 1;
    if (_selectedEquipmentIds.isNotEmpty) completed++;
    else missingRequired.add('Оборудование для поверок');

    // Карта обследования
    total += 5;
    if (_checklist.vesselName != null && _checklist.vesselName!.isNotEmpty) completed++;
    if (_checklist.serialNumber != null && _checklist.serialNumber!.isNotEmpty) completed++;
    if (_checklist.regNumber != null && _checklist.regNumber!.isNotEmpty) completed++;
    if (_checklist.manufacturer != null && _checklist.manufacturer!.isNotEmpty) completed++;
    if (_checklist.manufactureYear != null && _checklist.manufactureYear!.isNotEmpty) completed++;

    // Фото заводской таблички
    total += 1;
    if (_factoryPlatePhoto != null || (_checklist.factoryPlatePhoto != null && _checklist.factoryPlatePhoto!.isNotEmpty)) completed++;
    else missingRequired.add('Фото заводской таблички');

    // Заключение
    total += 1;
    if (_checklist.conclusion != null && _checklist.conclusion!.isNotEmpty) completed++;
    else missingRequired.add('Заключение');

    return {
      'completed': completed,
      'total': total,
      'missing': missingRequired.length,
    };
  }

  Widget _buildProgressIndicator() {
    final progress = _calculateProgress();
    final completed = progress['completed']!;
    final total = progress['total']!;
    final missing = progress['missing']!;
    
    List<String> missingRequired = [];
    if (_checklist.inspectionDate == null || _checklist.inspectionDate!.isEmpty) missingRequired.add('Дата обследования');
    if (_checklist.executors == null || _checklist.executors!.isEmpty) missingRequired.add('Исполнители');
    if (_checklist.organization == null || _checklist.organization!.isEmpty) missingRequired.add('Организация');
    if (_selectedEquipmentIds.isEmpty) missingRequired.add('Оборудование для поверок');
    if (_factoryPlatePhoto == null && (_checklist.factoryPlatePhoto == null || _checklist.factoryPlatePhoto!.isEmpty)) missingRequired.add('Фото заводской таблички');
    if (_checklist.conclusion == null || _checklist.conclusion!.isEmpty) missingRequired.add('Заключение');

    return ChecklistProgressIndicator(
      completedFields: completed,
      totalFields: total,
      missingRequiredFields: missingRequired.isNotEmpty ? missingRequired : null,
    );
  }

  Widget _buildSubmitButton() {
    final isAssignment =
        widget.assignmentId != null && widget.assignmentId!.isNotEmpty;
    return Column(
      children: [
        Semantics(
              label: 'Сохранить черновик осмотра. Данные будут отправлены при синхронизации.',
              button: true,
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _saveDraft,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3b82f6),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Сохранить (черновик)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                ),
              ),
            ),
        if (isAssignment) ...[
          const SizedBox(height: 12),
          Semantics(
            label: 'Подписать и завершить осмотр. После подписи осмотр будет отправлен при синхронизации.',
            button: true,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _signAndFinish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22c55e),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Подписать / Завершить',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
