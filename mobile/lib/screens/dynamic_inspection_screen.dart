import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../services/sync_provider.dart';
import '../services/api_service.dart';
import '../services/offline_auth_provider.dart';

/// Экран динамической инспекции с поддержкой офлайн-режима
class DynamicInspectionScreen extends StatefulWidget {
  final String equipmentId;
  final Map<String, dynamic>? schema; // JSON Schema для формы
  final bool isOffline;

  const DynamicInspectionScreen({
    super.key,
    required this.equipmentId,
    this.schema,
    this.isOffline = false,
  });

  @override
  State<DynamicInspectionScreen> createState() => _DynamicInspectionScreenState();
}

class _DynamicInspectionScreenState extends State<DynamicInspectionScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isSubmitting = false;
  bool _isOffline = false;
  final Map<String, File?> _photoFiles = {};
  final Map<String, String> _photoPaths = {};

  @override
  void initState() {
    super.initState();
    _isOffline = widget.isOffline;
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final isConnected = await _apiService.checkConnection();
    setState(() {
      _isOffline = !isConnected || widget.isOffline;
    });
  }

  Future<void> _pickPhoto(String fieldName) async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _photoFiles[fieldName] = File(image.path);
          _photoPaths[fieldName] = image.path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при выборе фото: $e')),
        );
      }
    }
  }

  Future<void> _submitInspection() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() => _isSubmitting = true);

      try {
        final formData = _formKey.currentState!.value;
        final clientId = const Uuid().v4(); // Локальный UUID

        // Формируем данные инспекции
        final inspectionData = {
          'equipment_id': widget.equipmentId,
          'data': formData,
          'conclusion': formData['conclusion'],
          'date_performed': formData['date_performed']?.toString() ?? DateTime.now().toIso8601String(),
          'status': 'DRAFT',
        };

        if (_isOffline) {
          // Сохраняем в локальную БД
          await _saveInspectionOffline(clientId, inspectionData);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Инспекция сохранена локально. Будет синхронизирована при подключении к интернету.'),
              ),
            );
            Navigator.pop(context);
          }
        } else {
          // Отправляем на сервер
          await _apiService.submitInspection(
            equipmentId: widget.equipmentId,
            checklist: _convertToChecklist(formData),
            conclusion: formData['conclusion'],
            datePerformed: DateTime.tryParse(formData['date_performed']?.toString() ?? ''),
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Инспекция успешно отправлена')),
            );
            Navigator.pop(context);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка при сохранении: $e')),
          );
        }
      } finally {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _saveInspectionOffline(String clientId, Map<String, dynamic> inspectionData) async {
    // Сохранение в локальную БД через AppDatabase
    // Примечание: требуется настроить провайдер databaseProvider в main.dart
    try {
      // TODO: После настройки провайдера раскомментировать:
      // final database = Provider.of<AppDatabase>(context, listen: false);
      // await database.into(database.inspections).insert(
      //   InspectionsCompanion.insert(
      //     clientId: clientId,
      //     equipmentId: inspectionData['equipment_id'],
      //     data: json.encode(inspectionData['data']),
      //     conclusion: Value(inspectionData['conclusion']),
      //     status: 'DRAFT',
      //     isSynced: false,
      //   ),
      // );
      
      // Сохраняем фото
      for (final entry in _photoPaths.entries) {
        // TODO: После настройки провайдера:
        // await database.into(database.inspectionFiles).insert(
        //   InspectionFilesCompanion.insert(
        //     id: const Uuid().v4(),
        //     inspectionClientId: clientId,
        //     filePath: entry.value,
        //     fileName: entry.key,
        //     fileSize: await File(entry.value).length(),
        //     mimeType: 'image/jpeg',
        //     isSynced: false,
        //   ),
        // );
      }
      
      // Временное решение: сохраняем в SharedPreferences для совместимости
      final prefs = await SharedPreferences.getInstance();
      final pendingInspections = prefs.getStringList('pending_inspections') ?? [];
      pendingInspections.add(json.encode({
        'client_id': clientId,
        ...inspectionData,
      }));
      await prefs.setStringList('pending_inspections', pendingInspections);
    } catch (e) {
      throw Exception('Ошибка сохранения в офлайн-режиме: $e');
    }
  }

  dynamic _convertToChecklist(Map<String, dynamic> formData) {
    // Конвертируем данные формы в VesselChecklist
    // Это упрощенная версия - в production нужно правильное преобразование
    return formData;
  }

  Widget _buildField(Map<String, dynamic> field) {
    final fieldType = field['type'] as String? ?? 'text';
    final fieldName = field['name'] as String? ?? '';
    final label = field['label'] as String? ?? fieldName;

    switch (fieldType) {
      case 'text':
        return FormBuilderTextField(
          name: fieldName,
          decoration: InputDecoration(labelText: label),
          validator: FormBuilderValidators.compose([
            if (field['required'] == true) FormBuilderValidators.required(),
          ]),
        );

      case 'number':
        return FormBuilderTextField(
          name: fieldName,
          decoration: InputDecoration(labelText: label),
          keyboardType: TextInputType.number,
          validator: FormBuilderValidators.compose([
            if (field['required'] == true) FormBuilderValidators.required(),
            FormBuilderValidators.numeric(),
          ]),
        );

      case 'date':
        return FormBuilderDateTimePicker(
          name: fieldName,
          decoration: InputDecoration(labelText: label),
          inputType: InputType.date,
          validator: FormBuilderValidators.compose([
            if (field['required'] == true) FormBuilderValidators.required(),
          ]),
        );

      case 'photo':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_photoFiles[fieldName] != null)
              Image.file(
                _photoFiles[fieldName]!,
                height: 200,
                fit: BoxFit.cover,
              )
            else
              Container(
                height: 200,
                color: Colors.grey[300],
                child: const Center(child: Text('Нет фото')),
              ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _pickPhoto(fieldName),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Сделать фото'),
            ),
          ],
        );

      case 'textarea':
        return FormBuilderTextField(
          name: fieldName,
          decoration: InputDecoration(labelText: label),
          maxLines: 5,
          validator: FormBuilderValidators.compose([
            if (field['required'] == true) FormBuilderValidators.required(),
          ]),
        );

      default:
        return FormBuilderTextField(
          name: fieldName,
          decoration: InputDecoration(labelText: label),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Используем схему по умолчанию, если не передана
    final schema = widget.schema ?? {
      'sections': [
        {
          'title': 'Основная информация',
          'fields': [
            {'name': 'date_performed', 'type': 'date', 'label': 'Дата обследования', 'required': true},
            {'name': 'conclusion', 'type': 'textarea', 'label': 'Заключение'},
          ],
        },
      ],
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_isOffline ? 'Инспекция (Офлайн)' : 'Инспекция'),
        actions: [
          if (_isOffline)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.cloud_off, color: Colors.orange),
            ),
        ],
      ),
      body: FormBuilder(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isOffline)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Офлайн-режим. Данные будут сохранены локально.',
                        style: TextStyle(color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ...(schema['sections'] as List? ?? []).map<Widget>((section) {
              return ExpansionTile(
                title: Text(section['title'] ?? 'Раздел'),
                initiallyExpanded: true,
                children: [
                  ...(section['fields'] as List? ?? []).map<Widget>((field) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: _buildField(field),
                    );
                  }),
                ],
              );
            }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSubmitting ? null : _submitInspection,
        icon: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save),
        label: Text(_isSubmitting ? 'Сохранение...' : 'Сохранить'),
      ),
    );
  }
}

