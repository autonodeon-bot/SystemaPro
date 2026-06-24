import 'package:flutter/material.dart';

import '../../data/technical_report_form_registry.dart';

import '../../models/vessel_checklist.dart';
import 'inspection_form_fields.dart';

/// Паспортные данные для приложения Б (таблицы Б1–Б6) и поля ЭПБ.
class InspectionPassportSection extends StatelessWidget {
  final VesselChecklist checklist;
  final VoidCallback onStateChanged;

  const InspectionPassportSection({
    super.key,
    required this.checklist,
    required this.onStateChanged,
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
        _simpleField(
          label: 'Конструктивное исполнение',
          value: checklist.constructionType,
          onChanged: (v) {
            checklist.constructionType = v;
            onStateChanged();
          },
        ),
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
            (r) => '${r.date ?? "—"} · ${r.pressure ?? "—"}',
            (i) => _editHydro(context, index: i),
          ),
        ),
        _tableBlock(
          context,
          title: 'Б4. История НК (${checklist.ndtControlHistory.length})',
          onAdd: () => _editNdt(context),
          children: _simpleRows(
            checklist.ndtControlHistory,
            (r) => '${r.date ?? "—"} · ${r.scope ?? "—"}',
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
    final mat = TextEditingController(text: existing.material);
    final ok = await _dialog(
      context,
      'Элемент корпуса',
      [
        buildDialogTextField(name, 'Наименование'),
        buildDialogTextField(dia, 'Диаметр, мм'),
        buildDialogTextField(len, 'Длина, мм'),
        buildDialogTextField(wt, 'Толщина стенки, мм'),
        buildDialogTextField(mat, 'Марка материала'),
      ],
    );
    if (ok == true) {
      final el = VesselElement()
        ..name = name.text.trim()
        ..diameterMm = dia.text.trim()
        ..lengthMm = len.text.trim()
        ..wallThicknessMm = wt.text.trim()
        ..material = mat.text.trim();
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
    final ok = await _dialog(context, 'Термообработка', [
      buildDialogTextField(el, 'Элемент'),
      buildDialogTextField(tp, 'Вид'),
    ]);
    if (ok == true) {
      final r = HeatTreatmentRecord()..element = el.text..type = tp.text;
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
    final pr = TextEditingController(text: e.pressure);
    final ok = await _dialog(context, 'Гидроиспытание', [
      buildDialogTextField(dt, 'Дата'),
      buildDialogTextField(pr, 'Пробное давление'),
    ]);
    if (ok == true) {
      final r = HydraulicTestRecord()..date = dt.text..pressure = pr.text;
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
    final sc = TextEditingController(text: e.scope);
    final ok = await _dialog(context, 'История НК', [
      buildDialogTextField(dt, 'Дата'),
      buildDialogTextField(sc, 'Вид и объём'),
    ]);
    if (ok == true) {
      final r = NdtControlRecord()..date = dt.text..scope = sc.text;
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
