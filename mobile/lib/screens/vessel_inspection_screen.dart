import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as Path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/equipment.dart';
import '../models/assignment.dart';
import '../data/technical_report_form_registry.dart';
import '../models/vessel_checklist.dart';
import '../models/compressor_checklist.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/location_service.dart';
import '../services/auto_save_service.dart';
import '../services/photo_annotation_service.dart';
import '../services/image_resize_service.dart';
import '../services/last_values_service.dart';
import '../services/checklist_pdf_service.dart';
import '../services/inspection_validation_service.dart';
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
import '../widgets/inspection/inspection_passport_section.dart';
import '../widgets/inspection/inspection_conclusion_section.dart';
import 'image_annotation_screen.dart';

class VesselInspectionScreen extends StatefulWidget {
  final Equipment equipment;
  final String? assignmentId;
  final String? existingInspectionId;
  final String? inspectionType;
  /// Форма технического отчёта (to-1, to-3, …).
  final String? reportFormId;
  /// Предзаполнение из шаблона обследования объекта.
  final Map<String, dynamic>? initialChecklistJson;

  const VesselInspectionScreen({
    super.key,
    required this.equipment,
    this.assignmentId,
    this.existingInspectionId,
    this.inspectionType,
    this.reportFormId,
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
  late TechnicalReportForm _reportForm;
  final ApiService _apiService = ApiService();
  final SyncService _syncService = SyncService();
  final LocationService _locationService = LocationService();
  final AutoSaveService _autoSaveService = AutoSaveService();
  final PhotoAnnotationService _photoAnnotationService = PhotoAnnotationService();
  final LastValuesService _lastValuesService = LastValuesService();
  bool _isSubmitting = false;
  bool _hasUnsavedChanges = false;
  bool _isAutoSaving = false;
  Map<String, double>? _gpsCoordinates;
  DateTime? _lastAutoSaveTime;
  int _formSeed = 0;
  Timer? _autoSaveTimer;
  int? _restorePageIndex;

  List<String> get _pageLabels => _reportForm.navigationLabels;

  /// Не final: при восстановлении черновика подменяем целиком (все поля).
  late VesselChecklist _checklist;

  bool get _isCompressor {
    final typeCode = widget.equipment.typeCode?.toUpperCase() ?? '';
    final typeName = widget.equipment.typeName?.toUpperCase() ?? '';
    return typeCode.contains('COMPRESSOR') ||
        typeCode.contains('КОМПРЕССОР') ||
        typeName.contains('COMPRESSOR') ||
        typeName.contains('КОМПРЕССОР');
  }

  bool get _isGasSeparator {
    final typeCode = widget.equipment.typeCode?.toUpperCase() ?? '';
    final typeName = widget.equipment.typeName?.toUpperCase() ?? '';
    final attrs = widget.equipment.attributes ?? {};
    final objectType = (attrs['object_type'] ?? '').toString().toLowerCase();
    return typeCode.contains('GAS_SEPARATOR') ||
        typeCode.contains('GAS_SEP') ||
        typeName.contains('ГАЗОСЕПАРАТОР') ||
        objectType == 'gas_separator';
  }

  bool get _isUndergroundTank {
    final typeCode = widget.equipment.typeCode?.toUpperCase() ?? '';
    final typeName = widget.equipment.typeName?.toUpperCase() ?? '';
    final attrs = widget.equipment.attributes ?? {};
    final objectType = (attrs['object_type'] ?? '').toString().toLowerCase();
    final eqName = (widget.equipment.name ?? '').toUpperCase();
    return typeCode.contains('UNDERGROUND_TANK') ||
        typeName.contains('ЁМКОСТ') ||
        typeName.contains('ЕМКОСТ') ||
        typeName.contains('ПОДЗЕМН') ||
        eqName.contains('ЁМКОСТ') ||
        eqName.contains('ЕМКОСТ') ||
        objectType == 'underground_tank';
  }

  bool get _isOilSettler {
    final typeCode = widget.equipment.typeCode?.toUpperCase() ?? '';
    final typeName = widget.equipment.typeName?.toUpperCase() ?? '';
    final attrs = widget.equipment.attributes ?? {};
    final objectType = (attrs['object_type'] ?? '').toString().toLowerCase();
    final eqName = (widget.equipment.name ?? '').toUpperCase();
    return typeCode.contains('OIL_SETTLER') ||
        typeName.contains('ОТСТОЙНИК') ||
        eqName.contains('ОТСТОЙНИК') ||
        objectType == 'oil_settler';
  }

  String get _pressureEquipmentTypeCode {
    if (_isGasSeparator) return 'GAS_SEPARATOR';
    if (_isUndergroundTank) return 'UNDERGROUND_TANK';
    if (_isOilSettler) return 'OIL_SETTLER';
    return 'VESSEL';
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
  List<String> _organizationOptions = [];
  List<String> _verificationEquipmentLabels = [];

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      final formId = widget.reportFormId ??
          TechnicalReportFormRegistry.suggestFormId(widget.equipment);
      _reportForm = TechnicalReportFormRegistry.getById(formId);

      _checklist = _isCompressor ? CompressorChecklist() : VesselChecklist();
      _checklist.inspectionType = widget.inspectionType;
      _checklist.reportFormId = _reportForm.id;
      _checklist.reportFormTitle = _reportForm.displayTitle;

      final docs = _reportForm.documents.isNotEmpty
          ? _reportForm.documents
          : ChecklistConstants.documents;
      for (var doc in docs) {
        _checklist.documents[doc['number']!] = false;
      }

      _prefillFromEquipment();
      _applyTemplateDefaults();

      Future.microtask(_loadEngineers);
      Future.microtask(_loadOpos);
      Future.microtask(_loadOrganizationOptions);
      Future.microtask(_getGpsCoordinates);
      Future.microtask(_startAutoSaveTimer);
      
      Future.microtask(() async {
        final hadLocal = await _loadLocalPendingIfExists();
        if (!hadLocal) {
          await _prefillFromPreviousInspections();
        }
        await _applyAssignmentMeta();
        await _prefillFromOpo();
      });
    } catch (e) {
      _reportForm = TechnicalReportFormRegistry.getById('to-1');
      _checklist = VesselChecklist();
      _checklist.inspectionType = widget.inspectionType;
      _checklist.reportFormId = _reportForm.id;
      _checklist.reportFormTitle = _reportForm.displayTitle;
      for (var doc in ChecklistConstants.documents) {
        _checklist.documents[doc['number']!] = false;
      }
      print('Ошибка инициализации чек-листа: $e');
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_hasUnsavedChanges && !_isSubmitting) {
      try {
        _syncFormFieldsToChecklist();
      } catch (_) {}
      // fire-and-forget: данные уже в _checklist
      _autoSaveDraft();
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // paused — экран выкл / уход в фон; hidden — Flutter 3.13+
    // inactive не используем: срабатывает на клавиатуру/диалоги
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!_isSubmitting) {
        try {
          _syncFormFieldsToChecklist();
        } catch (_) {}
        _autoSaveDraft(force: true);
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
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _hasUnsavedChanges && !_isSubmitting) {
        _autoSaveDraft();
      }
    });
  }

  // ====================================================================
  //  Автосохранение
  // ====================================================================

  /// Обновляет поле FormBuilder без сброса остальных значений.
  void _patchFormField(String name, dynamic value) {
    final field = _formKey.currentState?.fields[name];
    if (field != null) {
      field.didChange(value);
    }
  }

  /// Подтягивает в FormBuilder актуальные значения из модели (после пикеров / возврата на стр.1).
  void _patchFormFromChecklist() {
    final form = _formKey.currentState;
    if (form == null) return;

    void patch(String name, dynamic value) {
      if (!form.fields.containsKey(name)) return;
      final current = form.fields[name]!.value;
      if (current == value) return;
      // Не затираем уже введённый текст пустым значением из модели
      if (value == null || (value is String && value.trim().isEmpty)) {
        if (current != null && current.toString().trim().isNotEmpty) return;
      }
      form.fields[name]!.didChange(value);
    }

    patch('executors', _checklist.executors);
    patch('organization', _checklist.organization);
    final org = (_checklist.organization ?? '').trim();
    if (org.isNotEmpty) {
      if (_organizationOptions.contains(org)) {
        patch('organization_select', org);
      } else {
        patch('organization_custom', org);
      }
    }
    patch('vessel_name', _checklist.vesselName);
    patch('serial_number', _checklist.serialNumber);
    patch('reg_number', _checklist.regNumber);
    patch('manufacturer', _checklist.manufacturer);
    patch('manufacture_year', _checklist.manufactureYear);
    if (_selectedOpoId != null && _selectedOpoId!.isNotEmpty) {
      patch('opo_id', _selectedOpoId);
    }
    if (_checklist.inspectionDate != null &&
        _checklist.inspectionDate!.trim().isNotEmpty) {
      try {
        patch('inspection_date', DateTime.parse(_checklist.inspectionDate!));
      } catch (_) {}
    }
  }

  /// Переносит значения видимых/живых полей FormBuilder в модель чек-листа.
  void _syncFormFieldsToChecklist() {
    final form = _formKey.currentState;
    if (form == null) return;
    form.save();
    final values = Map<String, dynamic>.from(form.value);

    String? asStr(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      return s;
    }

    bool? asYesNo(dynamic v) {
      if (v == null) return null;
      final s = v.toString().toLowerCase();
      if (s == 'yes' || s == 'true' || s == 'да') return true;
      if (s == 'no' || s == 'false' || s == 'нет') return false;
      return null;
    }

    /// Не затираем уже заполненное в модели пустым значением из формы
    /// (типичный кейс: пикер исполнителей пишет в checklist, а FormBuilder ещё пуст).
    void setStrPreferNonEmpty(String? formVal, void Function(String?) assign, String? current) {
      if (formVal == null) return;
      if (formVal.trim().isEmpty) {
        if (current == null || current.trim().isEmpty) {
          assign(formVal);
        }
        return;
      }
      assign(formVal);
    }

    if (values.containsKey('executors')) {
      setStrPreferNonEmpty(
        asStr(values['executors']),
        (v) => _checklist.executors = v,
        _checklist.executors,
      );
    }
    if (values.containsKey('organization')) {
      setStrPreferNonEmpty(
        asStr(values['organization']),
        (v) => _checklist.organization = v,
        _checklist.organization,
      );
    }
    if (values.containsKey('organization_custom')) {
      setStrPreferNonEmpty(
        asStr(values['organization_custom']),
        (v) => _checklist.organization = v,
        _checklist.organization,
      );
    }
    if (values.containsKey('organization_select')) {
      setStrPreferNonEmpty(
        asStr(values['organization_select']),
        (v) => _checklist.organization = v,
        _checklist.organization,
      );
    }
    if (values.containsKey('vessel_name')) {
      _checklist.vesselName = asStr(values['vessel_name']);
    }
    if (values.containsKey('serial_number')) {
      _checklist.serialNumber = asStr(values['serial_number']);
    }
    if (values.containsKey('reg_number')) {
      _checklist.regNumber = asStr(values['reg_number']);
    }
    if (values.containsKey('manufacturer')) {
      _checklist.manufacturer = asStr(values['manufacturer']);
    }
    if (values.containsKey('manufacture_year')) {
      _checklist.manufactureYear = asStr(values['manufacture_year']);
    }
    if (values.containsKey('conclusion')) {
      _checklist.conclusion = asStr(values['conclusion']);
    }

    final dateVal = values['inspection_date'];
    if (dateVal is DateTime) {
      _checklist.inspectionDate = dateVal.toIso8601String();
    } else if (dateVal != null) {
      final parsed = DateTime.tryParse(dateVal.toString());
      if (parsed != null) {
        _checklist.inspectionDate = parsed.toIso8601String();
      }
    }

    if (!_isCompressor) {
      if (values.containsKey('diameter')) {
        _checklist.diameter = asStr(values['diameter']);
      }
      if (values.containsKey('working_pressure')) {
        _checklist.workingPressure = asStr(values['working_pressure']);
      }
      if (values.containsKey('wall_thickness')) {
        _checklist.wallThickness = asStr(values['wall_thickness']);
      }
      if (values.containsKey('purpose')) {
        _checklist.purpose = asStr(values['purpose']);
      }
      if (values.containsKey('commissioning_year')) {
        _checklist.commissioningYear = asStr(values['commissioning_year']);
      }
      if (values.containsKey('design_pressure')) {
        _checklist.designPressure = asStr(values['design_pressure']);
      }
      if (values.containsKey('test_pressure')) {
        _checklist.testPressure = asStr(values['test_pressure']);
      }
      if (values.containsKey('working_temperature')) {
        _checklist.workingTemperature = asStr(values['working_temperature']);
      }
      if (values.containsKey('design_temperature')) {
        _checklist.designTemperature = asStr(values['design_temperature']);
      }
      if (values.containsKey('working_medium')) {
        _checklist.workingMedium = asStr(values['working_medium']);
      }
      if (values.containsKey('medium_characteristics')) {
        _checklist.mediumCharacteristics = asStr(values['medium_characteristics']);
      }
      if (values.containsKey('vessel_group')) {
        _checklist.vesselGroup = asStr(values['vessel_group']);
      }
      if (values.containsKey('medium_group')) {
        _checklist.mediumGroup = asStr(values['medium_group']);
      }
      if (values.containsKey('corrosion_allowance')) {
        _checklist.corrosionAllowance = asStr(values['corrosion_allowance']);
      }
      if (values.containsKey('previous_inspection_result')) {
        _checklist.previousInspectionResult =
            asStr(values['previous_inspection_result']);
      }
      if (values.containsKey('designation')) {
        _checklist.designation = asStr(values['designation']);
      }
      if (values.containsKey('hazard_class')) {
        _checklist.hazardClass = asStr(values['hazard_class']);
      }
      if (values.containsKey('explosion_hazard')) {
        _checklist.explosionHazard = asStr(values['explosion_hazard']);
      }
      if (values.containsKey('fire_hazard')) {
        _checklist.fireHazard = asStr(values['fire_hazard']);
      }
      if (values.containsKey('connection_scheme')) {
        _checklist.connectionScheme = asStr(values['connection_scheme']);
      }
      if (values.containsKey('climatic_version')) {
        _checklist.climaticVersion = asStr(values['climatic_version']);
      }
      if (values.containsKey('empty_mass')) {
        _checklist.emptyMass = asStr(values['empty_mass']);
      }
      if (values.containsKey('load_cycles')) {
        _checklist.loadCycles = asStr(values['load_cycles']);
      }
      if (values.containsKey('service_life')) {
        _checklist.serviceLife = asStr(values['service_life']);
      }
      if (values.containsKey('tech_card_number')) {
        _checklist.techCardNumber = asStr(values['tech_card_number']);
      }
      if (values.containsKey('calculation_result')) {
        _checklist.calculationResult = asStr(values['calculation_result']);
      }
      if (values.containsKey('technical_state')) {
        _checklist.technicalState = asStr(values['technical_state']);
      }
      if (values.containsKey('documentation_conclusion')) {
        _checklist.documentationConclusion =
            asStr(values['documentation_conclusion']);
      }
      if (values.containsKey('operational_conclusion')) {
        _checklist.operationalConclusion =
            asStr(values['operational_conclusion']);
      }
      if (values.containsKey('matches_drawing')) {
        _checklist.matchesDrawing = asYesNo(values['matches_drawing']);
      }
      if (values.containsKey('has_thermal_insulation')) {
        _checklist.hasThermalInsulation =
            asYesNo(values['has_thermal_insulation']);
      }
      if (values.containsKey('anticorrosion_coating')) {
        _checklist.anticorrosionCoatingState =
            asStr(values['anticorrosion_coating']);
      }
      if (values.containsKey('support_state')) {
        _checklist.supportState = asStr(values['support_state']);
      }
      if (values.containsKey('fasteners_state')) {
        _checklist.fastenersState = asStr(values['fasteners_state']);
      }
      if (values.containsKey('has_flange_misalignment')) {
        _checklist.hasFlangeMisalignment =
            asYesNo(values['has_flange_misalignment']);
      }
      if (values.containsKey('has_nozzle_misalignment')) {
        _checklist.hasNozzleMisalignment =
            asYesNo(values['has_nozzle_misalignment']);
      }
      if (values.containsKey('has_vessel_repairs')) {
        _checklist.hasVesselRepairs = asYesNo(values['has_vessel_repairs']);
      }
      if (values.containsKey('has_tpa_repairs')) {
        _checklist.hasTpaRepairs = asYesNo(values['has_tpa_repairs']);
      }
      if (values.containsKey('internal_devices_state')) {
        _checklist.internalDevicesState = asStr(values['internal_devices_state']);
      }
      if (values.containsKey('has_local_deformations')) {
        _checklist.hasLocalDeformations =
            asYesNo(values['has_local_deformations']);
      }
      if (values.containsKey('has_external_defects')) {
        _checklist.hasExternalDefects = asYesNo(values['has_external_defects']);
      }
      if (values.containsKey('has_internal_defects')) {
        _checklist.hasInternalDefects = asYesNo(values['has_internal_defects']);
      }
      if (values.containsKey('has_armature_defects')) {
        _checklist.hasArmatureDefects = asYesNo(values['has_armature_defects']);
      }
    } else if (_checklist is CompressorChecklist) {
      final c = _checklist as CompressorChecklist;
      if (values.containsKey('compressor_type')) {
        c.compressorType = asStr(values['compressor_type']);
      }
      if (values.containsKey('power_rating')) {
        c.powerRating = asStr(values['power_rating']) ?? c.powerRating;
      }
      if (values.containsKey('pressure_ratio')) {
        c.pressureRatio = asStr(values['pressure_ratio']) ?? c.pressureRatio;
      }
      if (values.containsKey('flow_rate')) {
        c.flowRate = asStr(values['flow_rate']) ?? c.flowRate;
      }
      if (values.containsKey('rotation_speed')) {
        c.rotationSpeed = asStr(values['rotation_speed']) ?? c.rotationSpeed;
      }
      if (values.containsKey('number_of_stages')) {
        c.numberOfStages = asStr(values['number_of_stages']) ?? c.numberOfStages;
      }
    }

    _checklist.additionalData ??= <String, dynamic>{};
    _checklist.additionalData!['current_page'] = _currentPage;
  }

  Future<void> _autoSaveDraft({bool force = false}) async {
    if (_isAutoSaving) return;
    if (!force && !_hasUnsavedChanges) return;
    _isAutoSaving = true;

    try {
      _syncFormFieldsToChecklist();

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
      _checklist.additionalData ??= <String, dynamic>{};
      _checklist.additionalData!['current_page'] = _currentPage;

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

      if (mounted) {
        setState(() {
          _hasUnsavedChanges = false;
          _lastAutoSaveTime = DateTime.now();
        });
      } else {
        _hasUnsavedChanges = false;
        _lastAutoSaveTime = DateTime.now();
      }
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
      try {
        final last = await _lastValuesService.load();
        if ((_checklist.organization == null ||
                _checklist.organization!.trim().isEmpty) &&
            (last['organization']?.isNotEmpty ?? false)) {
          _checklist.organization = last['organization'];
        }
        if ((_checklist.executors == null ||
                _checklist.executors!.trim().isEmpty) &&
            (last['executors']?.isNotEmpty ?? false)) {
          _checklist.executors = last['executors'];
        }
      } catch (_) {}
      setState(() {
        // Сохраняем уже выбранных инженеров по id — иначе при подгрузке списка
        // с сервера выбор на 1-й странице «слетает».
        final prevSelectedIds = <String, String>{};
        for (final e in _selectedEngineerByMethod.entries) {
          final id = e.value['id']?.toString();
          if (id != null && id.isNotEmpty) {
            prevSelectedIds[e.key] = id;
          }
        }
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
        for (final entry in prevSelectedIds.entries) {
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
        _updateInspectionEngineers();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingEngineers = false);
    }
  }

  Future<void> _loadOrganizationOptions() async {
    try {
      final enterprises = await _apiService.getHierarchyEnterprises();
      final options = <String>[];
      for (final ent in enterprises) {
        final entId = ent['id']?.toString() ?? '';
        final entName = ent['name']?.toString().trim() ?? '';
        if (entId.isEmpty) continue;
        final branches = await _apiService.getHierarchyBranches(entId);
        if (branches.isEmpty && entName.isNotEmpty) {
          options.add(entName);
          continue;
        }
        for (final br in branches) {
          final brName = br['name']?.toString().trim() ?? '';
          final workshops = await _apiService.getHierarchyWorkshops(
            br['id']?.toString() ?? '',
          );
          if (workshops.isEmpty) {
            options.add('$entName / $brName');
          } else {
            for (final ws in workshops) {
              final wsName = ws['name']?.toString().trim() ?? '';
              options.add('$entName / $brName / $wsName');
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _organizationOptions = options.toSet().toList()..sort();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _patchFormFromChecklist();
        } catch (_) {}
      });
    } catch (e) {
      print('Ошибка загрузки организаций: $e');
    }
  }

  Future<void> _refreshVerificationLabels() async {
    if (_selectedEquipmentIds.isEmpty) {
      if (mounted) setState(() => _verificationEquipmentLabels = []);
      return;
    }
    try {
      var list = await _syncService.getOfflineVerificationEquipment();
      if (list.isEmpty) {
        list = await _apiService.getVerificationEquipment(isActive: true);
      }
      final labels = <String>[];
      for (final id in _selectedEquipmentIds) {
        Map<String, dynamic>? match;
        for (final e in list) {
          if (e['id']?.toString() == id) {
            match = e;
            break;
          }
        }
        if (match != null) {
          final name =
              (match['name'] ?? match['equipment_name'] ?? id).toString();
          labels.add(name);
        } else {
          labels.add('Прибор $id');
        }
      }
      if (mounted) setState(() => _verificationEquipmentLabels = labels);
    } catch (_) {
      if (mounted) {
        setState(() => _verificationEquipmentLabels =
            _selectedEquipmentIds.map((id) => 'Прибор $id').toList());
      }
    }
  }

  Future<bool> _loadLocalPendingIfExists() async {
    try {
      Map<String, dynamic>? pending = await _syncService.getLatestPendingInspection(
        equipmentId: widget.equipment.id,
        assignmentId: widget.assignmentId,
      );

      Map<String, dynamic>? data =
          (pending?['data'] as Map?)?.cast<String, dynamic>();

      // Fallback: черновик из AutoSaveService (на случай, если pending ещё нет)
      if (data == null) {
        final draft = await _autoSaveService.getDraftForEquipment(
          widget.equipment.id,
        );
        if (draft != null) {
          final draftAssignment = draft['assignment_id']?.toString();
          if (widget.assignmentId == null ||
              draftAssignment == null ||
              draftAssignment == widget.assignmentId) {
            final cd = draft['checklist_data'];
            if (cd is Map) {
              data = Map<String, dynamic>.from(cd);
              pending = {
                'data': data,
                'verification_equipment_ids':
                    data['additional_data'] is Map
                        ? (data['additional_data']
                            as Map)['verification_equipment_ids']
                        : null,
                'document_files': data['document_files'],
              };
            }
          }
        }
      }

      if (data == null) return false;

      final equipmentType = data['equipment_type']?.toString();
      final isCompressor = equipmentType != null &&
          equipmentType.toUpperCase().contains('COMPRESSOR');

      final loadedChecklist = isCompressor
          ? CompressorChecklist.fromJson(data)
          : VesselChecklist.fromJson(data);

      final ve = pending?['verification_equipment_ids'];
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

      final savedPage = data['additional_data'] is Map
          ? (data['additional_data'] as Map)['current_page']
          : null;
      if (savedPage is int) {
        _restorePageIndex = savedPage;
      } else if (savedPage != null) {
        _restorePageIndex = int.tryParse(savedPage.toString());
      }

      final docs = pending?['document_files'];
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

      for (final docNum in VesselChecklist.multiDocumentNumbers) {
        if (_documentFiles.containsKey(docNum) &&
            !_documentFiles.containsKey(VesselChecklist.documentFileKey(docNum, 0))) {
          _documentFiles[VesselChecklist.documentFileKey(docNum, 0)] =
              _documentFiles[docNum]!;
        }
      }

      setState(() {
        // Полная подмена модели — иначе паспорт/таблицы/расчёт теряются
        final j = loadedChecklist.toJson();
        _checklist = isCompressor
            ? CompressorChecklist.fromJson(j)
            : VesselChecklist.fromJson(j);
        _checklist.inspectionType =
            _checklist.inspectionType ?? widget.inspectionType;
        _checklist.reportFormId = _checklist.reportFormId ?? _reportForm.id;
        _checklist.reportFormTitle =
            _checklist.reportFormTitle ?? _reportForm.displayTitle;

        _selectedEngineerByMethod.clear();
        for (final ie in _checklist.inspectionEngineers) {
          final method = ie.method;
          final match = _engineers.firstWhere(
            (e) => e['id']?.toString() == ie.engineerId,
            orElse: () => {},
          );
          if (match.isNotEmpty) {
            _selectedEngineerByMethod[method] = match;
          }
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

      final pageToRestore = _restorePageIndex;
      if (pageToRestore != null &&
          pageToRestore >= 0 &&
          pageToRestore < _pageLabels.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_pageController.hasClients) {
            _pageController.jumpToPage(pageToRestore);
          }
          setState(() => _currentPage = pageToRestore);
        });
      }

      await _refreshVerificationLabels();
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
      mergeStr(tpl.constructionType, (v) => _checklist.constructionType = v, _checklist.constructionType);
      mergeStr(tpl.schemeIndex, (v) => _checklist.schemeIndex = v, _checklist.schemeIndex);
      mergeStr(tpl.volume, (v) => _checklist.volume = v, _checklist.volume);
      mergeStr(tpl.residualLifeText, (v) => _checklist.residualLifeText = v, _checklist.residualLifeText);

      void mergeNum(dynamic from, void Function(String v) set, String? current) {
        if (from != null && (current == null || current.trim().isEmpty)) {
          set(from.toString());
        }
      }

      mergeNum(raw['working_pressure'], (v) => _checklist.workingPressure = v, _checklist.workingPressure);
      mergeNum(raw['design_pressure'], (v) => _checklist.designPressure = v, _checklist.designPressure);
      mergeNum(raw['test_pressure'], (v) => _checklist.testPressure = v, _checklist.testPressure);
      mergeNum(raw['wall_thickness'], (v) => _checklist.wallThickness = v, _checklist.wallThickness);
      mergeNum(raw['diameter'], (v) => _checklist.diameter = v, _checklist.diameter);
      mergeNum(raw['corrosion_allowance'], (v) => _checklist.corrosionAllowance = v, _checklist.corrosionAllowance);
      mergeNum(raw['commissioning_year'], (v) => _checklist.commissioningYear = v, _checklist.commissioningYear);

      if (tpl.inspectionType != null && tpl.inspectionType!.isNotEmpty) {
        _checklist.inspectionType = tpl.inspectionType;
      }
      if (tpl.equipmentTypeCode != null && tpl.equipmentTypeCode!.isNotEmpty) {
        _checklist.equipmentTypeCode = tpl.equipmentTypeCode;
      }
      _checklist.includeOpoData = tpl.includeOpoData;

      void mergeList<T>(List<T> from, List<T> target) {
        if (from.isNotEmpty && target.isEmpty) {
          target.addAll(from);
        }
      }

      mergeList(tpl.vesselElements, _checklist.vesselElements);
      mergeList(tpl.heatTreatmentRecords, _checklist.heatTreatmentRecords);
      mergeList(tpl.hydraulicTestHistory, _checklist.hydraulicTestHistory);
      mergeList(tpl.ndtControlHistory, _checklist.ndtControlHistory);
      mergeList(tpl.repairHistory, _checklist.repairHistory);
      mergeList(tpl.fittingsAndInstruments, _checklist.fittingsAndInstruments);
      mergeList(tpl.hardnessTests, _checklist.hardnessTests);
      mergeList(tpl.weldInspections, _checklist.weldInspections);
      mergeList(tpl.thicknessMeasurements, _checklist.thicknessMeasurements);

      if (_checklist.calculationData == null && tpl.calculationData != null) {
        _checklist.calculationData = Map<String, dynamic>.from(tpl.calculationData!);
      }
    } catch (e) {
      debugPrint('Шаблон обследования: $e');
    }
  }

  /// Подтянуть договор/сроки/техкарту из задания (веб → мобильное → отчёт).
  Future<void> _applyAssignmentMeta() async {
    if (widget.assignmentId == null || widget.assignmentId!.isEmpty) return;
    try {
      Assignment? assignment;
      try {
        for (final a in await _syncService.getOfflineAssignments()) {
          if (a.id == widget.assignmentId) {
            assignment = a;
            break;
          }
        }
      } catch (_) {}
      if (assignment == null) {
        for (final a in await _apiService.getAssignments()) {
          if (a.id == widget.assignmentId) {
            assignment = a;
            break;
          }
        }
      }
      if (assignment == null || !mounted) return;
      final a = assignment;
      setState(() {
        void put(String? cur, String? next, void Function(String) set) {
          if ((cur == null || cur.isEmpty) && next != null && next.isNotEmpty) {
            set(next);
          }
        }

        put(_checklist.contractNumber, a.contractNumber,
            (v) => _checklist.contractNumber = v);
        put(_checklist.contractDate, a.contractDate,
            (v) => _checklist.contractDate = v);
        put(_checklist.workPeriodFrom, a.workPeriodFrom,
            (v) => _checklist.workPeriodFrom = v);
        put(_checklist.workPeriodTo, a.workPeriodTo,
            (v) => _checklist.workPeriodTo = v);
        put(_checklist.workBasis, a.workBasis, (v) => _checklist.workBasis = v);
        put(_checklist.techCardNumber, a.techCardNumber,
            (v) => _checklist.techCardNumber = v);
      });
    } catch (_) {}
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
    _checklist.equipmentTypeCode = _pressureEquipmentTypeCode;
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
      _checklist.purpose = getAttr('purpose') ??
          (_isGasSeparator
              ? 'сепарация нефти и попутного нефтяного газа'
              : _isUndergroundTank
                  ? 'слив нефти, нефтегазоводяной смеси из технологических трубопроводов и аппаратов'
                  : _isOilSettler
                      ? 'трехфазное разделение предварительно подготовленной нефти (нефтегазоводяной смеси)'
                      : null);
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
      
      if (mounted) {
        // Не пересоздаём FormBuilder, если пользователь уже начал ввод —
        // иначе данные на 1-й странице слетают.
        setState(() {
          if (!_hasUnsavedChanges) {
            _formSeed++;
          }
        });
      }
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

        final shouldAnnotate = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1e293b),
            title: const Text('Разметка фото', style: TextStyle(color: Colors.white)),
            content: const Text(
              'Добавить стрелки/окружности поверх фото прямо сейчас?',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'skip'),
                child: const Text('Пропустить', style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'draw'),
                child: const Text('Разметить', style: TextStyle(color: Color(0xFF3b82f6))),
              ),
            ],
          ),
        );

        if (shouldAnnotate == 'draw' && mounted) {
          final annotated = await Navigator.of(context).push<File>(
            MaterialPageRoute(
              builder: (_) => ImageAnnotationScreen(
                initialImage: File(finalImagePath),
                title: isFactoryPlate ? 'Табличка' : 'Схема контроля',
              ),
            ),
          );
          if (annotated != null) {
            finalImagePath = annotated.path;
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
    _syncFormFieldsToChecklist();
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
      _checklist.additionalData ??= <String, dynamic>{};
      _checklist.additionalData!['current_page'] = _currentPage;

      await _autoSaveService.saveDraft(
        equipmentId: widget.equipment.id,
        checklistData: _checklist.toJson(),
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

      if (mounted) {
        setState(() {
          _hasUnsavedChanges = false;
          _lastAutoSaveTime = DateTime.now();
        });
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
    _syncFormFieldsToChecklist();
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

    _syncManualEquipmentToChecklist();
    _syncObjectPhotosToChecklist();

    final validation = validateInspectionForSign(
      checklist: _checklist,
      selectedEquipmentIds: _selectedEquipmentIds,
      manualVerificationEquipment: _manualVerificationEquipment,
      factoryPlatePhoto: _factoryPlatePhoto,
      controlSchemeImage: _controlSchemeImage,
    );
    if (!validation.isComplete) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Данные обследования неполные'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Перед подписанием заполните:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...validation.missingRequired.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $f'),
                    )),
                if (validation.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Предупреждения:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...validation.warnings.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $f', style: const TextStyle(fontSize: 13)),
                      )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
          ],
        ),
      );
      return;
    }

    final inspectionDateStr = _resolveInspectionDateIso();
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

      await _lastValuesService.save(
        organization: _checklist.organization,
        executors: _checklist.executors,
      );

      // Обследование подписано и поставлено в очередь синхронизации —
      // удаляем автосохранённый черновик, чтобы в «Реестре протоколов»
      // оно не отображалось как «не завершён»
      final draftKey =
          widget.existingInspectionId ?? 'draft_${widget.equipment.id}';
      await _autoSaveService.deleteDraft(draftKey);

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

    initialValues['conclusion'] = _checklist.conclusion;
    initialValues['calculation_result'] = _checklist.calculationResult;
    initialValues['technical_state'] = _checklist.technicalState;
    initialValues['documentation_conclusion'] = _checklist.documentationConclusion;
    initialValues['operational_conclusion'] = _checklist.operationalConclusion;
    initialValues['designation'] = _checklist.designation;
    initialValues['hazard_class'] = _checklist.hazardClass;
    initialValues['explosion_hazard'] = _checklist.explosionHazard;
    initialValues['fire_hazard'] = _checklist.fireHazard;
    initialValues['connection_scheme'] = _checklist.connectionScheme;
    initialValues['climatic_version'] = _checklist.climaticVersion;
    initialValues['empty_mass'] = _checklist.emptyMass;
    initialValues['load_cycles'] = _checklist.loadCycles;
    initialValues['service_life'] = _checklist.serviceLife;
    initialValues['tech_card_number'] = _checklist.techCardNumber;

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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.equipment.name,
                style: const TextStyle(fontSize: 16),
              ),
              Text(
                _reportForm.displayTitle,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
            ],
          ),
          backgroundColor: kInspectionScaffoldBg,
          foregroundColor: Colors.white,
          actions: [
            if (_isSubmitting)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              )
            else ...[
              // Навигация по разделам — по нажатию, не автоматически
              IconButton(
                icon: const Icon(Icons.list_alt_outlined, size: 22),
                tooltip: 'Разделы отчёта',
                onPressed: _showSectionNavigator,
              ),
              IconButton(icon: const Icon(Icons.save_outlined), onPressed: _saveDraft, tooltip: 'Сохранить черновик'),
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
            child: _buildPageView(conclusionSection),
          ),
        ),
      ),
    );
  }

  Widget _buildPageView(InspectionConclusionSection conclusionSection) {
    // Страница 0: Основная информация
    final page0 = _buildSinglePage(
      pageIndex: 0,
      progressWidget: buildInspectionProgressIndicator(
        checklist: _checklist,
        selectedEquipmentIds: _selectedEquipmentIds,
        factoryPlatePhoto: _factoryPlatePhoto,
      ),
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
        organizationOptions: _organizationOptions,
        selectedVerificationLabels: _verificationEquipmentLabels,
        onStateChanged: () {
          setState(() => _hasUnsavedChanges = true);
          // Пикеры (исполнители и т.п.) пишут в checklist, но не в FormBuilder —
          // сразу синхронизируем поле формы, иначе при уходе со стр.1 sync затрёт данные.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            try {
              _patchFormFromChecklist();
            } catch (_) {}
          });
        },
        onEquipmentIdsChanged: (ids) {
          setState(() {
            _selectedEquipmentIds = ids;
            _hasUnsavedChanges = true;
          });
          _refreshVerificationLabels();
        },
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

    // Страница 2: Паспорт (приложение Б) — для ЭПБ
    final page2 = _buildSinglePage(
      pageIndex: 2,
      child: InspectionPassportSection(
        checklist: _checklist,
        onStateChanged: () => setState(() => _hasUnsavedChanges = true),
      ),
    );

    // Страница 3: Карта обследования (фото таблички, доп.фото, схема)
    final page3 = _buildSinglePage(
      pageIndex: 3,
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

    // Страница 4: Проверки + Дефекты (р.11)
    final page4 = _buildSinglePage(
      pageIndex: 4,
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

    // Страница 5: ЗРА + СППК
    final page5 = _buildSinglePage(
      pageIndex: 5,
      child: InspectionSafetyDevicesSection(
        checklist: _checklist,
        onStateChanged: () => setState(() => _hasUnsavedChanges = true),
      ),
    );

    // Страница 6: Измерения 7-10 (овальность, твёрдость, ПВК/УЗК, УЗТ)
    final page6 = _buildSinglePage(
      pageIndex: 6,
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

    // Страница 7: Заключение + кнопки
    final page7 = _buildSinglePage(
      pageIndex: 7,
      child: conclusionSection,
    );

    return Column(
      children: [
        // Липкая панель навигации по разделам
        Material(
          color: const Color(0xFF1e293b),
          child: SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              itemCount: _pageLabels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (ctx, idx) {
                final selected = idx == _currentPage;
                return ChoiceChip(
                  selected: selected,
                  label: Text(
                    '${idx + 1}. ${_pageLabels[idx]}',
                    style: TextStyle(
                      fontSize: 11,
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  selectedColor: const Color(0xFF3b82f6),
                  backgroundColor: Colors.white10,
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFF3b82f6)
                        : Colors.white24,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    _pageController.animateToPage(
                      idx,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeInOut,
                    );
                  },
                );
              },
            ),
          ),
        ),
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (idx) {
              try {
                _syncFormFieldsToChecklist();
              } catch (_) {}
              if (!_isSubmitting) {
                _autoSaveDraft(force: true);
              }
              setState(() {
                _currentPage = idx;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                try {
                  _patchFormFromChecklist();
                } catch (_) {}
              });
            },
            children: [
              _KeepAlivePage(key: const PageStorageKey('insp_p0'), child: page0),
              _KeepAlivePage(key: const PageStorageKey('insp_p1'), child: page1),
              _KeepAlivePage(key: const PageStorageKey('insp_p2'), child: page2),
              _KeepAlivePage(key: const PageStorageKey('insp_p3'), child: page3),
              _KeepAlivePage(key: const PageStorageKey('insp_p4'), child: page4),
              _KeepAlivePage(key: const PageStorageKey('insp_p5'), child: page5),
              _KeepAlivePage(key: const PageStorageKey('insp_p6'), child: page6),
              _KeepAlivePage(key: const PageStorageKey('insp_p7'), child: page7),
            ],
          ),
        ),
      ],
    );
  }

  /// Оборачивает один виджет или список виджетов в ScrollView с заголовком страницы
  Widget _buildSinglePage({
    required int pageIndex,
    Widget? child,
    List<Widget>? children,
    Widget? progressWidget,
  }) {
    final bottomPad = 88.0 +
        MediaQuery.viewPaddingOf(context).bottom +
        MediaQuery.viewInsetsOf(context).bottom;
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
              _reportForm.navigationLabel(pageIndex),
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

  /// Bottom sheet навигации по разделам — вызывается только по кнопке.
  void _showSectionNavigator() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1B2438),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.viewPaddingOf(sheetCtx).bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Ручка
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.list_alt_outlined, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _reportForm.displayTitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(_pageLabels.length, (idx) {
                final isCurrent = idx == _currentPage;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _pageController.animateToPage(
                        idx,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? kInspectionAccentBlue.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCurrent
                              ? kInspectionAccentBlue.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? kInspectionAccentBlue
                                  : Colors.white12,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${idx + 1}',
                              style: TextStyle(
                                color: isCurrent ? Colors.white : Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _pageLabels[idx],
                              style: TextStyle(
                                color: isCurrent ? Colors.white : Colors.white70,
                                fontSize: 13,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isCurrent)
                            const Icon(
                              Icons.chevron_right,
                              color: Colors.white38,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

/// Сохраняет состояние страницы PageView при уходе с неё (поля формы не dispose).
class _KeepAlivePage extends StatefulWidget {
  final Widget child;

  const _KeepAlivePage({super.key, required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
