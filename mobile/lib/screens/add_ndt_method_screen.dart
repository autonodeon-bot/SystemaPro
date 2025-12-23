import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/questionnaire.dart';
import 'image_annotation_screen.dart';
import 'weld_defect_annotation_screen.dart';

// Список доступных методов НК
const List<Map<String, String>> NDT_METHODS = [
  {'code': 'ВИК', 'name': 'Визуальный и измерительный контроль'},
  {'code': 'УЗК', 'name': 'Ультразвуковой контроль'},
  {'code': 'РК', 'name': 'Радиографический контроль'},
  {'code': 'МПД', 'name': 'Магнитопорошковая дефектоскопия'},
  {'code': 'КПД', 'name': 'Капиллярная дефектоскопия'},
  {'code': 'ПВК', 'name': 'Пневматический контроль'},
  {'code': 'АК', 'name': 'Акустико-эмиссионный контроль'},
  {'code': 'ТК', 'name': 'Тепловой контроль'},
  {'code': 'УЗТ', 'name': 'Ультразвуковая толщинометрия'},
  {'code': 'ВТК', 'name': 'Вихретоковый контроль'},
  {'code': 'ТВИ', 'name': 'Тепловизионный контроль'},
  {'code': 'ОЭ', 'name': 'Оптико-эмиссионная спектрометрия'},
  {'code': 'ЗРА', 'name': 'Запорно-регулирующая арматура (осмотр/контроль)'},
  {'code': 'СППК', 'name': 'Предохранительные клапаны (осмотр/контроль)'},
  {'code': 'ОВАЛ', 'name': 'Измерение овальности'},
  {'code': 'ПРОГИБ', 'name': 'Измерение прогиба'},
  {'code': 'ТВЕРД', 'name': 'Контроль твердости'},
  {'code': 'МК', 'name': 'Магнитный контроль (МК)'},
  {'code': 'УЗК_СС', 'name': 'УЗК сварных соединений'},
];

class AddNDTMethodScreen extends StatefulWidget {
  final String questionnaireId;
  final NDTMethod? existingMethod;

  const AddNDTMethodScreen({
    super.key,
    required this.questionnaireId,
    this.existingMethod,
  });

  @override
  State<AddNDTMethodScreen> createState() => _AddNDTMethodScreenState();
}

class _AddNDTMethodScreenState extends State<AddNDTMethodScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final _apiService = ApiService();
  bool _isSubmitting = false;
  String? _selectedMethodCode;
  List<String> _annotatedImagePaths = [];

  @override
  void initState() {
    super.initState();
    if (widget.existingMethod != null) {
      _selectedMethodCode = widget.existingMethod!.methodCode;
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      final formData = _formKey.currentState!.value;
      
      setState(() {
        _isSubmitting = true;
      });

      try {
        final methodData = {
          'method_code': _selectedMethodCode ?? formData['method_code'],
          'method_name': NDT_METHODS.firstWhere(
            (m) => m['code'] == (_selectedMethodCode ?? formData['method_code']),
            orElse: () => {'name': formData['method_name'] ?? ''},
          )['name'],
          'is_performed': formData['is_performed'] ?? false,
          'standard': formData['standard'],
          'equipment': formData['equipment'],
          'inspector_name': formData['inspector_name'],
          'inspector_level': formData['inspector_level'],
          'results': formData['results'],
          'defects': formData['defects'],
          'conclusion': formData['conclusion'],
          'performed_date': formData['performed_date'] != null
              ? (formData['performed_date'] as DateTime).toIso8601String()
              : null,
          'photos': _annotatedImagePaths,
          'additional_data': {
            'annotated_images': _annotatedImagePaths,
          },
        };

        await _apiService.addNDTMethod(
          questionnaireId: widget.questionnaireId,
          methodData: methodData,
        );

        if (mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Метод НК успешно добавлен'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingMethod == null
            ? 'Добавить метод НК'
            : 'Редактировать метод НК'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: FormBuilder(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormBuilderDropdown<String>(
              name: 'method_code',
              decoration: const InputDecoration(
                labelText: 'Метод неразрушающего контроля *',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              items: NDT_METHODS.map((method) {
                return DropdownMenuItem(
                  value: method['code'],
                  child: Text(
                    '${method['code']} - ${method['name']}',
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              }).toList(),
              initialValue: widget.existingMethod?.methodCode,
              validator: FormBuilderValidators.required(),
              onChanged: (value) {
                setState(() {
                  _selectedMethodCode = value;
                });
              },
            ),
            const SizedBox(height: 16),
            FormBuilderCheckbox(
              name: 'is_performed',
              title: const Text(
                'Метод проведен',
                style: TextStyle(color: Colors.white70),
              ),
              initialValue: widget.existingMethod?.isPerformed ?? false,
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'standard',
              decoration: const InputDecoration(
                labelText: 'Нормативный документ (ГОСТ, РД)',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              initialValue: widget.existingMethod?.standard,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'equipment',
              decoration: const InputDecoration(
                labelText: 'Используемое оборудование',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              initialValue: widget.existingMethod?.equipment,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'inspector_name',
              decoration: const InputDecoration(
                labelText: 'ФИО инженера',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              initialValue: widget.existingMethod?.inspectorName,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderDropdown<String>(
              name: 'inspector_level',
              decoration: const InputDecoration(
                labelText: 'Уровень инженера',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              items: ['I', 'II', 'III']
                  .map((level) => DropdownMenuItem(
                        value: level,
                        child: Text(
                          level,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ))
                  .toList(),
              initialValue: widget.existingMethod?.inspectorLevel,
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'results',
              decoration: const InputDecoration(
                labelText: 'Результаты контроля',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              initialValue: widget.existingMethod?.results,
              maxLines: 5,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'defects',
              decoration: const InputDecoration(
                labelText: 'Обнаруженные дефекты',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              initialValue: widget.existingMethod?.defects,
              maxLines: 5,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'conclusion',
              decoration: const InputDecoration(
                labelText: 'Заключение',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              initialValue: widget.existingMethod?.conclusion,
              maxLines: 5,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderDateTimePicker(
              name: 'performed_date',
              decoration: const InputDecoration(
                labelText: 'Дата проведения',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              initialValue: widget.existingMethod?.performedDate,
              inputType: InputType.date,
              format: DateFormat('yyyy-MM-dd'),
            ),
            const SizedBox(height: 16),
            // Кнопки для аннотирования изображений
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ImageAnnotationScreen(
                            title: 'Аннотирование для ${_selectedMethodCode ?? "метода НК"}',
                          ),
                        ),
                      );
                      if (result != null && result is File) {
                        setState(() {
                          _annotatedImagePaths.add(result.path);
                        });
                      }
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Аннотировать изображение'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3b82f6),
                    ),
                  ),
                ),
              ],
            ),
            if (_selectedMethodCode == 'УЗК_СС' || _selectedMethodCode == 'УЗК')
              const SizedBox(height: 8),
            if (_selectedMethodCode == 'УЗК_СС' || _selectedMethodCode == 'УЗК')
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const WeldDefectAnnotationScreen(),
                          ),
                        );
                        if (result != null && result is File) {
                          setState(() {
                            _annotatedImagePaths.add(result.path);
                          });
                        }
                      },
                      icon: const Icon(Icons.build),
                      label: const Text('Дефекты сварного шва'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10b981),
                      ),
                    ),
                  ),
                ],
              ),
            if (_annotatedImagePaths.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Аннотированные изображения:',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    ..._annotatedImagePaths.asMap().entries.map((entry) {
                      return ListTile(
                        leading: const Icon(Icons.image, color: Colors.blue),
                        title: Text(
                          'Изображение ${entry.key + 1}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          entry.value,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              _annotatedImagePaths.removeAt(entry.key);
                            });
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                disabledBackgroundColor: Colors.grey,
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
                      'Сохранить',
                      style: TextStyle(
                        color: Colors.white,
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






