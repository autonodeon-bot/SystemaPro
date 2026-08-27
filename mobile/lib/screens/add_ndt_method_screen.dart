import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../models/questionnaire.dart';

/// Стандартные формулировки заключения по видам НК — техник выбирает из
/// выпадающего списка вместо ввода произвольного текста; при необходимости
/// текст можно отредактировать вручную после выбора.
/// TODO: формулировки предварительные — уточнить у экспертов ЮТАР.
const Map<String, List<String>> NDT_STANDARD_CONCLUSIONS = {
  'ВИК': [
    'По результатам визуального и измерительного контроля недопустимых дефектов не обнаружено, объект контроля соответствует требованиям нормативно-технической документации.',
    'По результатам визуального и измерительного контроля выявлены дефекты, требующие устранения до дальнейшей эксплуатации.',
  ],
  'УЗК': [
    'По результатам ультразвукового контроля сварных соединений недопустимых дефектов не обнаружено, объект контроля соответствует требованиям НТД.',
    'По результатам ультразвукового контроля выявлены недопустимые дефекты, требуется дополнительная оценка/ремонт.',
  ],
  'УЗК_СС': [
    'По результатам ультразвукового контроля сварных соединений недопустимых дефектов не обнаружено, объект контроля соответствует требованиям НТД.',
    'По результатам ультразвукового контроля выявлены недопустимые дефекты, требуется дополнительная оценка/ремонт.',
  ],
  'МПД': [
    'По результатам магнитопорошкового контроля дефектов не обнаружено, объект контроля соответствует требованиям НТД.',
    'По результатам магнитопорошкового контроля выявлены поверхностные дефекты, требуется дополнительная оценка.',
  ],
  'МК': [
    'По результатам магнитного контроля дефектов не обнаружено, объект контроля соответствует требованиям НТД.',
    'По результатам магнитного контроля выявлены поверхностные дефекты, требуется дополнительная оценка.',
  ],
  'ТВЕРД': [
    'Измеренные значения твёрдости металла находятся в допустимых пределах и соответствуют прочностным характеристикам используемой марки стали.',
    'Измеренные значения твёрдости металла выходят за допустимые пределы, требуется дополнительный контроль.',
  ],
  'УЗТ': [
    'Измеренная толщина стенок элементов не превышает минимально допустимые значения и удовлетворяет требованиям НТД.',
    'Измеренная толщина стенок в отдельных точках ниже минимально допустимой — требуется дополнительная оценка/расчёт остаточного ресурса.',
  ],
  'КПД': [
    'По результатам капиллярной дефектоскопии дефектов не обнаружено, объект контроля соответствует требованиям НТД.',
    'По результатам капиллярной дефектоскопии выявлены поверхностные дефекты, требуется дополнительная оценка.',
  ],
};

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
  final _syncService = SyncService();
  bool _isSubmitting = false;
  String? _selectedMethodCode;
  final List<String> _annotatedImagePaths = [];

  // Динамические списки для метод-специфичных данных
  final List<Map<String, TextEditingController>> _measurementPoints = [];
  final List<Map<String, TextEditingController>> _defectsList = [];
  final List<Map<String, TextEditingController>> _indicationsList = [];
  final List<Map<String, TextEditingController>> _uzkResults = [];
  final List<Map<String, TextEditingController>> _hardnessPoints = [];

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
    for (final list in [_measurementPoints, _defectsList, _indicationsList, _uzkResults, _hardnessPoints]) {
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
            'joint': TextEditingController(text: r['joint']?.toString() ?? r['zone']?.toString() ?? ''),
            'defect_number': TextEditingController(text: r['defect_number']?.toString() ?? ''),
            'equivalent_size': TextEditingController(text: r['equivalent_size']?.toString() ?? r['equivalent_area']?.toString() ?? ''),
            'depth': TextEditingController(text: r['depth']?.toString() ?? ''),
            'length': TextEditingController(text: r['length']?.toString() ?? ''),
            'form': TextEditingController(text: r['form']?.toString() ?? r['character']?.toString() ?? ''),
            'coordinate': TextEditingController(text: r['coordinate']?.toString() ?? ''),
          });
        }
      }
    }

    final hardness = ad['hardness_tests'] as List?;
    if (hardness != null) {
      for (final h in hardness) {
        if (h is Map) {
          _hardnessPoints.add({
            'element': TextEditingController(text: h['element']?.toString() ?? h['element_name']?.toString() ?? h['location']?.toString() ?? ''),
            'point_number': TextEditingController(text: h['point_number']?.toString() ?? ''),
            'steel_grade': TextEditingController(text: h['steel_grade']?.toString() ?? h['material']?.toString() ?? ''),
            'hardness_base': TextEditingController(text: h['hardness_base']?.toString() ?? ''),
            'hardness_weld': TextEditingController(text: h['hardness_weld']?.toString() ?? ''),
            'allowed_hardness_base': TextEditingController(text: h['allowed_hardness_base']?.toString() ?? ''),
          });
        }
      }
    }
  }

  void _clearMethodSpecificData() {
    for (final list in [_measurementPoints, _defectsList, _indicationsList, _uzkResults, _hardnessPoints]) {
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
        ad['roughness'] = formData['method_roughness'];
        ad['additional_lighting'] = formData['method_additional_lighting'] == true;
        ad['surface_temp'] = formData['method_surface_temp'];
        ad['defects_list'] = _defectsList
            .map<Map<String, String>>((d) => {
                    'element': d['element']?.text ?? '',
                    'description': d['description']?.text ?? '',
                    'size': d['size']?.text ?? '',
                    'classification': d['classification']?.text ?? '',
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
        ad['joint_type'] = formData['method_joint_type'];
        ad['element_thickness'] = formData['method_element_thickness'];
        ad['max_equivalent_area'] = formData['method_max_equiv_area'];
        ad['notch_params'] = formData['method_notch_params'];
        ad['results_list'] = _uzkResults
            .map<Map<String, String>>((r) => {
                    'joint': r['joint']?.text ?? '',
                    'zone': r['joint']?.text ?? '',
                    'defect_number': r['defect_number']?.text ?? '',
                    'coordinate': r['coordinate']?.text ?? '',
                    'equivalent_size': r['equivalent_size']?.text ?? '',
                    'equivalent_area': r['equivalent_size']?.text ?? '',
                    'depth': r['depth']?.text ?? '',
                    'length': r['length']?.text ?? '',
                    'form': r['form']?.text ?? '',
                    'character': r['form']?.text ?? '',
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
            .map<Map<String, String>>((p) => {
                    'location': p['location']?.text ?? '',
                    'thickness': p['thickness']?.text ?? '',
                  })
            .where((m) => m.values.any((v) => v.isNotEmpty))
            .toList();
        break;

      case 'МПД':
      case 'МК':
        ad['magnetization_type'] = formData['method_magnetization_type'];
        ad['field_strength'] = formData['method_field_strength'];
        ad['indicator_suspension'] = formData['method_indicator_suspension'];
        ad['sensitivity'] = formData['method_sensitivity'];
        ad['control_method'] = formData['method_mpk_control_method'];
        ad['indications_list'] = _indicationsList
            .map<Map<String, String>>((ind) => {
                    'zone': ind['zone']?.text ?? '',
                    'indication': ind['indication']?.text ?? '',
                    'size': ind['size']?.text ?? '',
                    'assessment': ind['assessment']?.text ?? '',
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
            .map<Map<String, String>>((ind) => {
                    'zone': ind['zone']?.text ?? '',
                    'indication': ind['indication']?.text ?? '',
                    'size': ind['size']?.text ?? '',
                    'assessment': ind['assessment']?.text ?? '',
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

      case 'ТВЕРД':
        ad['device_type'] = formData['method_device_type'];
        ad['test_method'] = formData['method_hardness_test_method'];
        ad['hardness_tests'] = _hardnessPoints
            .map<Map<String, String>>((p) => {
                    'element': p['element']?.text ?? '',
                    'element_name': p['element']?.text ?? '',
                    'location': p['element']?.text ?? '',
                    'point_number': p['point_number']?.text ?? '',
                    'steel_grade': p['steel_grade']?.text ?? '',
                    'material': p['steel_grade']?.text ?? '',
                    'hardness_base': p['hardness_base']?.text ?? '',
                    'hardness_weld': p['hardness_weld']?.text ?? '',
                    'allowed_hardness_base': p['allowed_hardness_base']?.text ?? '',
                  })
            .where((m) => m.values.any((v) => v.isNotEmpty))
            .toList();
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

        final useOfflineQueue = _syncService.isPendingQuestionnaireLocalId(
              widget.questionnaireId,
            ) ||
            !await _apiService.checkConnection();

        if (useOfflineQueue) {
          await _syncService.queueNdtMethodOffline(
            questionnaireId: widget.questionnaireId,
            methodData: methodData,
            localPhotoPaths: List<String>.from(_annotatedImagePaths),
            photosAnnotated: true,
          );
          if (mounted) {
            context.pop(true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Метод НК сохранён локально. Фото отправятся при синхронизации.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        }

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
        final msg = e.toString();
        final isNetwork = msg.contains('SocketException') ||
            msg.contains('Failed host lookup') ||
            msg.contains('Нет связи') ||
            msg.contains('Connection');
        if (isNetwork) {
          try {
            final formData = _formKey.currentState!.value;
            final methodData = {
              'method_code': _selectedMethodCode ?? formData['method_code'],
              'method_name': NDT_METHODS.firstWhere(
                (m) =>
                    m['code'] ==
                    (_selectedMethodCode ?? formData['method_code']),
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
                  ? (formData['performed_date'] as DateTime)
                      .toIso8601String()
                  : null,
              'photos': <dynamic>[],
              'additional_data': _collectMethodSpecificData(),
            };
            await _syncService.queueNdtMethodOffline(
              questionnaireId: widget.questionnaireId,
              methodData: methodData,
              localPhotoPaths: List<String>.from(_annotatedImagePaths),
              photosAnnotated: true,
            );
            if (mounted) {
              context.pop(true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Ошибка сети: метод НК и фото в очереди синхронизации.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 5),
                ),
              );
            }
            return;
          } catch (_) {}
        }
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
      case 'ТВЕРД':
        return _buildTVERDFields();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Стандартные формулировки заключения ─────────────────────
  Widget _buildConclusionPresetDropdown() {
    final code = (_selectedMethodCode ?? '').toUpperCase();
    final presets = NDT_STANDARD_CONCLUSIONS[code] ?? const [];
    if (presets.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      decoration: _inputDeco('Стандартная формулировка заключения'),
      dropdownColor: const Color(0xFF1e293b),
      items: [
        ...presets.map(
          (t) => DropdownMenuItem(
            value: t,
            child: Text(
              t,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
        const DropdownMenuItem(
          value: '__custom__',
          child: Text('Другое (ввести вручную)', style: TextStyle(color: Colors.white70)),
        ),
      ],
      onChanged: (value) {
        if (value == null || value == '__custom__') return;
        _formKey.currentState?.fields['conclusion']?.didChange(value);
      },
    );
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
          name: 'method_roughness',
          decoration: _inputDeco('Шероховатость поверхности', hint: 'Rz 80'),
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
        FormBuilderSwitch(
          name: 'method_additional_lighting',
          title: const Text(
            'Использовалось дополнительное освещение',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          initialValue: false,
          activeColor: Colors.blue,
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
        FormBuilderTextField(
          name: 'method_joint_type',
          decoration: _inputDeco('Тип соединения'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_element_thickness',
          decoration: _inputDeco('Толщина элементов, мм'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_max_equiv_area',
          decoration: _inputDeco('Макс. допустимая эквивалентная площадь, мм²'),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_notch_params',
          decoration: _inputDeco('Параметры зарубки, мм'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        _buildUzkResultsList(),
      ],
    );
  }

  Widget _buildUzkResultsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Результаты УЗК',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.blue),
              onPressed: () {
                setState(() {
                  _uzkResults.add({
                    'joint': TextEditingController(),
                    'defect_number': TextEditingController(),
                    'equivalent_size': TextEditingController(),
                    'depth': TextEditingController(),
                    'length': TextEditingController(),
                    'form': TextEditingController(text: 'объёмный'),
                    'coordinate': TextEditingController(),
                  });
                });
              },
            ),
          ],
        ),
        if (_uzkResults.isEmpty)
          const Text('Нет записей. Нажмите + для добавления.',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ..._uzkResults.asMap().entries.map((entry) {
          final idx = entry.key;
          final c = entry.value;
          final formVal = c['form']!.text;
          return Card(
            color: const Color(0xFF1e293b),
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Дефект ${idx + 1}',
                            style: const TextStyle(color: Colors.white70)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                        onPressed: () {
                          setState(() {
                            for (final ctrl in c.values) {
                              ctrl.dispose();
                            }
                            _uzkResults.removeAt(idx);
                          });
                        },
                      ),
                    ],
                  ),
                  TextField(
                    controller: c['joint'],
                    decoration: _inputDeco('Номер стыка'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: c['defect_number'],
                    decoration: _inputDeco('Условный номер дефекта'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: c['length'],
                    decoration: _inputDeco('Протяжённость, мм'),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: c['depth'],
                    decoration: _inputDeco('Глубина залегания, мм'),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: c['equivalent_size'],
                    decoration: _inputDeco('Эквивалентная площадь, мм²'),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: (formVal == 'объёмный' ||
                            formVal == 'объемный' ||
                            formVal == 'плоскостной')
                        ? (formVal == 'объемный' ? 'объёмный' : formVal)
                        : 'объёмный',
                    decoration: _inputDeco('Характер дефекта'),
                    dropdownColor: const Color(0xFF0f172a),
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'объёмный', child: Text('Объёмный')),
                      DropdownMenuItem(value: 'плоскостной', child: Text('Плоскостной')),
                    ],
                    onChanged: (v) {
                      c['form']!.text = v ?? 'объёмный';
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          );
        }),
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
          decoration: _inputDeco('Тип намагничивания / способ контроля'),
          items: const [
            DropdownMenuItem(value: 'Циркулярное', child: Text('Циркулярное', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'Продольное', child: Text('Продольное', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'Комбинированное', child: Text('Комбинированное', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'Приложенным полем', child: Text('Приложенным полем', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'Остаточной намагниченностью', child: Text('Остаточной намагниченностью', style: TextStyle(color: Colors.white))),
          ],
        ),
        const SizedBox(height: 12),
        FormBuilderTextField(
          name: 'method_sensitivity',
          decoration: _inputDeco('Уровень чувствительности'),
          style: const TextStyle(color: Colors.white),
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

  // ── Твердометрия (ТВЕРД) ────────────────────────────────────

  Widget _buildTVERDFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Параметры контроля твёрдости'),
        FormBuilderTextField(
          name: 'method_device_type',
          decoration: _inputDeco('Тип твердомера'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 12),
        FormBuilderDropdown<String>(
          name: 'method_hardness_test_method',
          decoration: _inputDeco('Метод измерения'),
          items: const [
            DropdownMenuItem(value: 'Динамический (Либа)', child: Text('Динамический (Либа)', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'Статический (Бринелль)', child: Text('Статический (Бринелль)', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 'Статический (Роквелл)', child: Text('Статический (Роквелл)', style: TextStyle(color: Colors.white))),
          ],
        ),
        const SizedBox(height: 12),
        _buildDynamicList(
          title: 'Точки замера твёрдости',
          items: _hardnessPoints,
          fieldLabels: const [
            'Элемент сосуда',
            '№ точки',
            'Марка стали',
            'Твёрдость осн. металла, HB',
            'Твёрдость шва, HB',
            'Допустимая твёрдость, HB',
          ],
          fieldKeys: const [
            'element',
            'point_number',
            'steel_grade',
            'hardness_base',
            'hardness_weld',
            'allowed_hardness_base',
          ],
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
            _buildConclusionPresetDropdown(),
            const SizedBox(height: 8),
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
