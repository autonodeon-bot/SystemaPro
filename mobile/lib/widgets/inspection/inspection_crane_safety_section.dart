import 'package:flutter/material.dart';
import '../../models/vessel_checklist.dart';
import 'inspection_form_fields.dart';

/// Акт ПС + чек-листы безопасности (прил. 2 и 6 формы to-3).
class InspectionCraneSafetySection extends StatefulWidget {
  final VesselChecklist checklist;
  final VoidCallback onStateChanged;

  const InspectionCraneSafetySection({
    super.key,
    required this.checklist,
    required this.onStateChanged,
  });

  @override
  State<InspectionCraneSafetySection> createState() =>
      _InspectionCraneSafetySectionState();
}

class _InspectionCraneSafetySectionState
    extends State<InspectionCraneSafetySection> {
  static const _safetyNodes = [
    '1.1 Зона соединения со стрелой',
    '1.2 Зона соединения с противовесом',
    '1.3 Противовес',
    '2.1 Секция стрелы',
    '2.2 Зона установки канатных блоков',
    '1.1 Тормозная обкладка',
    '1.2 Крепление тормоза',
    '2.1 Уровень масла',
    '2.2 Крепление редуктора',
    '4.1 Износ ручья барабана',
    '4.4 Крепление каната',
    '5.1 Износ крюка',
    '5.5 Состояние предохранительного замка',
    '7.1 Состояние смазки каната',
    '7.2 Состояние каната',
  ];

  static const _safetyDevices = [
    'Блокировка рычагов управления лебедкой и противовесом',
    'Сигнализатор предельного подъема крюка',
    'Устройство для автоматической остановки стрелы в крайнем положении',
    'Сигнализатор предельного грузового момента',
    'Указатель предельной грузоподъемности',
  ];

  Map<String, dynamic> get _ad {
    widget.checklist.additionalData ??= {};
    return widget.checklist.additionalData!;
  }

  Map<String, dynamic> get _act {
    final raw = _ad['crane_act'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    final m = <String, dynamic>{};
    _ad['crane_act'] = m;
    return m;
  }

  Map<String, dynamic> get _checks {
    final raw = _ad['crane_safety_checks'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    final m = <String, dynamic>{};
    _ad['crane_safety_checks'] = m;
    return m;
  }

  Map<String, dynamic> get _devices {
    final raw = _ad['crane_safety_devices'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    final m = <String, dynamic>{};
    _ad['crane_safety_devices'] = m;
    return m;
  }

  void _setAct(String k, String? v) {
    _act[k] = v;
    _ad['crane_act'] = _act;
    widget.onStateChanged();
  }

  void _setCheck(String k, String? v) {
    _checks[k] = v;
    _ad['crane_safety_checks'] = _checks;
    widget.onStateChanged();
    setState(() {});
  }

  void _setDevice(String k, String? v) {
    _devices[k] = v;
    _ad['crane_safety_devices'] = _devices;
    widget.onStateChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionHeader('Акт обследования ПС (прил. 2)'),
        buildInspectionTextField(
          'crane_overall_state',
          'Общее состояние крана',
          (v) {
            _setAct('overall_state', v);
            widget.checklist.technicalState = v;
          },
          initialValue: _act['overall_state']?.toString() ??
              widget.checklist.technicalState,
        ),
        buildInspectionTextField(
          'crane_residual_score',
          'Оценка остаточного ресурса (баллы)',
          (v) => _setAct('residual_score', v),
          initialValue: _act['residual_score']?.toString(),
        ),
        buildInspectionTextField(
          'crane_allowed_until',
          'Допуск к эксплуатации до',
          (v) => _setAct('allowed_until', v),
          initialValue: _act['allowed_until']?.toString(),
        ),
        buildInspectionTextField(
          'crane_repair_required',
          'Требуемый ремонт / ограничения',
          (v) => _setAct('repair_required', v),
          initialValue: _act['repair_required']?.toString(),
        ),
        buildInspectionTextField(
          'crane_recommendations',
          'Рекомендации',
          (v) => _setAct('recommendations', v),
          initialValue: _act['recommendations']?.toString(),
        ),
        buildInspectionTextField(
          'crane_classification_limit',
          'Достижение предела группы классификации',
          (v) => _setAct('classification_limit', v),
          initialValue: _act['classification_limit']?.toString(),
        ),
        const SizedBox(height: 16),
        buildSectionHeader('Проверка узлов и механизмов (прил. 6)'),
        const Text(
          'Для каждого узла укажите результат контроля (соответствует / не соответствует / описание дефекта).',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ..._safetyNodes.map((node) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: buildInspectionTextField(
              'crane_check_${node.hashCode}',
              node,
              (v) => _setCheck(node, v),
              initialValue: _checks[node]?.toString() ?? 'соответствует',
            ),
          );
        }),
        const SizedBox(height: 16),
        buildSectionHeader('Устройства безопасности'),
        ..._safetyDevices.map((dev) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: buildInspectionTextField(
              'crane_dev_${dev.hashCode}',
              '$dev (наличие / состояние)',
              (v) => _setDevice(dev, v),
              initialValue: _devices[dev]?.toString() ?? 'имеется / исправно',
            ),
          );
        }),
        const SizedBox(height: 12),
        buildInspectionTextField(
          'static_dynamic_test_act',
          'Путь к акту статических/динамических испытаний',
          (v) {
            _ad['static_dynamic_test_act'] = v;
            widget.onStateChanged();
          },
          initialValue: _ad['static_dynamic_test_act']?.toString(),
        ),
        buildInspectionTextField(
          'work_character_certificate',
          'Путь к справке о характере работы ПС',
          (v) {
            _ad['work_character_certificate'] = v;
            widget.onStateChanged();
          },
          initialValue: _ad['work_character_certificate']?.toString(),
        ),
      ],
    );
  }
}
