import 'package:flutter/material.dart';

import '../../data/technical_report_form_registry.dart';

import '../../models/vessel_checklist.dart';
import 'inspection_form_fields.dart';

/// Паспортные данные для приложения Б (таблицы Б1–Б6) и поля ЭПБ.
class InspectionPassportSection extends StatelessWidget {
  final VesselChecklist checklist;
  final VoidCallback onStateChanged;
  final Future<void> Function()? onPickConnectionSchemeFile;
  final VoidCallback? onClearConnectionSchemeFile;

  const InspectionPassportSection({
    super.key,
    required this.checklist,
    required this.onStateChanged,
    this.onPickConnectionSchemeFile,
    this.onClearConnectionSchemeFile,
  });

  @override
  Widget build(BuildContext context) {
    final form = TechnicalReportFormRegistry.formForChecklist(checklist.reportFormId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          form.sectionHeader('passport', fallback: 'Паспортные данные (приложение Б)'),
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Заполняется из шаблона оборудования; при необходимости уточните по паспорту.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 16),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: checklist.orientation == 'horizontal' || checklist.orientation == 'vertical'
              ? checklist.orientation
              : null,
          decoration: const InputDecoration(
            labelText: 'Ориентация сосуда',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
          ),
          dropdownColor: const Color(0xFF1e293b),
          style: const TextStyle(color: Colors.white),
          items: const [
            DropdownMenuItem(value: 'horizontal', child: Text('Горизонтальный')),
            DropdownMenuItem(value: 'vertical', child: Text('Вертикальный')),
          ],
          onChanged: (v) {
            checklist.orientation = v;
            if (v == 'horizontal' &&
                (checklist.constructionType == null ||
                    !checklist.constructionType!.toLowerCase().contains('горизонт'))) {
              checklist.constructionType = 'горизонтальный';
            } else if (v == 'vertical' &&
                (checklist.constructionType == null ||
                    !checklist.constructionType!.toLowerCase().contains('вертикал'))) {
              checklist.constructionType = 'вертикальный';
            }
            onStateChanged();
          },
        ),
        const SizedBox(height: 12),
        _simpleField(
          label: 'Конструктивное исполнение',
          value: checklist.constructionType,
          onChanged: (v) {
            checklist.constructionType = v;
            final s = (v ?? '').toLowerCase();
            if (s.contains('горизонт')) checklist.orientation = 'horizontal';
            if (s.contains('вертикал')) checklist.orientation = 'vertical';
            onStateChanged();
          },
        ),
        _simpleField(
          label: 'Схема подключения (текст)',
          value: checklist.connectionScheme,
          onChanged: (v) {
            checklist.connectionScheme = v;
            onStateChanged();
          },
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1e293b),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Файл схемы подключения',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                (checklist.connectionSchemeFile != null &&
                        checklist.connectionSchemeFile!.trim().isNotEmpty)
                    ? checklist.connectionSchemeFile!.split(RegExp(r'[\\/]')).last
                    : 'Файл не выбран',
                style: TextStyle(
                  color: (checklist.connectionSchemeFile != null &&
                          checklist.connectionSchemeFile!.trim().isNotEmpty)
                      ? Colors.white
                      : Colors.white38,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: onPickConnectionSchemeFile == null
                        ? null
                        : () => onPickConnectionSchemeFile!(),
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Прикрепить'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (checklist.connectionSchemeFile != null &&
                      checklist.connectionSchemeFile!.trim().isNotEmpty)
                    TextButton(
                      onPressed: onClearConnectionSchemeFile,
                      child: const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _simpleField(
                label: 'Индекс схемы (ОГ-13)',
                value: checklist.schemeIndex,
                onChanged: (v) {
                  checklist.schemeIndex = v;
                  onStateChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _simpleField(
                label: 'Объём, м³',
                value: checklist.volume,
                keyboard: TextInputType.number,
                onChanged: (v) {
                  checklist.volume = v;
                  onStateChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _tableBlock(
          context,
          title: 'Б1. Элементы корпуса (${checklist.vesselElements.length})',
          onAdd: () => _editElement(context),
          children: checklist.vesselElements.asMap().entries.map((e) {
            final el = e.value;
            return ListTile(
              dense: true,
              title: Text(
                (el.name ?? 'Элемент').replaceAll('\n', ' '),
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Ø${el.diameterMm ?? "—"} × ${el.wallThicknessMm ?? "—"} мм',
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit, color: Colors.white70, size: 20),
                onPressed: () => _editElement(context, index: e.key),
              ),
            );
          }).toList(),
        ),
        _tableBlock(
          context,
          title: 'Б2. Термообработка (${checklist.heatTreatmentRecords.length})',
          onAdd: () => _editHeat(context),
          children: _simpleRows(
            checklist.heatTreatmentRecords,
            (r) => '${r.element ?? "—"} · ${r.type ?? "—"}',
            (i) => _editHeat(context, index: i),
          ),
        ),
        _tableBlock(
          context,
          title: 'Б3. Гидроиспытания (${checklist.hydraulicTestHistory.length})',
          onAdd: () => _editHydro(context),
          children: _simpleRows(
            checklist.hydraulicTestHistory,
            (r) =>
                '${r.date ?? "—"} · ${r.testType ?? "гидравл."} · ${r.pressure ?? "—"}',
            (i) => _editHydro(context, index: i),
          ),
        ),
        _tableBlock(
          context,
          title: 'Б4. История НК (${checklist.ndtControlHistory.length})',
          onAdd: () => _editNdt(context),
          children: _simpleRows(
            checklist.ndtControlHistory,
            (r) =>
                '${r.date ?? "—"} · ${r.kind ?? r.scope ?? "—"} · ${r.organization ?? ""}',
            (i) => _editNdt(context, index: i),
          ),
        ),
        _tableBlock(
          context,
          title: 'Б5. Ремонты (${checklist.repairHistory.length})',
          onAdd: () => _editRepair(context),
          children: _simpleRows(
            checklist.repairHistory,
            (r) => '${r.year ?? "—"} · ${r.description ?? "—"}',
            (i) => _editRepair(context, index: i),
          ),
        ),
        _tableBlock(
          context,
          title: 'Б6. Арматура и КИП (${checklist.fittingsAndInstruments.length})',
          onAdd: () => _editFitting(context),
          children: _simpleRows(
            checklist.fittingsAndInstruments,
            (r) => '${r.name ?? "—"} · ${r.quantity ?? "1"} шт.',
            (i) => _editFitting(context, index: i),
          ),
        ),
      ],
    );
  }

  List<Widget> _simpleRows<T>(
    List<T> items,
    String Function(T) subtitle,
    void Function(int) onEdit,
  ) {
    return items.asMap().entries.map((e) {
      return ListTile(
        dense: true,
        title: Text(subtitle(e.value), style: const TextStyle(color: Colors.white70)),
        trailing: IconButton(
          icon: const Icon(Icons.edit, color: Colors.white70, size: 20),
          onPressed: () => onEdit(e.key),
        ),
      );
    }).toList();
  }

  Widget _tableBlock(
    BuildContext context, {
    required String title,
    required VoidCallback onAdd,
    required List<Widget> children,
  }) {
    return Card(
      color: const Color(0xFF1E2A38),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        trailing: IconButton(
          icon: const Icon(Icons.add, color: Colors.lightBlueAccent),
          onPressed: onAdd,
        ),
        children: children.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Нет записей', style: TextStyle(color: Colors.white38)),
                ),
              ]
            : children,
      ),
    );
  }

  Future<void> _editElement(BuildContext context, {int? index}) async {
    final existing = index != null ? checklist.vesselElements[index] : VesselElement();
    final name = TextEditingController(text: existing.name);
    final dia = TextEditingController(text: existing.diameterMm);
    final len = TextEditingController(text: existing.lengthMm);
    final wt = TextEditingController(text: existing.wallThicknessMm);
    final calc = TextEditingController(text: existing.calcThickness);
    final mat = TextEditingController(text: existing.material);
    final gost = TextEditingController(text: existing.gost);
    final weld = TextEditingController(text: existing.weldData);
    final elctr = TextEditingController(text: existing.electrodes);
    final ndt = TextEditingController(text: existing.ndtMethod);
    final ys = TextEditingController(text: existing.yieldStrength);
    final ts = TextEditingController(text: existing.tensileStrength);
    final elon = TextEditingController(text: existing.elongation);
    final red = TextEditingController(text: existing.reduction);
    final imp = TextEditingController(text: existing.impact);
    final tTemp = TextEditingController(text: existing.testTemperature);
    final spec = TextEditingController(text: existing.specimenType);
    final ok = await _dialog(
      context,
      'Элемент корпуса',
      [
        buildDialogTextField(name, 'Наименование'),
        buildDialogTextField(dia, 'Диаметр внутренний, мм'),
        buildDialogTextField(len, 'Длина или высота, мм'),
        buildDialogTextField(wt, 'Толщина стенки номинальная, мм'),
        buildDialogTextField(
            calc, 'Расчётная толщина стенки (до прибавки на коррозию), мм'),
        buildDialogTextField(mat, 'Марка стали'),
        buildDialogTextField(gost, 'ГОСТ / ТУ материала'),
        buildDialogTextField(weld, 'Вид сварки'),
        buildDialogTextField(elctr, 'Электроды / сварочная проволока'),
        buildDialogTextField(ndt, 'Метод неразрушающего контроля'),
        const SizedBox(height: 8),
        const Text(
          'Механические испытания (по сертификату / протоколу)',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        buildDialogTextField(ys, 'Предел текучести σт, МПа'),
        buildDialogTextField(ts, 'Временное сопротивление σв, МПа'),
        buildDialogTextField(elon, 'Относительное удлинение δ, %'),
        buildDialogTextField(red, 'Относительное сужение ψ, %'),
        buildDialogTextField(imp, 'Ударная вязкость KCU/KCV'),
        buildDialogTextField(tTemp, 'Температура испытания, °C'),
        buildDialogTextField(spec, 'Тип образца'),
      ],
    );
    if (ok == true) {
      final el = VesselElement()
        ..name = name.text.trim()
        ..diameterMm = dia.text.trim()
        ..lengthMm = len.text.trim()
        ..wallThicknessMm = wt.text.trim()
        ..calcThickness = calc.text.trim()
        ..material = mat.text.trim()
        ..gost = gost.text.trim()
        ..weldData = weld.text.trim()
        ..electrodes = elctr.text.trim()
        ..ndtMethod = ndt.text.trim()
        ..yieldStrength = ys.text.trim()
        ..tensileStrength = ts.text.trim()
        ..elongation = elon.text.trim()
        ..reduction = red.text.trim()
        ..impact = imp.text.trim()
        ..testTemperature = tTemp.text.trim()
        ..specimenType = spec.text.trim();
      if (index != null) {
        checklist.vesselElements[index] = el;
      } else {
        checklist.vesselElements.add(el);
      }
      onStateChanged();
    }
  }

  Future<void> _editHeat(BuildContext context, {int? index}) async {
    final e = index != null ? checklist.heatTreatmentRecords[index] : HeatTreatmentRecord();
    final el = TextEditingController(text: e.element);
    final tp = TextEditingController(text: e.type);
    final mode = TextEditingController(text: e.mode);
    final temp = TextEditingController(text: e.temperature);
    final dur = TextEditingController(text: e.duration);
    final cool = TextEditingController(text: e.cooling);
    final ok = await _dialog(context, 'Термообработка', [
      buildDialogTextField(el, 'Элемент / соединение'),
      buildDialogTextField(tp, 'Вид термообработки'),
      buildDialogTextField(mode, 'Режим термообработки'),
      buildDialogTextField(temp, 'Температура, °C'),
      buildDialogTextField(dur, 'Продолжительность выдержки, ч'),
      buildDialogTextField(cool, 'Способ охлаждения'),
    ]);
    if (ok == true) {
      final r = HeatTreatmentRecord()
        ..element = el.text.trim()
        ..type = tp.text.trim()
        ..mode = mode.text.trim()
        ..temperature = temp.text.trim()
        ..duration = dur.text.trim()
        ..cooling = cool.text.trim();
      if (index != null) {
        checklist.heatTreatmentRecords[index] = r;
      } else {
        checklist.heatTreatmentRecords.add(r);
      }
      onStateChanged();
    }
  }

  Future<void> _editHydro(BuildContext context, {int? index}) async {
    final e = index != null ? checklist.hydraulicTestHistory[index] : HydraulicTestRecord();
    final dt = TextEditingController(text: e.date);
    String testType = e.testType ?? 'гидравлическое';
    String medium = e.medium ?? 'вода';
    final pr = TextEditingController(text: e.pressure);
    final tm = TextEditingController(text: e.temperature);
    final nt = TextEditingController(text: e.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1e293b),
              title: const Text('Испытание на прочность', style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildDialogTextField(dt, 'Дата'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: testType,
                      decoration: const InputDecoration(
                        labelText: 'Вид испытания',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                      dropdownColor: const Color(0xFF0f172a),
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white),
                      items: const [
                        DropdownMenuItem(value: 'гидравлическое', child: Text('Гидравлическое')),
                        DropdownMenuItem(value: 'пневматическое', child: Text('Пневматическое')),
                      ],
                      onChanged: (v) => setLocal(() => testType = v ?? testType),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: ['вода', 'воздух', 'незамерзающая жидкость', 'другое'].contains(medium)
                          ? medium
                          : 'другое',
                      decoration: const InputDecoration(
                        labelText: 'Испытательная среда',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                      dropdownColor: const Color(0xFF0f172a),
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white),
                      items: const [
                        DropdownMenuItem(value: 'вода', child: Text('Вода')),
                        DropdownMenuItem(value: 'воздух', child: Text('Воздух')),
                        DropdownMenuItem(
                            value: 'незамерзающая жидкость', child: Text('Незамерзающая жидкость')),
                        DropdownMenuItem(value: 'другое', child: Text('Другое')),
                      ],
                      onChanged: (v) => setLocal(() => medium = v ?? medium),
                    ),
                    buildDialogTextField(pr, 'Пробное давление, кгс/см²'),
                    buildDialogTextField(tm, 'Температура испытательной среды, °C'),
                    buildDialogTextField(nt, 'Примечание'),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
              ],
            );
          },
        );
      },
    );
    if (ok == true) {
      final r = HydraulicTestRecord()
        ..date = dt.text.trim()
        ..testType = testType
        ..pressure = pr.text.trim()
        ..medium = medium
        ..temperature = tm.text.trim()
        ..note = nt.text.trim();
      if (index != null) {
        checklist.hydraulicTestHistory[index] = r;
      } else {
        checklist.hydraulicTestHistory.add(r);
      }
      onStateChanged();
    }
  }

  Future<void> _editNdt(BuildContext context, {int? index}) async {
    final e = index != null ? checklist.ndtControlHistory[index] : NdtControlRecord();
    final dt = TextEditingController(text: e.date);
    final kd = TextEditingController(text: e.kind);
    final sc = TextEditingController(text: e.scope);
    final rs = TextEditingController(text: e.result);
    final org = TextEditingController(text: e.organization);
    final ok = await _dialog(context, 'История НК', [
      buildDialogTextField(dt, 'Дата'),
      buildDialogTextField(kd, 'Вид контроля'),
      buildDialogTextField(sc, 'Объём контроля'),
      buildDialogTextField(rs, 'Основные результаты контроля'),
      buildDialogTextField(org, 'Организация-исполнитель'),
    ]);
    if (ok == true) {
      final r = NdtControlRecord()
        ..date = dt.text.trim()
        ..kind = kd.text.trim()
        ..scope = sc.text.trim()
        ..result = rs.text.trim()
        ..organization = org.text.trim();
      if (index != null) {
        checklist.ndtControlHistory[index] = r;
      } else {
        checklist.ndtControlHistory.add(r);
      }
      onStateChanged();
    }
  }

  Future<void> _editRepair(BuildContext context, {int? index}) async {
    final e = index != null ? checklist.repairHistory[index] : RepairRecord();
    final yr = TextEditingController(text: e.year);
    final desc = TextEditingController(text: e.description);
    final ok = await _dialog(context, 'Ремонт', [
      buildDialogTextField(yr, 'Год'),
      buildDialogTextField(desc, 'Характер ремонта'),
    ]);
    if (ok == true) {
      final r = RepairRecord()..year = yr.text..description = desc.text;
      if (index != null) {
        checklist.repairHistory[index] = r;
      } else {
        checklist.repairHistory.add(r);
      }
      onStateChanged();
    }
  }

  Future<void> _editFitting(BuildContext context, {int? index}) async {
    final e = index != null ? checklist.fittingsAndInstruments[index] : FittingInstrument();
    final nm = TextEditingController(text: e.name);
    final qty = TextEditingController(text: e.quantity);
    final ok = await _dialog(context, 'Арматура / КИП', [
      buildDialogTextField(nm, 'Наименование'),
      buildDialogTextField(qty, 'Количество'),
    ]);
    if (ok == true) {
      final f = FittingInstrument()..name = nm.text..quantity = qty.text;
      if (index != null) {
        checklist.fittingsAndInstruments[index] = f;
      } else {
        checklist.fittingsAndInstruments.add(f);
      }
      onStateChanged();
    }
  }

  Future<bool?> _dialog(BuildContext context, String title, List<Widget> fields) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A38),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: fields),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
  }

  Widget _simpleField({
    required String label,
    String? value,
    TextInputType keyboard = TextInputType.text,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: value,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.lightBlueAccent),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
