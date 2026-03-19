import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/questionnaire.dart';

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
  final List<String> _annotatedImagePaths = [];

  // Динамические списки для метод-специфичных данных
  final List<Map<String, TextEditingController>> _measurementPoints = [];
  final List<Map<String, TextEditingController>> _defectsList = [];
  final List<Map<String, TextEditingController>> _indicationsList = [];
  final List<Map<String, TextEditingController>> _uzkResults = [];

  @override
  void initState() {
    super.initState();
    if (widget.existingMethod != null) {
      _selectedMethodCode = widget.existingMethod!.methodCode;
      _restoreMethodSpecificData();
    }
  }

  @override
  void dispose() {
    for (final list in [_measurementPoints, _defectsList, _indicationsList, _uzkResults]) {
      for (final item in list) {
        for (final ctrl in item.values) {
          ctrl.dispose();
        }
      }
    }
    super.dispose();
  }

  void _restoreMethodSpecificData() {
    final ad = widget.existingMethod?.additionalData;
    if (ad == null || ad is! Map<String, dynamic>) return;

    final points = ad['measurement_points'] as List?;
    if (points != null) {
      for (final p in points) {
        if (p is Map) {
          _measurementPoints.add({
            'location': TextEditingController(text: p['location']?.toString() ?? ''),
            'thickness': TextEditingController(text: p['thickness']?.toString() ?? ''),
          });
        }
      }
    }

    final defects = ad['defects_list'] as List?;
    if (defects != null) {
      for (final d in defects) {
        if (d is Map) {
          _defectsList.add({
            'element': TextEditingController(text: d['element']?.toString() ?? ''),
            'description': TextEditingController(text: d['description']?.toString() ?? ''),
            'size': TextEditingController(text: d['size']?.toString() ?? ''),
            'classification': TextEditingController(text: d['classification']?.toString() ?? ''),
          });
        }
      }
    }

    final indications = ad['indications_list'] as List?;
    if (indications != null) {
      for (final ind in indications) {
        if (ind is Map) {
          _indicationsList.add({
            'zone': TextEditingController(text: ind['zone']?.toString() ?? ''),
            'indication': TextEditingController(text: ind['indication']?.toString() ?? ''),
            'size': TextEditingController(text: ind['size']?.toString() ?? ''),
            'assessment': TextEditingController(text: ind['assessment']?.toString() ?? ''),
          });
        }
      }
    }

    final uzk = ad['results_list'] as List?;
    if (uzk != null) {
      for (final r in uzk) {
        if (r is Map) {
          _uzkResults.add({
            'zone': TextEditingController(text: r['zone']?.toString() ?? ''),
            'coordinate': TextEditingController(text: r['coordinate']?.toString() ?? ''),
            'amplitude': TextEditingController(text: r['amplitude']?.toString() ?? ''),
            'equivalent_size': TextEditingController(text: r['equivalent_size']?.toString() ?? ''),
          });
        }
      }
    }
  }

  void _clearMethodSpecificData() {
    for (final list in [_measurementPoints, _defectsList, _indicationsList, _uzkResults]) {
      for (final item in list) {
        for (final ctrl in item.values) {
          ctrl.dispose();
        }
      }
      list.clear();
    }
  }

  InputDecoration _inputDeco(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white30),
      border: const OutlineInputBorder(),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white24),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.blue),
      ),
    );
  }

  Map<String, dynamic> _collectMethodSpecificData() {
    final formData = _formKey.currentState?.value ?? {};
    final code = (_selectedMethodCode ?? '').toUpperCase();
    final Map<String, dynamic> ad = {
      'annotated_images': _annotatedImagePaths.toList(),
    };

    switch (code) {
      case 'ВИК':
        ad['control_zone'] = formData['method_control_zone'];
        ad['illumination'] = formData['method_illumination'];
        ad['surface_temp'] = formData['method_surface_temp'];
        ad['defects_list'] = _defectsList
            .map((d) => {
                  return {
                    'element': d['element']?.text ?? '',
                    'description': d['description']?.text ?? '',
                    'size': d['size']?.text ?? '',
                    'classification': d['classification']?.text ?? '',
                  };
                })
            .where((m) => m.values.any((v) => v.isNotEmpty))
            .toList();
        break;

      case 'УЗК':
      case 'УЗК_СС':
        ad['device_type'] = formData['method_device_type'];
        ad['transducer_type'] = formData['method_transducer_type'];
        ad['frequency_mhz'] = formData['method_frequency'];
        ad['angle_deg'] = formData['method_angle'];
        ad['reference_sample'] = formData['method_reference_sample'];
        ad['control_zone'] = formData['method_control_zone'];
        ad['results_list'] = _uzkResults
            .map((r) => {
                  return {
                    'zone': r['zone']?.text ?? '',
                    'coordinate': r['coordinate']?.text ?? '',
                    'amplitude': r['amplitude']?.text ?? '',
                    'equivalent_size': r['equivalent_size']?.text ?? '',
                  };
                })
            .where((m) => m.values.any((v) => v.isNotEmpty))
            .toList();
        break;

      case 'УЗТ':
        ad['device_type'] = formData['method_device_type'];
        ad['device_serial'] = formData['method_device_serial'];
        ad['nominal_thickness'] = formData['method_nominal_thickness'];
        ad['min_allowed_thickness'] = formData['method_min_thickness'];
        ad['corrosion_rate'] = formData['method_corrosion_rate'];
        ad['measurement_points'] = _measurementPoints
            .map((p) => {
                  return {
                    'location': p['location']?.text ?? '',
                    'thickness': p['thickness']?.text ?? '',
                  };
                })
            .where((m) => m.values.any((v) => v.isNotEmpty))
            .toList();
        break;

      case 'МПД':
      case 'МК':
        ad['magnetization_type'] = formData['method_magnetization_type'];
        ad['field_strength'] = formData['method_field_strength'];
        ad['indicator_suspension'] = formData['method_indicator_suspension'];
        ad['indications_list'] = _indicationsList
            .map((ind) => {
                  return {
                    'zone': ind['zone']?.text ?? '',
                    'indication': ind['indication']?.text ?? '',
                    'size': ind['size']?.text ?? '',
                    'assessment': ind['assessment']?.text ?? '',
                  };
                })
            .where((m) => m.values.any((v) => v.isNotEmpty))
            .toList();
        break;

      case 'ПВК':
      case 'КПД':
        ad['penetrant'] = formData['method_penetrant'];
        ad['developer'] = formData['method_developer'];
        ad['penetrant_time_min'] = formData['method_penetrant_time'];
        ad['surface_temp'] = formData['method_surface_temp'];
        ad['indications_list'] = _indicationsList
            .map((ind) => {
                  return {
                    'zone': ind['zone']?.text ?? '',
                    'indication': ind['indication']?.text ?? '',
                    'size': ind['size']?.text ?? '',
                    'assessment': ind['assessment']?.text ?? '',
                  };
                })
            .where((m) => m.values.any((v) => v.isNotEmpty))
            .toList();
        break;

      case 'РК':
        ad['radiation_source'] = formData['method_radiation_source'];
        ad['energy_kv'] = formData['method_energy_kv'];
        ad['exposure'] = formData['method_exposure'];
        ad['film_detector'] = formData['method_film_detector'];
        ad['sensitivity'] = formData['method_sensitivity'];
        break;
    }

    return ad;
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      final formData = _formKey.currentState!.value;

      setState(() => _isSubmitting = true);

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
          'photos': [],
          'additional_data': _collectMethodSpecificData(),
        };

        final created = await _apiService.addNDTMethod(
          questionnaireId: widget.questionnaireId,
          methodData: methodData,
        );

        final methodId = created['id']?.toString();
        if (methodId != null && _annotatedImagePaths.isNotEmpty) {
          for (final path in _annotatedImagePaths) {
            try {
              final file = File(path);
              if (!file.existsSync()) continue;
              await _apiService.uploadNdtMethodPhoto(
                questionnaireId: widget.questionnaireId,
                methodId: methodId,
                filePath: path,
                annotated: true,
              );
            } catch (e) {
              debugPrint('Ошибка загрузки фото НК: $e');
            }
          }
        }

        if (mounted) {
          context.pop(true);
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
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Билдеры форм по методам НК
  // ══════════════════════════════════════════════════════════════

  Widget _buildMethodSpecificFields() {
    if (_selectedMethodCode == null) return const SizedBox.shrink();
    switch (_selectedMethodCode!.toUpperCase()) {
      case 'ВИК':
        return _buildVIKFields();
      case 'УЗК':
      case 'УЗК_СС':
        return _buildUZKFields();
      case 'УЗТ':
        return _buildUZTFields();
      case 'МПД':
      case 'МК':
        return _buildMPDFields();
      case 'ПВК':
      case 'КПД':
        return _buildPVKFields();
      case 'РК':
        return _buildRKFields();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ── ВИК ──────────────────────────────────────────────────────

  Widget _buildVIKFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Параметры ВИК'),
        FormBuilderTextField(
          name: 'method_control_zone',
          decoration: _inputDeco('Зона контроля'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_illumination',
          decoration: _inputDeco('Освещённость, лк'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_surface_temp',
          decoration: _inputDeco('Температура поверхности, °C'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        _buildDynamicList(
          title: 'Обнаруженные дефекты',
          items: _defectsList,
          fieldLabels: const ['Элемент', 'Описание', 'Размер', 'Классификация'],
          fieldKeys: const ['element', 'description', 'size', 'classification'],
        ),
      ],
    );
  }

  // ── УЗК ──────────────────────────────────────────────────────

  Widget _buildUZKFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Параметры УЗК'),
        FormBuilderDropdown<String>(
          name: 'method_device_type',
          decoration: _inputDeco('Тип прибора'),
          items: const [
            DropdownMenuItem(value: 'УД2-12', child: Text('УД2-12', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'УД2-70', child: Text('УД2-70', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'УД9812', child: Text('УД9812', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'USM Go+', child: Text('USM Go+', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'A1212 MASTER', child: Text('A1212 MASTER', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'Другой', child: Text('Другой', style: TextStyle(color: Colors.white))),
          ],
        ),
        const SizedBox(height: 12),
        FormBuilderDropdown<String>(
          name: 'method_transducer_type',
          decoration: _inputDeco('Тип преобразователя'),
          items: const [
            DropdownMenuItem(value: 'Прямой', child: Text('Прямой', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'Наклонный', child: Text('Наклонный', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'Раздельно-совмещённый', child: Text('Раздельно-совмещённый', style: TextStyle(color: Colors.white))),
          ],
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_frequency',
          decoration: _inputDeco('Частота, МГц'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_angle',
          decoration: _inputDeco('Угол ввода, °'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_reference_sample',
          decoration: _inputDeco('Настроечный образец'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_control_zone',
          decoration: _inputDeco('Зона контроля'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        _buildDynamicList(
          title: 'Результаты сканирования',
          items: _uzkResults,
          fieldLabels: const ['Зона', 'Координата', 'Амплитуда, дБ', 'Эквив. размер, мм'],
          fieldKeys: const ['zone', 'coordinate', 'amplitude', 'equivalent_size'],
        ),
      ],
    );
  }

  // ── УЗТ ──────────────────────────────────────────────────────

  Widget _buildUZTFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Параметры УЗТ'),
        FormBuilderTextField(
          name: 'method_device_type',
          decoration: _inputDeco('Тип прибора'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_device_serial',
          decoration: _inputDeco('Серийный номер прибора'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_nominal_thickness',
          decoration: _inputDeco('Номинальная толщина, мм'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_min_thickness',
          decoration: _inputDeco('Минимально допустимая толщина, мм'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_corrosion_rate',
          decoration: _inputDeco('Скорость коррозии, мм/год'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        _buildDynamicList(
          title: 'Точки замера',
          items: _measurementPoints,
          fieldLabels: const ['Местоположение', 'Толщина, мм'],
          fieldKeys: const ['location', 'thickness'],
        ),
      ],
    );
  }

  // ── МПД / МК ─────────────────────────────────────────────────

  Widget _buildMPDFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Параметры МПД/МК'),
        FormBuilderDropdown<String>(
          name: 'method_magnetization_type',
          decoration: _inputDeco('Тип намагничивания'),
          items: const [
            DropdownMenuItem(value: 'Циркулярное', child: Text('Циркулярное', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'Продольное', child: Text('Продольное', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'Комбинированное', child: Text('Комбинированное', style: TextStyle(color: Colors.white))),
          ],
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_field_strength',
          decoration: _inputDeco('Напряжённость поля, А/м'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_indicator_suspension',
          decoration: _inputDeco('Индикаторная суспензия'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        _buildDynamicList(
          title: 'Обнаруженные индикации',
          items: _indicationsList,
          fieldLabels: const ['Зона', 'Индикация', 'Размер', 'Оценка'],
          fieldKeys: const ['zone', 'indication', 'size', 'assessment'],
        ),
      ],
    );
  }

  // ── ПВК / КПД ────────────────────────────────────────────────

  Widget _buildPVKFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Параметры ПВК'),
        FormBuilderTextField(
          name: 'method_penetrant',
          decoration: _inputDeco('Пенетрант'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_developer',
          decoration: _inputDeco('Проявитель'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_penetrant_time',
          decoration: _inputDeco('Время выдержки пенетранта, мин'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_surface_temp',
          decoration: _inputDeco('Температура поверхности, °C'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        _buildDynamicList(
          title: 'Обнаруженные индикации',
          items: _indicationsList,
          fieldLabels: const ['Зона', 'Индикация', 'Размер', 'Оценка'],
          fieldKeys: const ['zone', 'indication', 'size', 'assessment'],
        ),
      ],
    );
  }

  // ── РК ───────────────────────────────────────────────────────

  Widget _buildRKFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Параметры РК'),
        FormBuilderTextField(
          name: 'method_radiation_source',
          decoration: _inputDeco('Источник излучения'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_energy_kv',
          decoration: _inputDeco('Энергия, кВ'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_exposure',
          decoration: _inputDeco('Экспозиция, мА·мин'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_film_detector',
          decoration: _inputDeco('Плёнка/детектор'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_sensitivity',
          decoration: _inputDeco('Чувствительность контроля'),
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }

  // ── Универсальный динамический список ────────────────────────

  Widget _buildDynamicList({
    required String title,
    required List<Map<String, TextEditingController>> items,
    required List<String> fieldLabels,
    required List<String> fieldKeys,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.blue),
              tooltip: 'Добавить',
              onPressed: () {
                setState(() {
                  final entry = <String, TextEditingController>{};
                  for (final key in fieldKeys) {
                    entry[key] = TextEditingController();
                  }
                  items.add(entry);
                });
              },
            ),
          ],
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Нет записей. Нажмите + для добавления.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ...items.asMap().entries.map((entry) {
          final idx = entry.key;
          final controllers = entry.value;
          return Card(
            color: const Color(0xFF1e293b),
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${title.replaceAll(RegExp(r'ые$|ие$'), 'ая')} ${idx + 1}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          setState(() {
                            for (final ctrl in controllers.values) {
                              ctrl.dispose();
                            }
                            items.removeAt(idx);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...fieldKeys.asMap().entries.map((fe) {
                    final fIdx = fe.key;
                    final fKey = fe.value;
                    final fLabel = fieldLabels[fIdx];
                    final isNumeric = fLabel.contains('мм') ||
                        fLabel.contains('дБ') ||
                        fLabel.contains('°');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: controllers[fKey],
                        keyboardType:
                            isNumeric ? TextInputType.number : TextInputType.text,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: fLabel,
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          border: const OutlineInputBorder(),
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.blue),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  Build
  // ══════════════════════════════════════════════════════════════

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
            // ── Выбор метода НК ─────────────────────────────────
            FormBuilderDropdown<String>(
              name: 'method_code',
              decoration: _inputDeco('Метод неразрушающего контроля *'),
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
                  _clearMethodSpecificData();
                  _selectedMethodCode = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // ── Общие поля ──────────────────────────────────────
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
              decoration: _inputDeco('Нормативный документ (ГОСТ, РД)'),
              initialValue: widget.existingMethod?.standard,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'equipment',
              decoration: _inputDeco('Используемое оборудование'),
              initialValue: widget.existingMethod?.equipment,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'inspector_name',
              decoration: _inputDeco('ФИО инженера'),
              initialValue: widget.existingMethod?.inspectorName,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderDropdown<String>(
              name: 'inspector_level',
              decoration: _inputDeco('Уровень инженера'),
              items: ['I', 'II', 'III']
                  .map((level) => DropdownMenuItem(
                        value: level,
                        child: Text(level, style: const TextStyle(color: Colors.white)),
                      ))
                  .toList(),
              initialValue: widget.existingMethod?.inspectorLevel,
            ),
            const SizedBox(height: 16),
            FormBuilderDateTimePicker(
              name: 'performed_date',
              decoration: _inputDeco('Дата проведения'),
              initialValue: widget.existingMethod?.performedDate,
              inputType: InputType.date,
              format: DateFormat('yyyy-MM-dd'),
            ),
            const SizedBox(height: 16),

            // ── Специфичные поля метода ─────────────────────────
            _buildMethodSpecificFields(),
            const SizedBox(height: 16),

            // ── Общие результаты ────────────────────────────────
            FormBuilderTextField(
              name: 'results',
              decoration: _inputDeco('Результаты контроля'),
              initialValue: widget.existingMethod?.results,
              maxLines: 5,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'defects',
              decoration: _inputDeco('Обнаруженные дефекты'),
              initialValue: widget.existingMethod?.defects,
              maxLines: 5,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'conclusion',
              decoration: _inputDeco('Заключение'),
              initialValue: widget.existingMethod?.conclusion,
              maxLines: 5,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),

            // ── Аннотации и фото ────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await context.push<File>(
                        '/image-annotation',
                        extra: {
                          'title': 'Аннотирование для ${_selectedMethodCode ?? "метода НК"}',
                        },
                      );
                      if (result != null) {
                        setState(() => _annotatedImagePaths.add(result.path));
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
                        final result = await context.push<File>(
                          '/weld-defect-annotation',
                        );
                        if (result != null) {
                          setState(() => _annotatedImagePaths.add(result.path));
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
                            setState(() => _annotatedImagePaths.removeAt(entry.key));
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // ── Кнопка сохранения ───────────────────────────────
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
