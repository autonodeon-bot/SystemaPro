import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../models/equipment.dart';
import '../models/vessel_checklist.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';
import '../data/checklist_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class VesselInspectionScreen extends StatefulWidget {
  final Equipment equipment;

  const VesselInspectionScreen({
    super.key,
    required this.equipment,
  });

  @override
  State<VesselInspectionScreen> createState() => _VesselInspectionScreenState();
}

class _VesselInspectionScreenState extends State<VesselInspectionScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  final SyncService _syncService = SyncService();
  final AuthService _authService = AuthService();
  bool _isSubmitting = false;
  bool _isOffline = false;
  bool _autoSync = true; // Автоматическая отправка по умолчанию

  final VesselChecklist _checklist = VesselChecklist();
  File? _factoryPlatePhoto;
  File? _controlSchemeImage;

  // Хранилище документов: ключ - номер документа, значение - путь к файлу
  final Map<String, String> _documentPaths = {};
  // Хранилище точек контроля на чертеже: ключ - pointId, значение - данные измерения
  final Map<String, Map<String, dynamic>> _controlPoints = {};

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Инициализация документов
    for (var doc in ChecklistConstants.documents) {
      _checklist.documents[doc['number']!] = false;
    }
    _loadAutoSyncSetting();
    _loadEquipmentData();
    _checkConnection();
  }

  // Загрузка настройки автоматической синхронизации
  Future<void> _loadAutoSyncSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSync = prefs.getBool('auto_sync') ?? true;
    });
  }

  // Сохранение настройки автоматической синхронизации
  Future<void> _saveAutoSyncSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_sync', value);
    setState(() {
      _autoSync = value;
    });
  }

  // Автозаполнение данных из оборудования
  void _loadEquipmentData() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_formKey.currentState != null) {
        final formData = _formKey.currentState!.value;

        // Автозаполнение наименования сосуда
        if (widget.equipment.name.isNotEmpty &&
            (formData['vessel_name'] == null ||
                formData['vessel_name'].toString().isEmpty)) {
          _formKey.currentState!.fields['vessel_name']
              ?.didChange(widget.equipment.name);
          _checklist.vesselName = widget.equipment.name;
        }

        // Автозаполнение места установки
        if (widget.equipment.location != null &&
            (formData['organization'] == null ||
                formData['organization'].toString().isEmpty)) {
          _formKey.currentState!.fields['organization']
              ?.didChange(widget.equipment.location);
          _checklist.organization = widget.equipment.location;
        }

        // Автозаполнение заводского номера
        if (widget.equipment.serialNumber != null &&
            (formData['serial_number'] == null ||
                formData['serial_number'].toString().isEmpty)) {
          _formKey.currentState!.fields['serial_number']
              ?.didChange(widget.equipment.serialNumber);
          _checklist.serialNumber = widget.equipment.serialNumber;
        }

        // Автозаполнение из attributes
        if (widget.equipment.attributes != null) {
          final attrs = widget.equipment.attributes!;

          // Диаметр
          if (attrs['diameter'] != null &&
              (formData['diameter'] == null ||
                  formData['diameter'].toString().isEmpty)) {
            _formKey.currentState!.fields['diameter']
                ?.didChange(attrs['diameter'].toString());
            _checklist.diameter = attrs['diameter'].toString();
          }

          // Толщина стенки
          if (attrs['wall_thickness'] != null &&
              (formData['wall_thickness'] == null ||
                  formData['wall_thickness'].toString().isEmpty)) {
            _formKey.currentState!.fields['wall_thickness']
                ?.didChange(attrs['wall_thickness'].toString());
            _checklist.wallThickness = attrs['wall_thickness'].toString();
          }

          // Рабочее давление
          if (attrs['operating_pressure'] != null &&
              (formData['working_pressure'] == null ||
                  formData['working_pressure'].toString().isEmpty)) {
            _formKey.currentState!.fields['working_pressure']
                ?.didChange(attrs['operating_pressure'].toString());
            _checklist.workingPressure = attrs['operating_pressure'].toString();
          }
        }
      }
    });
  }

  Future<void> _checkConnection() async {
    final isConnected = await _apiService.checkConnection();
    setState(() {
      _isOffline = !isConnected;
    });
  }

  void _showReportCreationDialog(String inspectionId) async {
    // Проверяем подключение к интернету
    final isConnected = await _apiService.checkConnection();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text(
          'Создать отчет?',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Чек-лист успешно отправлен. Хотите создать отчет или экспертизу на основе этой диагностики?',
              style: TextStyle(color: Colors.white70),
            ),
            if (!isConnected) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Нет подключения к интернету. Отчет будет сохранен локально и отправлен при появлении связи.',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, true);
            },
            child: const Text('Позже'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                if (isConnected) {
                  // Пытаемся создать отчет онлайн
                  final report = await _apiService.createReport(
                    inspectionId: inspectionId,
                    reportType: 'TECHNICAL_REPORT',
                    title: 'Технический отчет: ${widget.equipment.name}',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Отчет успешно создан и отправлен'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.pop(context, true);
                  }
                } else {
                  // Сохраняем отчет локально для последующей синхронизации
                  await _syncService.saveReportOffline(
                    inspectionId: inspectionId,
                    reportType: 'TECHNICAL_REPORT',
                    title: 'Технический отчет: ${widget.equipment.name}',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Отчет сохранен локально. Будет отправлен при появлении интернета.'),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 4),
                      ),
                    );
                    Navigator.pop(context, true);
                  }
                }
              } catch (e) {
                // Если ошибка при создании онлайн, сохраняем локально
                try {
                  await _syncService.saveReportOffline(
                    inspectionId: inspectionId,
                    reportType: 'TECHNICAL_REPORT',
                    title: 'Технический отчет: ${widget.equipment.name}',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Ошибка отправки. Отчет сохранен локально: $e'),
                        backgroundColor: Colors.orange,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                } catch (offlineError) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Ошибка создания отчета: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text(
              'Создать отчет',
              style: TextStyle(color: Color(0xFF3b82f6)),
            ),
          ),
        ],
      ),
    );
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

  Future<void> _submitForm() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() => _isSubmitting = true);

      try {
        // Парсим дату обследования
        DateTime? datePerformed;
        if (_checklist.inspectionDate != null &&
            _checklist.inspectionDate!.isNotEmpty) {
          try {
            datePerformed = DateTime.parse(_checklist.inspectionDate!);
          } catch (e) {
            // Если не удалось распарсить, используем текущую дату
            datePerformed = DateTime.now();
          }
        } else {
          // Если дата не указана, используем текущую дату
          datePerformed = DateTime.now();
        }

        // Проверяем токен перед отправкой
        final token = await _authService.getToken();
        if (token == null || token.isEmpty) {
          throw Exception(
              'Токен авторизации не найден. Пожалуйста, войдите в систему заново.');
        }

        // Проверяем подключение
        final isConnected = await _apiService.checkConnection();

        // Если автосинхронизация выключена или нет подключения - сохраняем локально
        if (!_autoSync || !isConnected) {
          await _syncService.saveInspectionOffline(
            equipmentId: widget.equipment.id,
            checklist: _checklist,
            conclusion: _checklist.conclusion,
            inspectionDate:
                _checklist.inspectionDate ?? DateTime.now().toIso8601String(),
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_autoSync
                    ? 'Чек-лист сохранен локально. Будет отправлен при появлении интернета.'
                    : 'Чек-лист сохранен локально. Отправьте через синхронизацию.'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
            Navigator.pop(context, true);
          }
          return;
        }

        // Отправляем на сервер
        try {
          final result = await _apiService.submitInspection(
            equipmentId: widget.equipment.id,
            checklist: _checklist,
            conclusion: _checklist.conclusion,
            datePerformed: datePerformed,
          );

          if (mounted) {
            // Показываем диалог с предложением создать отчет
            final inspectionId = result['id']?.toString();
            if (inspectionId != null) {
              _showReportCreationDialog(inspectionId);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Чек-лист успешно отправлен'),
                  backgroundColor: Colors.green,
                ),
              );
              Navigator.pop(context, true);
            }
          }
        } catch (e) {
          // При ошибке сохраняем локально
          await _syncService.saveInspectionOffline(
            equipmentId: widget.equipment.id,
            checklist: _checklist,
            conclusion: _checklist.conclusion,
            inspectionDate:
                _checklist.inspectionDate ?? DateTime.now().toIso8601String(),
          );

          if (mounted) {
            final errorMsg = e.toString();
            final isAuthError = errorMsg.contains('авторизации') ||
                errorMsg.contains('401') ||
                errorMsg.contains('403') ||
                errorMsg.contains('not authenticated');

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(isAuthError
                    ? 'Ошибка авторизации. Данные сохранены локально. Войдите в систему заново.'
                    : 'Ошибка отправки. Данные сохранены локально: ${errorMsg.replaceAll("Exception: ", "")}'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );

            // Если ошибка авторизации - предлагаем перелогиниться
            if (isAuthError) {
              await _authService.logout();
              if (mounted) {
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            }
          }
        }
      } catch (e) {
        // При любой ошибке сохраняем локально
        try {
          await _syncService.saveInspectionOffline(
            equipmentId: widget.equipment.id,
            checklist: _checklist,
            conclusion: _checklist.conclusion,
            inspectionDate:
                _checklist.inspectionDate ?? DateTime.now().toIso8601String(),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Ошибка. Данные сохранены локально: ${e.toString().replaceAll("Exception: ", "")}'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        } catch (offlineError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Ошибка сохранения: ${e.toString().replaceAll("Exception: ", "")}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } finally {
        if (mounted) {
          setState(() => _isSubmitting = false);
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пожалуйста, заполните все обязательные поля'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
              onPressed: _submitForm,
              tooltip: 'Сохранить и отправить',
            ),
        ],
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: FormBuilder(
        key: _formKey,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader('1. Основная информация'),
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
            const SizedBox(height: 24),
            _buildSectionHeader('2. Перечень рассмотренных документов'),
            ...ChecklistConstants.documents
                .map((doc) => _buildDocumentCheckbox(doc)),
            const SizedBox(height: 24),
            _buildSectionHeader('3. Карта обследования'),
            _buildTextField('vessel_name', 'Наименование сосуда', (value) {
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
            _buildTextField('diameter', 'Диаметр сосуда', (value) {
              _checklist.diameter = value;
            }),
            _buildTextField('working_pressure', 'Рабочее давление', (value) {
              _checklist.workingPressure = value;
            }),
            _buildTextField(
                'wall_thickness', 'Толщина стенки (обечайка / днище)', (value) {
              _checklist.wallThickness = value;
            }),
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
              // TODO: Открыть диалог добавления ЗРА
            }),
            const SizedBox(height: 24),
            _buildSectionHeader('6. СППК (Система предохранительных клапанов)'),
            _buildAddItemButton('Добавить СППК', () {
              // TODO: Открыть диалог добавления СППК
            }),
            const SizedBox(height: 24),
            _buildSectionHeader('7. Измерительный контроль'),
            _buildSubsectionHeader('Овальность'),
            _buildAddItemButton('Добавить измерение овальности', () {
              // TODO: Открыть диалог добавления измерения
            }),
            _buildSubsectionHeader('Прогиб'),
            _buildAddItemButton('Добавить измерение прогиба', () {
              // TODO: Открыть диалог добавления измерения
            }),
            const SizedBox(height: 24),
            _buildSectionHeader('8. Результаты контроля твердости'),
            _buildAddItemButton('Добавить измерение твердости', () {
              // TODO: Открыть диалог добавления измерения
            }),
            const SizedBox(height: 24),
            _buildSectionHeader('9. Результаты ПВК (МК) и УЗК'),
            _buildAddItemButton('Добавить сварное соединение', () {
              // TODO: Открыть диалог добавления соединения
            }),
            const SizedBox(height: 24),
            _buildSectionHeader('10. УЗТ (Ультразвуковая толщинометрия)'),
            _buildInteractiveControlScheme(),
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

  Widget _buildDocumentCheckbox(Map<String, String> doc) {
    final hasDocument = _checklist.documents[doc['number']] ?? false;
    final hasFile = _documentPaths.containsKey(doc['number']);

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
              value: hasDocument,
              onChanged: (value) {
                setState(() {
                  _checklist.documents[doc['number']!] = value ?? false;
                });
              },
              activeColor: const Color(0xFF3b82f6),
            ),
            // Кнопка загрузки документа (активна только если документ есть)
            if (hasDocument)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _pickDocument(doc['number']!, doc['name']!),
                        icon: Icon(
                            hasFile ? Icons.check_circle : Icons.upload_file),
                        label: Text(hasFile
                            ? 'Документ загружен'
                            : 'Загрузить документ'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasFile
                              ? Colors.green.withOpacity(0.2)
                              : const Color(0xFF3b82f6),
                          foregroundColor:
                              hasFile ? Colors.green : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    if (hasFile)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _documentPaths.remove(doc['number']);
                          });
                        },
                        tooltip: 'Удалить документ',
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Загрузка документа (фото или PDF)
  Future<void> _pickDocument(String docNumber, String docName) async {
    try {
      final source = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1e293b),
          title: const Text(
            'Выберите тип файла',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF3b82f6)),
                title:
                    const Text('Фото', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'photo'),
              ),
              ListTile(
                leading:
                    const Icon(Icons.picture_as_pdf, color: Color(0xFF3b82f6)),
                title: const Text('PDF документ',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'pdf'),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      String? filePath;

      if (source == 'photo') {
        // Выбор фото
        final sourceType = await showDialog<ImageSource>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1e293b),
            title: const Text('Выберите источник',
                style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading:
                      const Icon(Icons.camera_alt, color: Color(0xFF3b82f6)),
                  title: const Text('Камера',
                      style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading:
                      const Icon(Icons.photo_library, color: Color(0xFF3b82f6)),
                  title: const Text('Галерея',
                      style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );

        if (sourceType == null) return;

        final XFile? image = await _imagePicker.pickImage(source: sourceType);
        if (image != null) {
          final appDir = await getApplicationDocumentsDirectory();
          final docDir = Directory('${appDir.path}/documents');
          if (!await docDir.exists()) {
            await docDir.create(recursive: true);
          }

          final fileName =
              'doc_${docNumber}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final file = File('${docDir.path}/$fileName');
          await File(image.path).copy(file.path);
          filePath = file.path;
        }
      } else {
        // Выбор PDF
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );

        if (result != null && result.files.single.path != null) {
          final appDir = await getApplicationDocumentsDirectory();
          final docDir = Directory('${appDir.path}/documents');
          if (!await docDir.exists()) {
            await docDir.create(recursive: true);
          }

          final fileName =
              'doc_${docNumber}_${DateTime.now().millisecondsSinceEpoch}.pdf';
          final file = File('${docDir.path}/$fileName');
          await File(result.files.single.path!).copy(file.path);
          filePath = file.path;
        }
      }

      if (filePath != null) {
        setState(() {
          _documentPaths[docNumber] = filePath!;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('Документ загружен: $docName'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки документа: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Интерактивный чертеж для выбора точек контроля
  Widget _buildInteractiveControlScheme() {
    if (_controlSchemeImage == null) {
      return Card(
        color: const Color(0xFF1e293b),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'Схема контроля',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  final source = await showDialog<ImageSource>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1e293b),
                      title: const Text('Выберите источник',
                          style: TextStyle(color: Colors.white)),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.camera_alt,
                                color: Color(0xFF3b82f6)),
                            title: const Text('Камера',
                                style: TextStyle(color: Colors.white)),
                            onTap: () =>
                                Navigator.pop(context, ImageSource.camera),
                          ),
                          ListTile(
                            leading: const Icon(Icons.photo_library,
                                color: Color(0xFF3b82f6)),
                            title: const Text('Галерея',
                                style: TextStyle(color: Colors.white)),
                            onTap: () =>
                                Navigator.pop(context, ImageSource.gallery),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (source != null) {
                    await _pickImage(source, false);
                  }
                },
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('Загрузить схему контроля'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3b82f6),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: const Color(0xFF1e293b),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Схема контроля',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Color(0xFF3b82f6)),
                      onPressed: () async {
                        final source = await showDialog<ImageSource>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF1e293b),
                            title: const Text('Выберите источник',
                                style: TextStyle(color: Colors.white)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.camera_alt,
                                      color: Color(0xFF3b82f6)),
                                  title: const Text('Камера',
                                      style: TextStyle(color: Colors.white)),
                                  onTap: () => Navigator.pop(
                                      context, ImageSource.camera),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.photo_library,
                                      color: Color(0xFF3b82f6)),
                                  title: const Text('Галерея',
                                      style: TextStyle(color: Colors.white)),
                                  onTap: () => Navigator.pop(
                                      context, ImageSource.gallery),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (source != null) {
                          await _pickImage(source, false);
                        }
                      },
                      tooltip: 'Изменить схему',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _controlSchemeImage = null;
                          _checklist.controlSchemeImage = null;
                          _controlPoints.clear();
                        });
                      },
                      tooltip: 'Удалить схему',
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Интерактивная область для выбора точек
          GestureDetector(
            onTapDown: (details) => _addControlPoint(details.localPosition),
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: const Color(0xFF3b82f6), width: 2),
              ),
              child: Stack(
                children: [
                  // Изображение схемы
                  if (_controlSchemeImage != null)
                    Image.file(
                      _controlSchemeImage!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  // Отмеченные точки контроля
                  ..._controlPoints.entries.map((entry) {
                    final point = entry.value;
                    return Positioned(
                      left: (point['x'] as double?) ?? 0.0,
                      top: (point['y'] as double?) ?? 0.0,
                      child: GestureDetector(
                        onTap: () => _editControlPoint(entry.key, point),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                                BorderSide(color: Colors.white, width: 2)),
                          ),
                          child: Center(
                            child: Text(
                              point['number']?.toString() ?? '',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          // Список точек контроля
          if (_controlPoints.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Точки контроля:',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._controlPoints.entries.map((entry) {
                    final point = entry.value;
                    return Card(
                      color: const Color(0xFF0f172a),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red,
                          child: Text(
                            point['number']?.toString() ?? '',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ),
                        title: Text(
                          'Точка ${point['number']}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          'Толщина: ${point['thickness'] ?? 'не указана'} мм',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  color: Color(0xFF3b82f6)),
                              onPressed: () =>
                                  _editControlPoint(entry.key, point),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _controlPoints.remove(entry.key);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  ElevatedButton.icon(
                    onPressed: () => _addControlPointManually(),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить точку вручную'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3b82f6),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Добавление точки контроля при клике на чертеж
  void _addControlPoint(Offset position) {
    final pointId = DateTime.now().millisecondsSinceEpoch.toString();
    final pointNumber = _controlPoints.length + 1;

    setState(() {
      _controlPoints[pointId] = {
        'x': position.dx,
        'y': position.dy,
        'number': pointNumber,
        'thickness': null,
        'comment': null,
      };
    });

    // Сразу открываем диалог для ввода данных
    _editControlPoint(pointId, _controlPoints[pointId]!);
  }

  // Добавление точки контроля вручную
  void _addControlPointManually() {
    final pointId = DateTime.now().millisecondsSinceEpoch.toString();
    final pointNumber = _controlPoints.length + 1;

    setState(() {
      _controlPoints[pointId] = {
        'x': 0.0,
        'y': 0.0,
        'number': pointNumber,
        'thickness': null,
        'comment': null,
      };
    });

    _editControlPoint(pointId, _controlPoints[pointId]!);
  }

  // Редактирование точки контроля
  void _editControlPoint(String pointId, Map<String, dynamic> point) {
    final thicknessController =
        TextEditingController(text: point['thickness']?.toString() ?? '');
    final commentController =
        TextEditingController(text: point['comment']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: Text(
          'Точка контроля ${point['number']}',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: thicknessController,
              decoration: const InputDecoration(
                labelText: 'Толщина, мм',
                labelStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Color(0xFF0f172a),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: commentController,
              decoration: const InputDecoration(
                labelText: 'Комментарий',
                labelStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Color(0xFF0f172a),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Отмена', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _controlPoints[pointId] = {
                  ...point,
                  'thickness': thicknessController.text.isNotEmpty
                      ? double.tryParse(thicknessController.text)
                      : null,
                  'comment': commentController.text.isNotEmpty
                      ? commentController.text
                      : null,
                };
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3b82f6),
              foregroundColor: Colors.white,
            ),
            child: const Text('Сохранить'),
          ),
        ],
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
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitForm,
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
                'Отправить отчет',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
