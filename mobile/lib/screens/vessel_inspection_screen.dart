import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as Path;
import 'package:path_provider/path_provider.dart';
import '../models/equipment.dart';
import '../models/vessel_checklist.dart';
import '../models/compressor_checklist.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../data/checklist_constants.dart';
import 'thickness_measurement_screen.dart';
import 'verification_equipment_selection_screen.dart';

class VesselInspectionScreen extends StatefulWidget {
  final Equipment equipment;
  final String? assignmentId; // ID задания (версия 3.3.0)

  const VesselInspectionScreen({
    super.key,
    required this.equipment,
    this.assignmentId,
  });

  @override
  State<VesselInspectionScreen> createState() => _VesselInspectionScreenState();
}

class _VesselInspectionScreenState extends State<VesselInspectionScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  final SyncService _syncService = SyncService();
  bool _isSubmitting = false;

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
  final Map<String, Map<String, dynamic>> _selectedEngineerByMethod = {};

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    try {
      // Создаем чек-лист в зависимости от типа оборудования
      _checklist = _isCompressor ? CompressorChecklist() : VesselChecklist();

      // Инициализация документов
      for (var doc in ChecklistConstants.documents) {
        _checklist.documents[doc['number']!] = false;
      }

      // Базовое автозаполнение из карточки оборудования
      _prefillFromEquipment();

      // Затем пытаемся подтянуть локально сохраненный черновик/подписанный чек-лист
      // (иначе при повторном открытии инженеру показывается пустая форма).
      Future.microtask(_loadLocalPendingIfExists);
      Future.microtask(_loadEngineers);
    } catch (e) {
      // Если ошибка при инициализации, создаем базовый чек-лист
      _checklist = VesselChecklist();
      for (var doc in ChecklistConstants.documents) {
        _checklist.documents[doc['number']!] = false;
      }
      print('Ошибка инициализации чек-листа: $e');
    }
  }

  Future<void> _loadEngineers() async {
    setState(() {
      _loadingEngineers = true;
    });
    try {
      var engineers = await _syncService.getOfflineEngineers();
      if (engineers.isEmpty) {
        try {
          engineers = await _apiService.getEngineers();
          await _syncService.saveEngineersOffline(engineers);
        } catch (_) {
          // игнорируем
        }
      }
      if (!mounted) return;
      setState(() {
        _engineers = engineers;
        _loadingEngineers = false;
        // Восстанавливаем выбранных инженеров из чек-листа
        _selectedEngineerByMethod.clear();
        for (final ie in _checklist.inspectionEngineers) {
          final match = engineers.firstWhere(
            (e) => e['id']?.toString() == ie.engineerId,
            orElse: () => {},
          );
          if (match.isNotEmpty) {
            _selectedEngineerByMethod[ie.method] = match;
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

  Future<void> _loadLocalPendingIfExists() async {
    try {
      final pending = await _syncService.getLatestPendingInspection(
        equipmentId: widget.equipment.id,
        assignmentId: widget.assignmentId,
      );
      if (pending == null) return;

      final data = (pending['data'] as Map?)?.cast<String, dynamic>();
      if (data == null) return;

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

        // файлы-объекты для UI (если путь сохранен)
        if ((_checklist.factoryPlatePhoto ?? '').isNotEmpty) {
          _factoryPlatePhoto = File(_checklist.factoryPlatePhoto!);
        }
        if ((_checklist.controlSchemeImage ?? '').isNotEmpty) {
          _controlSchemeImage = File(_checklist.controlSchemeImage!);
        }
      });
    } catch (e) {
      // Не роняем экран
      print('Ошибка загрузки локальных данных: $e');
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

    // Поля специфичные для сосудов
    if (!_isCompressor) {
      _checklist.diameter = getAttr('diameter');
      _checklist.workingPressure = getAttr('working_pressure');
      _checklist.wallThickness = getAttr('wall_thickness');
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

  Future<void> _pickImage(ImageSource source, bool isFactoryPlate) async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image != null) {
        setState(() {
          if (isFactoryPlate) {
            _factoryPlatePhoto = File(image.path);
            _checklist.factoryPlatePhoto = image.path;
          } else {
            _controlSchemeImage = File(image.path);
            _checklist.controlSchemeImage = image.path;
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка выбора изображения: $e')),
      );
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подписать и завершить?'),
        content: const Text(
          'После синхронизации на сервере задание будет отмечено как выполненное. '
          'Вы сможете скачать/сформировать отчет в веб-версии.',
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
      final inspectionDateStr = _resolveInspectionDateIso();

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

    return Scaffold(
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
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveDraft,
              tooltip:
                  'Сохранить черновик локально (отправка при синхронизации)',
            ),
        ],
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: FormBuilder(
        key: _formKey,
        initialValue: initialValues,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
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
              _buildTextField('working_pressure', 'Рабочее давление', (value) {
                _checklist.workingPressure = value;
              }),
              _buildTextField(
                  'wall_thickness', 'Толщина стенки (обечайка / днище)',
                  (value) {
                _checklist.wallThickness = value;
              }),
            ],
            // Поля для компрессоров
            if (_isCompressor) ...[
              Builder(
                builder: (context) {
                  final compressorChecklist = _checklist as CompressorChecklist;
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
                      _buildTextField('number_of_stages', 'Количество ступеней',
                          (value) {
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
                'has_thermal_insulation', 'Наличие тепловой изоляции', (value) {
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
            _buildYesNoField('has_tpa_repairs', 'Имеются ли места ремонта ТПА',
                (value) {
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
            _buildSectionHeader('6. СППК (Система предохранительных клапанов)'),
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
                title: 'Овальность, участок ${m.sectionNumber}',
                subtitle: [
                  if (m.maxDiameter != null) 'Dmax=${m.maxDiameter}',
                  if (m.minDiameter != null) 'Dmin=${m.minDiameter}',
                  if (m.deviationPercent != null) 'Δ%=${m.deviationPercent}',
                ].join(' • '),
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
                  if (w.conclusion != null && w.conclusion!.isNotEmpty)
                    'Заключение: ${w.conclusion}',
                ].join(' • '),
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
            _buildSubmitButton(),
            const SizedBox(height: 32),
          ],
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
  }) {
    return Card(
      color: const Color(0xFF1e293b),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
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
      ),
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

  Future<void> _showOvalityDialog() async {
    final section = TextEditingController(
        text: '${_checklist.ovalityMeasurements.length + 1}');
    final maxD = TextEditingController();
    final minD = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text('Овальность', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogTextField(section, 'Номер участка'),
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
              child: const Text('Добавить')),
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
        _checklist.ovalityMeasurements.add(
          OvalityMeasurement(
            sectionNumber: section.text.trim().isEmpty
                ? '${_checklist.ovalityMeasurements.length + 1}'
                : section.text.trim(),
            maxDiameter: maxVal,
            minDiameter: minVal,
            deviationPercent: dev,
          ),
        );
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

  Future<void> _showWeldInspectionDialog() async {
    final weld = TextEditingController();
    final loc = TextEditingController();
    final pvk = TextEditingController();
    final uzk = TextEditingController();
    String conclusion = ChecklistConstants.weldConclusions.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text('Сварное соединение',
            style: TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (context, setInner) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogTextField(weld, 'Номер шва *'),
                _dialogTextField(loc, 'Место на карте контроля'),
                _dialogTextField(pvk, 'Дефект (ПВК/МК)'),
                _dialogTextField(uzk, 'Дефект (УЗК)'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: conclusion,
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
              child: const Text('Добавить')),
        ],
      ),
    );

    if (ok == true && weld.text.trim().isNotEmpty) {
      setState(() {
        final w = WeldInspection(weldNumber: weld.text.trim());
        w.locationOnControlMap =
            loc.text.trim().isEmpty ? null : loc.text.trim();
        w.pvkDefect = pvk.text.trim().isEmpty ? null : pvk.text.trim();
        w.uzkDefect = uzk.text.trim().isEmpty ? null : uzk.text.trim();
        w.conclusion = conclusion;
        _checklist.weldInspections.add(w);
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
        format: DateFormat('yyyy-MM-dd'),
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
            _buildEngineerDropdown('ВИК', 'VIK'),
            _buildEngineerDropdown('УЗК', 'UZK'),
            _buildEngineerDropdown('УЗТ', 'UZT'),
            _buildEngineerDropdown('ПВК/МК', 'PVK'),
          ],
        ],
      ),
    );
  }

  Widget _buildEngineerDropdown(String label, String methodKey) {
    final items = _engineers;
    final selected = _selectedEngineerByMethod[methodKey];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<Map<String, dynamic>>(
        value: selected,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF0f172a),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white24),
          ),
        ),
        dropdownColor: const Color(0xFF1e293b),
        items: items.map((e) {
          final name = (e['full_name'] ?? '').toString();
          final position = (e['position'] ?? '').toString();
          return DropdownMenuItem<Map<String, dynamic>>(
            value: e,
            child: Text(
              position.isNotEmpty ? '$name — $position' : name,
              style: const TextStyle(color: Colors.white),
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            _selectedEngineerByMethod[methodKey] = value;
            _updateInspectionEngineers();
          });
        },
      ),
    );
  }

  void _updateInspectionEngineers() {
    final result = <InspectionEngineer>[];
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
    }
    _checklist.inspectionEngineers = result;
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
      final persistedPath = await _persistPickedFile(
        sourcePath: picked.path,
        fileName: Path.basename(picked.path),
        documentNumber: 'vik_defect',
      );
      return persistedPath;
    } catch (_) {
      return null;
    }
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
                leading: const Icon(Icons.photo, color: Colors.blue),
                title:
                    const Text('Фото', style: TextStyle(color: Colors.white)),
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
                leading: const Icon(Icons.image, color: Colors.green),
                title: const Text('Из галереи',
                    style: TextStyle(color: Colors.white)),
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
    final targetPath =
        Path.join(storageDir.path, '${documentNumber}_${ts}_$fileName');
    final targetFile = File(targetPath);
    await targetFile.writeAsBytes(await File(sourcePath).readAsBytes(),
        flush: true);
    return targetFile.path;
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
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDocumentFile(documentNumber),
                        icon: Icon(hasFile ? Icons.edit : Icons.attach_file),
                        label:
                            Text(hasFile ? 'Изменить файл' : 'Прикрепить файл'),
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
            Container(
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () =>
                            _pickImage(ImageSource.camera, isFactoryPlate),
                        icon: const Icon(Icons.camera),
                        label: const Text('Камера'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3b82f6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () =>
                            _pickImage(ImageSource.gallery, isFactoryPlate),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Галерея'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3b82f6),
                        ),
                      ),
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

  Widget _buildSubmitButton() {
    final isAssignment =
        widget.assignmentId != null && widget.assignmentId!.isNotEmpty;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _saveDraft,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3b82f6),
              padding: const EdgeInsets.symmetric(vertical: 16),
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
        if (isAssignment) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _signAndFinish,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22c55e),
                padding: const EdgeInsets.symmetric(vertical: 16),
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
        ],
      ],
    );
  }
}
