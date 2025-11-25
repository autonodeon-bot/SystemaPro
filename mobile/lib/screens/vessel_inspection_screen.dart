import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../models/equipment.dart';
import '../models/vessel_checklist.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../data/checklist_constants.dart';

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
  bool _isSubmitting = false;
  final bool _isOfflineMode = false;

  final VesselChecklist _checklist = VesselChecklist();
  File? _factoryPlatePhoto;
  File? _controlSchemeImage;

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Инициализация документов
    for (var doc in ChecklistConstants.documents) {
      _checklist.documents[doc['number']!] = false;
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

        final result = await _apiService.submitInspection(
          equipmentId: widget.equipment.id,
          checklist: _checklist,
          conclusion: _checklist.conclusion,
          datePerformed: datePerformed,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Чек-лист успешно отправлен'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка отправки: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
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
            _buildPhotoSection('Схема контроля', _controlSchemeImage, false),
            _buildAddItemButton('Добавить точку замера', () {
              // TODO: Открыть диалог добавления точки
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: const Color(0xFF1e293b),
        child: CheckboxListTile(
          title: Text(
            '${doc['number']}. ${doc['name']}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          value: _checklist.documents[doc['number']] ?? false,
          onChanged: (value) {
            setState(() {
              _checklist.documents[doc['number']!] = value ?? false;
            });
          },
          activeColor: const Color(0xFF3b82f6),
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
