import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../models/equipment.dart';
import '../models/questionnaire.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';
import '../utils/file_naming.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuestionnaireScreen extends StatefulWidget {
  final Equipment equipment;
  final String? inventoryNumber; // Инвентарный номер

  const QuestionnaireScreen({
    super.key,
    required this.equipment,
    this.inventoryNumber,
  });

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  final SyncService _syncService = SyncService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isSubmitting = false;
  bool _isOffline = false;
  bool _autoSync = true; // Автоматическая отправка по умолчанию

  final Questionnaire _questionnaire = Questionnaire();
  final AuthService _authService = AuthService();

  // Хранилище фото: ключ - itemId, значение - путь к файлу
  final Map<String, String> _photoPaths = {};
  // Хранилище информации о фото: ключ - itemId, значение - QuestionnaireItem
  final Map<String, QuestionnaireItem> _photoItems = {};
  // Хранилище документов: ключ - itemId, значение - путь к файлу (PDF или фото)
  final Map<String, String> _documentPaths = {};

  // Инвентарный номер (из equipment или переданный)
  String get _inventoryNumber {
    return widget.inventoryNumber ??
        widget.equipment.attributes?['inventoryNumber'] ??
        widget.equipment.serialNumber ??
        'UNKNOWN';
  }

  @override
  void initState() {
    super.initState();
    _questionnaire.equipmentId = widget.equipment.id;
    _questionnaire.equipmentInventoryNumber = _inventoryNumber;
    _questionnaire.equipmentName = widget.equipment.name;
    _checkConnection();
    _loadAutoSyncSetting();
    _loadEquipmentData();
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

        // Автозаполнение места установки
        if (widget.equipment.location != null &&
            (formData['location'] == null ||
                formData['location'].toString().isEmpty)) {
          _formKey.currentState!.fields['location']
              ?.didChange(widget.equipment.location);
        }

        // Автозаполнение заводского номера
        if (widget.equipment.serialNumber != null &&
            (formData['serial_number'] == null ||
                formData['serial_number'].toString().isEmpty)) {
          _formKey.currentState!.fields['serial_number']
              ?.didChange(widget.equipment.serialNumber);
        }

        // Автозаполнение даты ввода в эксплуатацию
        if (widget.equipment.commissioningDate != null) {
          try {
            final date = DateTime.parse(widget.equipment.commissioningDate!);
            final dateStr = DateFormat('yyyy-MM-dd').format(date);
            if (formData['installation_date'] == null ||
                formData['installation_date'].toString().isEmpty) {
              _formKey.currentState!.fields['installation_date']
                  ?.didChange(dateStr);
            }
          } catch (_) {}
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
          }

          // Толщина стенки
          if (attrs['wall_thickness'] != null &&
              (formData['wall_thickness'] == null ||
                  formData['wall_thickness'].toString().isEmpty)) {
            _formKey.currentState!.fields['wall_thickness']
                ?.didChange(attrs['wall_thickness'].toString());
          }

          // Материал
          if (attrs['material'] != null &&
              (formData['material'] == null ||
                  formData['material'].toString().isEmpty)) {
            _formKey.currentState!.fields['material']
                ?.didChange(attrs['material'].toString());
          }

          // Рабочее давление
          if (attrs['operating_pressure'] != null &&
              (formData['operating_pressure'] == null ||
                  formData['operating_pressure'].toString().isEmpty)) {
            _formKey.currentState!.fields['operating_pressure']
                ?.didChange(attrs['operating_pressure'].toString());
          }

          // Рабочая температура
          if (attrs['operating_temperature'] != null &&
              (formData['operating_temperature'] == null ||
                  formData['operating_temperature'].toString().isEmpty)) {
            _formKey.currentState!.fields['operating_temperature']
                ?.didChange(attrs['operating_temperature'].toString());
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

  Future<void> _pickPhoto(String itemId, String itemName) async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1e293b),
          title: const Text(
            'Выберите источник',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF3b82f6)),
                title:
                    const Text('Камера', style: TextStyle(color: Colors.white)),
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

      if (source == null) return;

      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) return;

      // Получаем директорию для сохранения
      final appDir = await getApplicationDocumentsDirectory();
      final baseDir = Directory('${appDir.path}/questionnaires');

      // Генерируем путь к файлу
      final filePath = await FileNaming.generateFilePath(
        baseDirectory: baseDir,
        inventoryNumber: _inventoryNumber,
        itemName: itemName,
        itemId: itemId,
        extension: 'jpg',
      );

      // Копируем файл
      final file = File(image.path);
      await file.copy(filePath);

      // Сохраняем информацию о фото
      setState(() {
        _photoPaths[itemId] = filePath;
        _photoItems[itemId] = QuestionnaireItem(
          id: itemId,
          title: itemName,
          photos: [filePath],
        );
      });

      // Показываем уведомление
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Фото прикреплено: $itemName'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при прикреплении фото: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildPhotoButton(String itemId, String itemName) {
    final hasPhoto = _photoPaths.containsKey(itemId);

    return InkWell(
      onTap: () => _pickPhoto(itemId, itemName),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasPhoto
              ? Colors.green.withOpacity(0.2)
              : const Color(0xFF1e293b),
          border: Border.all(
            color: hasPhoto ? Colors.green : const Color(0xFF3b82f6),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasPhoto ? Icons.check_circle : Icons.add_photo_alternate,
              color: hasPhoto ? Colors.green : const Color(0xFF3b82f6),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              hasPhoto ? 'Фото прикреплено' : 'Прикрепить фото',
              style: TextStyle(
                color: hasPhoto ? Colors.green : const Color(0xFF3b82f6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
            borderSide: const BorderSide(color: Color(0xFF3b82f6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3b82f6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3b82f6), width: 2),
          ),
        ),
        style: const TextStyle(color: Colors.white),
        onChanged: (value) => onChanged(value),
      ),
    );
  }

  Widget _buildDateField(
      String name, String label, Function(DateTime?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FormBuilderDateTimePicker(
        name: name,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF1e293b),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3b82f6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3b82f6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3b82f6), width: 2),
          ),
          suffixIcon:
              const Icon(Icons.calendar_today, color: Color(0xFF3b82f6)),
        ),
        style: const TextStyle(color: Colors.white),
        inputType: InputType.date,
        format: DateFormat('yyyy-MM-dd'),
        onChanged: (value) => onChanged(value),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 16),
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

  Future<void> _submitForm() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() => _isSubmitting = true);

      try {
        // Заполняем данные опросного листа из формы
        final formData = _formKey.currentState!.value;

        // Раздел 1: Общие сведения
        _questionnaire.section1.location = QuestionnaireItem(
          id: 'location',
          title: 'Место установки',
          value: formData['location'],
        );
        _questionnaire.section1.installationDate = QuestionnaireItem(
          id: 'installation_date',
          title: 'Дата установки',
          value: formData['installation_date']?.toString(),
        );
        _questionnaire.section1.operatingPressure = QuestionnaireItem(
          id: 'operating_pressure',
          title: 'Рабочее давление',
          value: formData['operating_pressure'],
        );
        _questionnaire.section1.operatingTemperature = QuestionnaireItem(
          id: 'operating_temperature',
          title: 'Рабочая температура',
          value: formData['operating_temperature'],
        );

        // Раздел 2: Технические характеристики
        _questionnaire.section2.designPressure = QuestionnaireItem(
          id: 'design_pressure',
          title: 'Расчетное давление',
          value: formData['design_pressure'],
        );
        _questionnaire.section2.diameter = QuestionnaireItem(
          id: 'diameter',
          title: 'Диаметр',
          value: formData['diameter'],
        );
        _questionnaire.section2.wallThickness = QuestionnaireItem(
          id: 'wall_thickness',
          title: 'Толщина стенки',
          value: formData['wall_thickness'],
        );
        _questionnaire.section2.material = QuestionnaireItem(
          id: 'material',
          title: 'Материал изготовления',
          value: formData['material'],
        );

        // Раздел 3: Состояние основного металла
        _questionnaire.section3.externalCondition = QuestionnaireItem(
          id: 'external_condition',
          title: 'Состояние наружной поверхности',
          value: formData['external_condition'],
        );
        _questionnaire.section3.internalCondition = QuestionnaireItem(
          id: 'internal_condition',
          title: 'Состояние внутренней поверхности',
          value: formData['internal_condition'],
        );
        _questionnaire.section3.hasDeformations = QuestionnaireItem(
          id: 'has_deformations',
          title: 'Наличие деформаций',
          booleanValue: formData['has_deformations'],
        );

        // Добавляем фото к соответствующим пунктам
        _photoItems.forEach((itemId, item) {
          // Находим соответствующий пункт и добавляем фото
          if (itemId.startsWith('section1_')) {
            _questionnaire.section1.generalPhotos.add(item);
          } else if (itemId.startsWith('section3_')) {
            _questionnaire.section3.metalPhotos.add(item);
          } else if (itemId.startsWith('section4_')) {
            _questionnaire.section4.weldPhotos.add(item);
          } else if (itemId.startsWith('section5_')) {
            _questionnaire.section5.armaturePhotos.add(item);
          } else if (itemId.startsWith('section6_')) {
            _questionnaire.section6.supportPhotos.add(item);
          } else if (itemId.startsWith('section7_')) {
            _questionnaire.section7.internalPhotos.add(item);
          } else if (itemId.startsWith('section8_')) {
            _questionnaire.section8.ndtPhotos.add(item);
          } else if (itemId.startsWith('section9_')) {
            _questionnaire.section9.conclusionPhotos.add(item);
          } else if (itemId.startsWith('section10_')) {
            _questionnaire.section10.recommendationPhotos.add(item);
          }
        });

        // Заполняем дату обследования
        _questionnaire.inspectionDate =
            formData['inspection_date']?.toString() ??
                DateTime.now().toIso8601String();

        // Проверяем подключение
        final isConnected = await _apiService.checkConnection();

        if (isConnected) {
          // Отправляем на сервер
          await _apiService.submitQuestionnaire(_questionnaire, _photoPaths);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Опросный лист успешно отправлен'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context, true);
          }
        } else {
          // Сохраняем локально для последующей синхронизации
          await _syncService.saveQuestionnaireOffline(
              _questionnaire, _photoPaths);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Опросный лист сохранен локально. Будет отправлен при появлении интернета.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
            Navigator.pop(context, true);
          }
        }
      } catch (e) {
        // При ошибке тоже сохраняем локально
        try {
          await _syncService.saveQuestionnaireOffline(
              _questionnaire, _photoPaths);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка отправки. Данные сохранены локально: $e'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        } catch (offlineError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка сохранения: $e'),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Опросный лист'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        actions: [
          if (_isOffline)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Icon(Icons.wifi_off, color: Colors.orange),
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
            // Информация об оборудовании
            Card(
              color: const Color(0xFF1e293b),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.equipment.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Инвентарный номер: $_inventoryNumber',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    if (widget.equipment.location != null)
                      Text(
                        'Место: ${widget.equipment.location}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Раздел 1: Общие сведения
            _buildSectionHeader('1. Общие сведения об объекте'),
            _buildTextField('location', 'Место установки', (value) {}),
            _buildDateField('installation_date', 'Дата установки', (value) {}),
            _buildTextField(
                'operating_pressure', 'Рабочее давление, МПа', (value) {}),
            _buildTextField(
                'operating_temperature', 'Рабочая температура, °C', (value) {}),
            _buildTextField('working_environment', 'Рабочая среда', (value) {}),
            Row(
              children: [
                const Text('Общие фото объекта:',
                    style: TextStyle(color: Colors.white70)),
                const Spacer(),
                _buildPhotoButton('section1_general_1', 'Общие фото объекта'),
              ],
            ),

            const SizedBox(height: 16),

            // Раздел 2: Технические характеристики
            _buildSectionHeader('2. Технические характеристики'),
            _buildTextField(
                'design_pressure', 'Расчетное давление, МПа', (value) {}),
            _buildTextField(
                'design_temperature', 'Расчетная температура, °C', (value) {}),
            _buildTextField('volume', 'Объем, м³', (value) {}),
            _buildTextField('diameter', 'Диаметр, мм', (value) {}),
            _buildTextField('wall_thickness', 'Толщина стенки, мм', (value) {}),
            _buildTextField('material', 'Материал изготовления', (value) {}),
            _buildTextField('manufacturer', 'Изготовитель', (value) {}),
            _buildTextField('manufacture_year', 'Год изготовления', (value) {}),
            _buildTextField('serial_number', 'Заводской номер', (value) {}),
            _buildTextField('reg_number', 'Регистрационный номер', (value) {}),
            Row(
              children: [
                const Text('Фото заводской таблички:',
                    style: TextStyle(color: Colors.white70)),
                const Spacer(),
                _buildPhotoButton(
                    'section2_factory_plate', 'Заводская табличка'),
              ],
            ),

            const SizedBox(height: 16),

            // Раздел 3: Состояние основного металла
            _buildSectionHeader('3. Состояние основного металла'),
            _buildTextField('external_condition',
                'Состояние наружной поверхности', (value) {}),
            _buildTextField('internal_condition',
                'Состояние внутренней поверхности', (value) {}),
            _buildTextField(
                'corrosion_state', 'Состояние коррозии', (value) {}),
            FormBuilderCheckbox(
              name: 'has_deformations',
              title: const Text('Наличие деформаций',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField(
                'deformation_description', 'Описание деформаций', (value) {}),
            FormBuilderCheckbox(
              name: 'has_cracks',
              title: const Text('Наличие трещин',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField(
                'cracks_description', 'Описание трещин', (value) {}),
            Row(
              children: [
                const Text('Фото состояния металла:',
                    style: TextStyle(color: Colors.white70)),
                const Spacer(),
                _buildPhotoButton('section3_metal_1', 'Состояние металла'),
              ],
            ),

            const SizedBox(height: 16),

            // Раздел 4: Сварные соединения
            _buildSectionHeader('4. Сварные соединения'),
            _buildTextField('total_weld_count',
                'Общее количество сварных соединений', (value) {}),
            _buildTextField('inspected_weld_count',
                'Количество обследованных соединений', (value) {}),
            _buildTextField(
                'weld_condition', 'Состояние сварных соединений', (value) {}),
            FormBuilderCheckbox(
              name: 'has_weld_defects',
              title: const Text('Наличие дефектов',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField(
                'weld_defects_description', 'Описание дефектов', (value) {}),
            Row(
              children: [
                const Text('Фото сварных соединений:',
                    style: TextStyle(color: Colors.white70)),
                const Spacer(),
                _buildPhotoButton('section4_weld_1', 'Сварные соединения'),
              ],
            ),

            const SizedBox(height: 16),

            // Раздел 5: Арматура и КИП
            _buildSectionHeader('5. Арматура и КИП'),
            _buildTextField(
                'armature_condition', 'Состояние арматуры', (value) {}),
            _buildTextField('armature_type', 'Тип арматуры', (value) {}),
            _buildTextField(
                'armature_count', 'Количество арматуры', (value) {}),
            FormBuilderCheckbox(
              name: 'has_safety_valves',
              title: const Text('Наличие предохранительных клапанов',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField(
                'safety_valves_condition', 'Состояние ПК', (value) {}),
            FormBuilderCheckbox(
              name: 'has_gauges',
              title: const Text('Наличие манометров',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField(
                'gauges_condition', 'Состояние манометров', (value) {}),
            Row(
              children: [
                const Text('Фото арматуры и КИП:',
                    style: TextStyle(color: Colors.white70)),
                const Spacer(),
                _buildPhotoButton('section5_armature_1', 'Арматура и КИП'),
              ],
            ),

            const SizedBox(height: 16),

            // Раздел 6: Опоры и крепления
            _buildSectionHeader('6. Опоры и крепления'),
            _buildTextField('supports_type', 'Тип опор', (value) {}),
            _buildTextField('supports_condition', 'Состояние опор', (value) {}),
            FormBuilderCheckbox(
              name: 'has_support_defects',
              title: const Text('Наличие дефектов опор',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField(
                'support_defects_description', 'Описание дефектов', (value) {}),
            _buildTextField('fasteners_condition',
                'Состояние крепежных элементов', (value) {}),
            Row(
              children: [
                const Text('Фото опор и креплений:',
                    style: TextStyle(color: Colors.white70)),
                const Spacer(),
                _buildPhotoButton('section6_support_1', 'Опоры и крепления'),
              ],
            ),

            const SizedBox(height: 16),

            // Раздел 7: Внутренние устройства
            _buildSectionHeader('7. Внутренние устройства'),
            FormBuilderCheckbox(
              name: 'has_internal_devices',
              title: const Text('Наличие внутренних устройств',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField('internal_devices_type', 'Тип внутренних устройств',
                (value) {}),
            _buildTextField('internal_devices_condition',
                'Состояние внутренних устройств', (value) {}),
            _buildTextField('internal_devices_description',
                'Описание внутренних устройств', (value) {}),
            Row(
              children: [
                const Text('Фото внутренних устройств:',
                    style: TextStyle(color: Colors.white70)),
                const Spacer(),
                _buildPhotoButton(
                    'section7_internal_1', 'Внутренние устройства'),
              ],
            ),

            const SizedBox(height: 16),

            // Раздел 8: Результаты неразрушающего контроля
            _buildSectionHeader('8. Результаты неразрушающего контроля'),
            FormBuilderCheckbox(
              name: 'has_visual_inspection',
              title: const Text('Проведен ВИК',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField(
                'visual_inspection_results', 'Результаты ВИК', (value) {}),
            FormBuilderCheckbox(
              name: 'has_ultrasonic_testing',
              title: const Text('Проведен УЗК',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField(
                'ultrasonic_testing_results', 'Результаты УЗК', (value) {}),
            FormBuilderCheckbox(
              name: 'has_thickness_measurement',
              title: const Text('Проведена УЗТ',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField(
                'thickness_measurement_results', 'Результаты УЗТ', (value) {}),
            _buildTextField(
                'min_thickness', 'Минимальная толщина, мм', (value) {}),
            _buildTextField(
                'max_thickness', 'Максимальная толщина, мм', (value) {}),
            Row(
              children: [
                const Text('Фото НК:', style: TextStyle(color: Colors.white70)),
                const Spacer(),
                _buildPhotoButton('section8_ndt_1', 'НК результаты'),
              ],
            ),

            const SizedBox(height: 16),

            // Раздел 9: Заключение
            _buildSectionHeader('9. Заключение о техническом состоянии'),
            _buildTextField(
                'technical_state', 'Техническое состояние', (value) {}),
            FormBuilderCheckbox(
              name: 'can_operate',
              title: const Text('Может ли эксплуатироваться',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField(
                'operating_conditions', 'Условия эксплуатации', (value) {}),
            FormBuilderCheckbox(
              name: 'has_restrictions',
              title: const Text('Наличие ограничений',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField(
                'restrictions_description', 'Описание ограничений', (value) {}),
            _buildTextField(
                'remaining_resource', 'Остаточный ресурс', (value) {}),
            _buildDateField('next_inspection_date',
                'Дата следующего обследования', (value) {}),
            Row(
              children: [
                const Text('Фото для заключения:',
                    style: TextStyle(color: Colors.white70)),
                const Spacer(),
                _buildPhotoButton('section9_conclusion_1', 'Заключение'),
              ],
            ),

            const SizedBox(height: 16),

            // Раздел 10: Рекомендации
            _buildSectionHeader(
                '10. Рекомендации по продлению срока эксплуатации'),
            FormBuilderCheckbox(
              name: 'can_extend_service_life',
              title: const Text('Можно ли продлить срок эксплуатации',
                  style: TextStyle(color: Colors.white70)),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            _buildTextField('recommended_extension_period',
                'Рекомендуемый период продления', (value) {}),
            _buildTextField(
                'required_repairs', 'Требуемые ремонты', (value) {}),
            _buildTextField(
                'repairs_description', 'Описание ремонтов', (value) {}),
            _buildTextField(
                'required_maintenance', 'Требуемое обслуживание', (value) {}),
            _buildTextField(
                'maintenance_description', 'Описание обслуживания', (value) {}),
            _buildTextField('additional_requirements',
                'Дополнительные требования', (value) {}),
            Row(
              children: [
                const Text('Фото для рекомендаций:',
                    style: TextStyle(color: Colors.white70)),
                const Spacer(),
                _buildPhotoButton('section10_recommendation_1', 'Рекомендации'),
              ],
            ),

            const SizedBox(height: 32),

            // Кнопка отправки
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3b82f6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Сохранить опросный лист',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
