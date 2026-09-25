import 'package:flutter/material.dart';
import '../../data/report_field_schema.dart';
import '../../models/vessel_checklist.dart';

class InspectionProfileMeasurements extends StatefulWidget {
  const InspectionProfileMeasurements({super.key, required this.checklist, required this.onChanged});
  final VesselChecklist checklist;
  final VoidCallback onChanged;
  @override
  State<InspectionProfileMeasurements> createState() => _InspectionProfileMeasurementsState();
}

class _InspectionProfileMeasurementsState extends State<InspectionProfileMeasurements> {
  late final List<Map<String, dynamic>> rows;
  int nextKey = 0;
  @override
  void initState() {
    super.initState();
    final saved = widget.checklist.additionalData?['profile_measurements'];
    rows = saved is List ? saved.whereType<Map>().map((row) => <String, dynamic>{...Map<String, dynamic>.from(row), '_row_id': nextKey++}).toList() : [];
  }
  void changed() {
    widget.checklist.additionalData ??= {};
    widget.checklist.additionalData!['profile_measurements'] = rows;
    widget.onChanged();
  }
  @override
  Widget build(BuildContext context) {
    final columns = ReportFieldSchema.measurementColumns(widget.checklist.reportFormId ?? 'to-1');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Профильные измерения', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Добавьте точки или элементы. Результаты войдут в таблицу приложения к отчёту.', style: TextStyle(color: Colors.white70)),
      for (var index = 0; index < rows.length; index++) Card(
        key: ValueKey(rows[index]['_row_id']),
        child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Row(children: [Expanded(child: Text('Измерение ${index + 1}')), IconButton(tooltip: 'Удалить измерение ${index + 1}',
            onPressed: () => setState(() { rows.removeAt(index); changed(); }), icon: const Icon(Icons.delete_outline))]),
          for (final column in columns) Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(
            initialValue: rows[index][column['key']]?.toString() ?? '',
            keyboardType: column['type'] == 'number' ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
            decoration: InputDecoration(labelText: column['label'], suffixText: column['unit'], border: const OutlineInputBorder()),
            onChanged: (value) { rows[index][column['key']] = value; changed(); },
          )),
        ])),
      ),
      OutlinedButton.icon(onPressed: () => setState(() { rows.add({'_row_id': nextKey++}); changed(); }),
        icon: const Icon(Icons.add), label: const Text('Добавить измерение')),
    ]);
  }
}
