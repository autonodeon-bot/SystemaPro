import 'package:flutter/material.dart';
import '../../models/vessel_checklist.dart';
import 'inspection_form_fields.dart';

/// Supplemental report values remain part of the offline inspection payload.
class InspectionReportFieldsSection extends StatefulWidget {
  final VesselChecklist checklist;
  final VoidCallback onChanged;
  const InspectionReportFieldsSection({super.key, required this.checklist, required this.onChanged});

  @override
  State<InspectionReportFieldsSection> createState() => _InspectionReportFieldsSectionState();
}

class _InspectionReportFieldsSectionState extends State<InspectionReportFieldsSection> {
  int _revision = 0;

  List<Map<String, dynamic>> get _rows {
    final raw = widget.checklist.additionalData?['report_fields'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  void _save(List<Map<String, dynamic>> rows, {bool rebuild = false}) {
    widget.checklist.additionalData ??= {};
    widget.checklist.additionalData!['report_fields'] = rows;
    widget.onChanged();
    if (rebuild) setState(() => _revision++);
  }

  Widget _field(int index, String key, String label, Map<String, dynamic> row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey('$_revision-$index-$key'),
        initialValue: row[key]?.toString() ?? '',
        style: const TextStyle(color: Colors.white),
        minLines: 1,
        maxLines: key == 'value' ? 5 : 2,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) {
          final rows = _rows;
          rows[index][key] = value;
          _save(rows);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      buildSectionHeader('Дополнительные сведения для отчёта'),
      const Text(
        'Внесите сведения, которых нет в основных разделах или которые не заполнил оператор. '
        'Они попадут в отдельное приложение к отчёту. Основные паспортные данные и результаты НК заполняйте в соответствующих разделах.',
        style: TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 16),
      for (var i = 0; i < rows.length; i++) ...[
        Row(children: [
          Expanded(child: Text('Показатель ${i + 1}', style: const TextStyle(color: Colors.white))),
          IconButton(
            tooltip: 'Удалить показатель ${i + 1}',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirmed = await showConfirmDeleteDialog(context);
              if (!mounted || !confirmed) return;
              final updated = _rows;
              updated.removeAt(i);
              _save(updated, rebuild: true);
            },
          ),
        ]),
        _field(i, 'section', 'Раздел или протокол', rows[i]),
        _field(i, 'label', 'Название показателя', rows[i]),
        _field(i, 'value', 'Значение / результат', rows[i]),
        _field(i, 'unit', 'Единица измерения (если нужна)', rows[i]),
        const Divider(),
      ],
      OutlinedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Добавить показатель'),
        onPressed: () => _save([..._rows, {'section': '', 'label': '', 'value': '', 'unit': ''}], rebuild: true),
      ),
    ]);
  }
}
