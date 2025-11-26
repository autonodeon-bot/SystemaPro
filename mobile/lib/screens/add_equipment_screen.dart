import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import '../services/api_service.dart';

class AddEquipmentScreen extends StatefulWidget {
  final String? initialLocation;

  const AddEquipmentScreen({
    super.key,
    this.initialLocation,
  });

  @override
  State<AddEquipmentScreen> createState() => _AddEquipmentScreenState();
}

class _AddEquipmentScreenState extends State<AddEquipmentScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final ApiService _apiService = ApiService();
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _equipmentTypes = [];
  String? _selectedTypeId;
  String? _selectedLocation;

  final List<String> _commonLocations = [
    'НГДУ-1, Цех №1',
    'НГДУ-1, Цех №2',
    'НГДУ-2, Участок А',
    'НГДУ-2, Участок Б',
    'НГДУ-3, Отдел диагностики',
  ];

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _loadEquipmentTypes();
  }

  Future<void> _loadEquipmentTypes() async {
    try {
      final types = await _apiService.getEquipmentTypes();
      setState(() {
        _equipmentTypes = types;
      });
    } catch (e) {
      // Игнорируем ошибку, если типы не загрузились
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() => _isSubmitting = true);

      try {
        final formData = _formKey.currentState!.value;
        
        // Если выбрана новая локация, используем её
        String? location = _selectedLocation;
        if (formData['new_location'] != null && 
            formData['new_location'].toString().trim().isNotEmpty) {
          location = formData['new_location'].toString().trim();
        }

        final equipment = await _apiService.createEquipment(
          name: formData['name'],
          typeId: _selectedTypeId,
          serialNumber: formData['serial_number'],
          location: location,
          attributes: {
            'regNumber': formData['reg_number'],
            'vesselName': formData['vessel_name'],
          },
        );

        if (mounted) {
          Navigator.pop(context, equipment);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка создания оборудования: $e'),
              backgroundColor: Colors.red,
            ),
          );
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
        title: const Text('Добавить оборудование'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: FormBuilder(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Название оборудования
            FormBuilderTextField(
              name: 'name',
              decoration: const InputDecoration(
                labelText: 'Название оборудования *',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3b82f6)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              validator: FormBuilderValidators.required(
                errorText: 'Обязательное поле',
              ),
            ),
            const SizedBox(height: 16),

            // Тип оборудования
            if (_equipmentTypes.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _selectedTypeId,
                decoration: const InputDecoration(
                  labelText: 'Тип оборудования',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3b82f6)),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                dropdownColor: const Color(0xFF1e293b),
                items: _equipmentTypes.map((type) {
                  return DropdownMenuItem<String>(
                    value: type['id']?.toString(),
                    child: Text(type['name'] ?? 'Неизвестный тип'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedTypeId = value;
                  });
                },
              ),
            const SizedBox(height: 16),

            // Заводской номер
            FormBuilderTextField(
              name: 'serial_number',
              decoration: const InputDecoration(
                labelText: 'Заводской номер',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3b82f6)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),

            // Регистрационный номер
            FormBuilderTextField(
              name: 'reg_number',
              decoration: const InputDecoration(
                labelText: 'Регистрационный номер',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3b82f6)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),

            // Наименование сосуда
            FormBuilderTextField(
              name: 'vessel_name',
              decoration: const InputDecoration(
                labelText: 'Наименование сосуда',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3b82f6)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),

            // Местоположение
            const Text(
              'Местоположение',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),

            // Выбор существующего местоположения
            DropdownButtonFormField<String>(
              value: _selectedLocation,
              decoration: const InputDecoration(
                labelText: 'Выберите местоположение',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF3b82f6)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              dropdownColor: const Color(0xFF1e293b),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('-- Выберите --'),
                ),
                ..._commonLocations.map((location) {
                  return DropdownMenuItem<String>(
                    value: location,
                    child: Text(location),
                  );
                }),
                const DropdownMenuItem<String>(
                  value: '__new__',
                  child: Text('+ Добавить новое'),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  if (value == '__new__') {
                    _selectedLocation = null;
                  } else {
                    _selectedLocation = value;
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            // Поле для нового местоположения
            if (_selectedLocation == null)
              FormBuilderTextField(
                name: 'new_location',
                decoration: const InputDecoration(
                  labelText: 'Новое местоположение (НГДУ, цех, отдел) *',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3b82f6)),
                  ),
                  hintText: 'Например: НГДУ-4, Цех №5, Отдел диагностики',
                ),
                style: const TextStyle(color: Colors.white),
                validator: _selectedLocation == null
                    ? FormBuilderValidators.required(
                        errorText: 'Укажите местоположение',
                      )
                    : null,
              ),

            const SizedBox(height: 32),

            // Кнопка создания
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
                      'Создать оборудование',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

