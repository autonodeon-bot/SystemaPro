import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/vessel_checklist.dart';
import '../services/vessel_pressure_calculation.dart';

class VesselPressureCalculationScreen extends StatefulWidget {
  final VesselChecklist checklist;
  final VoidCallback onChanged;
  const VesselPressureCalculationScreen(
      {super.key, required this.checklist, required this.onChanged});
  @override
  State<VesselPressureCalculationScreen> createState() =>
      _VesselPressureCalculationScreenState();
}

class _VesselPressureCalculationScreenState
    extends State<VesselPressureCalculationScreen> {
  final _fields = <String, TextEditingController>{};
  String _element = 'cylinder', _group = '', _load = 'internal_pressure';
  String? _caseId, _error, _notice;
  bool _loading = true;
  VesselPressureResult? _result;
  List<Map<String, dynamic>> get _cases {
    final raw = widget.checklist.additionalData?['strength_calculations'];
    return raw is List
        ? raw.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
        : [];
  }

  @override
  void initState() {
    super.initState();
    final checklist = widget.checklist;
    final draft = checklist.additionalData?['strength_calculation_draft'];
    final defaults = <String, dynamic>{
      'name': 'Обечайка',
      'pressure_mpa': checklist.designPressure,
      'diameter_mm': checklist.diameter,
      'nominal_mm': checklist.thicknessDefaults.nominalThickness,
      'temperature_c': checklist.designTemperature,
      'c1_mm': checklist.corrosionAllowance,
      'material': checklist.vesselElements.isNotEmpty
          ? checklist.vesselElements.first.material
          : ''
    };
    final saved = draft is Map ? draft['fields'] : null;
    for (final key in [
      'name',
      'pressure_mpa',
      'diameter_mm',
      'nominal_mm',
      'temperature_c',
      'material',
      'weld_factor',
      'c1_mm',
      'c2_mm',
      'c3_mm',
      'head_height_mm',
      'flange_length_mm',
      'manual_stress_mpa',
      'yield_at_20_mpa',
      'stress_basis'
    ]) {
      _fields[key] = TextEditingController(
          text: ((saved is Map ? saved[key] : null) ?? defaults[key] ?? '')
              .toString());
    }
    if (draft is Map) {
      _element = (draft['element'] ?? _element).toString();
      _group = (draft['material_group'] ?? '').toString();
      _load = (draft['load_case'] ?? _load).toString();
      _caseId = draft['case_id']?.toString();
    } else if (_cases.isNotEmpty) {
      _loadCase(_cases.last);
    }
    _loading = false;
  }

  void _changed() {
    if (_loading) return;
    widget.checklist.additionalData ??= {};
    widget.checklist.additionalData!['strength_calculation_draft'] = {
      'case_id': _caseId,
      'element': _element,
      'material_group': _group,
      'load_case': _load,
      'fields': _fields.map((key, c) => MapEntry(key, c.text))
    };
    widget.onChanged();
    setState(() => _result = null);
  }

  void _loadCase(Map<String, dynamic> row) {
    _loading = true;
    final inputs = Map<String, dynamic>.from(row['inputs'] as Map);
    _caseId = row['id']?.toString();
    _element = inputs['element'];
    _group = inputs['material_group'];
    _load = inputs['load_case'] ?? 'internal_pressure';
    for (final key in _fields.keys) {
      _fields[key]!.text =
          (key == 'name' ? row['name'] : inputs[key])?.toString() ?? '';
    }
    _loading = false;
  }

  double _number(String key, String label) {
    final value =
        double.tryParse(_fields[key]!.text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite)
      throw FormatException('Укажите $label');
    return value;
  }

  double? _optional(String key) =>
      _fields[key]!.text.trim().isEmpty ? null : _number(key, key);
  VesselPressureInput _input() => VesselPressureInput(
      element: _element,
      materialGroup: _group,
      loadCase: _load,
      material: _fields['material']!.text,
      stressBasis: _fields['stress_basis']!.text,
      pressure: _number('pressure_mpa', 'расчётное давление'),
      diameter: _number('diameter_mm', 'внутренний диаметр'),
      nominal: _number('nominal_mm', 'номинальную толщину'),
      temperature: _number('temperature_c', 'расчётную температуру'),
      weldFactor: _number('weld_factor', 'коэффициент прочности шва φ'),
      corrosionAllowance: _number('c1_mm', 'прибавку c1, в том числе 0'),
      toleranceAllowance: _number('c2_mm', 'прибавку c2, в том числе 0'),
      technologyAllowance: _number('c3_mm', 'прибавку c3, в том числе 0'),
      headHeight: _element == 'elliptical' ? _optional('head_height_mm') : null,
      flangeLength:
          _element == 'cylinder' ? null : _optional('flange_length_mm'),
      manualStress: _group == 'manual' ? _optional('manual_stress_mpa') : null,
      yieldAt20: _group == 'steel20' ? _optional('yield_at_20_mpa') : null);

  void _calculate() {
    try {
      final result = VesselPressureCalculation.calculate(_input());
      setState(() {
        _result = result;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _result = null;
        _error = e.message.toString();
      });
    }
  }

  void _applyCases(List<Map<String, dynamic>> cases) {
    final checklist = widget.checklist;
    checklist.additionalData ??= {};
    checklist.additionalData!['strength_calculations'] = cases;
    if (cases.isEmpty) {
      final previous =
          checklist.additionalData!['thickness_defaults_before_calc'];
      checklist.setThicknessDefaults(previous is Map
          ? ThicknessDefaults.fromJson(Map<String, dynamic>.from(previous))
          : ThicknessDefaults(
              nominalThickness: checklist.thicknessDefaults.nominalThickness));
      _notice = 'Расчёты удалены; восстановлены исходные общие толщины';
    } else {
      final inputs = cases
          .map((c) => VesselPressureInput.fromJson(
              Map<String, dynamic>.from(c['inputs'])))
          .toList();
      final consistent = inputs.every((p) =>
          p.pressure == inputs.first.pressure &&
          p.temperature == inputs.first.temperature &&
          p.nominal == inputs.first.nominal);
      if (!checklist.additionalData!
          .containsKey('thickness_defaults_before_calc'))
        checklist.additionalData!['thickness_defaults_before_calc'] =
            checklist.thicknessDefaults.toJson();
      if (!consistent) {
        checklist.setThicknessDefaults(ThicknessDefaults(
            nominalThickness: checklist.thicknessDefaults.nominalThickness,
            basis:
                'Разные расчётные условия элементов: общий порог не применяется'));
        _notice =
            'У элементов отличаются давление, температура или номинальная толщина. Общий порог отключён: согласуйте условия или задайте индивидуальные нормативы элементов.';
      } else {
        final minimum = inputs
            .map(VesselPressureCalculation.calculate)
            .map((r) => r.minimumThickness)
            .reduce(math.max);
        checklist.setThicknessDefaults(ThicknessDefaults(
            nominalThickness: inputs.first.nominal,
            minAllowedThickness: minimum,
            basis:
                'ГОСТ 34233.2-2017, внутреннее давление; максимум ${cases.length} расчётных случаев'));
        _notice =
            'Общий порог ${minimum.toStringAsFixed(2)} мм применён ко всем точкам с общими нормативами';
      }
      checklist.additionalData!['strength_calculations_consistent'] =
          consistent;
    }
    checklist.calculationData ??= {};
    checklist.calculationData!['method'] =
        'ГОСТ 34233.2-2017: внутреннее избыточное давление';
    checklist.calculationData!['strength_calculations'] = cases;
    checklist.calculationData!['min_thickness'] =
        checklist.thicknessDefaults.minAllowedThickness;
    widget.onChanged();
  }

  void _save() {
    try {
      final p = _input(),
          result = VesselPressureCalculation.calculate(_input());
      final name = _fields['name']!.text.trim();
      if (name.isEmpty) throw const FormatException('Назовите элемент сосуда');
      _caseId ??= const Uuid().v4();
      final cases = _cases.where((row) => row['id'] != _caseId).toList();
      cases.add({
        'id': _caseId,
        'name': name,
        'inputs': p.toJson(),
        'result': result.toJson(),
        'calculated_at': DateTime.now().toUtc().toIso8601String(),
        'schema_version': 1
      });
      _applyCases(cases);
      _changed();
      setState(() {
        _result = result;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message.toString());
    }
  }

  Widget _field(String key, String label,
          {String? helper, bool text = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
              key: ValueKey('pressure-$key'),
              controller: _fields[key],
              decoration: InputDecoration(
                  labelText: label,
                  helperText: helper,
                  helperMaxLines: 3,
                  border: const OutlineInputBorder()),
              keyboardType: text
                  ? TextInputType.text
                  : const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
              onChanged: (_) => _changed()));
  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Расчёт толщины по ГОСТ')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              'ГОСТ 34233.2-2017: обечайка и эллиптическое / полусферическое днище под внутренним давлением. Расчёт элемента не заменяет проверки отверстий, опор, вакуума и совместных нагрузок.'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
              key: ValueKey('load-$_load'),
              isExpanded: true,
              initialValue: _load,
              decoration: const InputDecoration(
                  labelText: 'Расчётное нагружение',
                  border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                    value: 'internal_pressure',
                    child: Text('Внутреннее избыточное давление')),
                DropdownMenuItem(
                    value: 'external_pressure',
                    child: Text('Вакуум / наружное давление')),
                DropdownMenuItem(
                    value: 'combined',
                    child: Text('Совместное действие нагрузок'))
              ],
              onChanged: (v) {
                setState(() => _load = v!);
                _changed();
              }),
          const SizedBox(height: 14),
          _field('name', 'Наименование элемента', text: true),
          DropdownButtonFormField<String>(
              key: ValueKey('element-$_element'),
              isExpanded: true,
              initialValue: _element,
              decoration: const InputDecoration(
                  labelText: 'Геометрия элемента',
                  border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                    value: 'cylinder', child: Text('Цилиндрическая обечайка')),
                DropdownMenuItem(
                    value: 'elliptical', child: Text('Эллиптическое днище')),
                DropdownMenuItem(
                    value: 'hemispherical',
                    child: Text('Полусферическое днище'))
              ],
              onChanged: (v) {
                setState(() => _element = v!);
                _changed();
              }),
          const SizedBox(height: 14),
          _field('pressure_mpa', 'Расчётное давление p, МПа',
              helper:
                  'Давление в элементе, включая гидростатическое; не подменяется рабочим давлением'),
          _field('diameter_mm', 'Внутренний диаметр D, мм'),
          _field('nominal_mm', 'Номинальная толщина s, мм'),
          _field('temperature_c', 'Расчётная температура стенки, °C'),
          _field('material', 'Марка материала по паспорту', text: true),
          DropdownButtonFormField<String>(
              key: ValueKey('material-$_group'),
              initialValue: _group.isEmpty ? null : _group,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Группа допускаемых напряжений',
                  border: OutlineInputBorder()),
              items: VesselPressureCalculation.materialGroups.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value,
                          maxLines: 2, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) {
                setState(() => _group = v!);
                _changed();
              }),
          const SizedBox(height: 14),
          if (_group == 'manual') ...[
            _field('manual_stress_mpa',
                'Допускаемое [σ] при этой температуре, МПа'),
            _field('stress_basis', 'Норматив / таблица / источник [σ]',
                text: true)
          ],
          if (_group == 'steel20')
            _field(
                'yield_at_20_mpa', 'Паспортный предел текучести при 20 °C, МПа',
                helper: 'Поправка по примечанию 3 таблицы А.1'),
          if (_group.isNotEmpty && _group != 'manual')
            const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Text(
                    '[σ] определяется по ГОСТ 34233.1-2017, табл. А.1 для 20–350 °C с интерполяцией и округлением вниз до 0,5 МПа. Проверьте вид продукции и класс прочности.')),
          _field('weld_factor', 'Коэффициент прочности сварного шва φ',
              helper:
                  'По паспорту и объёму НК; для днища из одной заготовки φ=1 (п.6.3.1.5)'),
          _field('c1_mm', 'c₁ — коррозия / эрозия, мм',
              helper:
                  'Применимая прибавка для данного расчётного случая; 0 вводится явно'),
          _field('c2_mm', 'c₂ — минусовой допуск, мм'),
          _field('c3_mm', 'c₃ — технологическая прибавка, мм'),
          if (_element == 'elliptical') ...[
            _field('head_height_mm', 'Высота выпуклой части H, мм'),
            TextButton(
                onPressed: () {
                  final d = double.tryParse(
                      _fields['diameter_mm']!.text.replaceAll(',', '.'));
                  if (d != null) {
                    _fields['head_height_mm']!.text = (d / 4).toString();
                    _changed();
                  }
                },
                child: const Text('Подставить H=D/4 для днища 2:1'))
          ],
          if (_element != 'cylinder')
            _field('flange_length_mm', 'Длина цилиндрической отбортовки h₁, мм',
                helper:
                    'Без отбортовки укажите 0; п.6.3.1.4 проверяется автоматически'),
          FilledButton.icon(
              key: const ValueKey('calculate-pressure'),
              onPressed: _calculate,
              icon: const Icon(Icons.calculate),
              label: const Text('Рассчитать')),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent))),
          if (_result != null)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('[σ] = ${_result!.allowableStress} МПа'),
                          Text(
                              'Расчётная sp = ${_result!.calculatedThickness.toStringAsFixed(3)} мм'),
                          Text(
                              'Минимальная с заданными прибавками: ${_result!.minimumThickness.toStringAsFixed(2)} мм',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(_result!.clause),
                          Text(_result!.formula),
                          if (_result!.flangeControls)
                            const Text(
                                'Определяющей является цилиндрическая отбортовка'),
                          if (!_result!.nominalSufficient)
                            const Text(
                                'Номинальная толщина меньше требуемой для этого расчётного случая',
                                style: TextStyle(color: Colors.redAccent)),
                          const Text(
                              'Порог округлён вверх до 0,01 мм. Это проверка выбранного расчётного случая, не итоговое разрешение эксплуатации.'),
                          const SizedBox(height: 12),
                          FilledButton(
                              key: const ValueKey('save-pressure'),
                              onPressed: _save,
                              child: const Text(
                                  'Сохранить расчёт и применить порог')),
                        ]))),
          if (_notice != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_notice!)),
          if (_cases.isNotEmpty) ...[
            const Divider(),
            const Text('Сохранённые расчёты элементов',
                style: TextStyle(fontSize: 18)),
            for (final row in _cases)
              ListTile(
                  title: Text(row['name']?.toString() ?? ''),
                  subtitle: Text(
                      'Порог: ${row['result']?['minimum_thickness_mm']} мм · ${row['inputs']?['pressure_mpa']} МПа · ${row['inputs']?['temperature_c']} °C'),
                  onTap: () {
                    setState(() => _loadCase(row));
                    _changed();
                  },
                  trailing: IconButton(
                      tooltip: 'Удалить расчёт',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        setState(() => _applyCases(_cases
                            .where((c) => c['id'] != row['id'])
                            .toList()));
                        widget.onChanged();
                      })),
          ],
          OutlinedButton(
              onPressed: () {
                setState(() {
                  _caseId = null;
                  _fields['name']!.text = '';
                  _result = null;
                  _error = null;
                });
                _changed();
              },
              child: const Text('Добавить расчёт другого элемента')),
          const SizedBox(height: 24),
        ]),
      );
}
