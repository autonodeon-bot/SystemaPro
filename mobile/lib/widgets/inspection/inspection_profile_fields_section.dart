import '../../theme/app_colors.dart';
import 'package:flutter/material.dart';
import '../../data/report_field_schema.dart';
import '../../models/vessel_checklist.dart';
import 'inspection_form_fields.dart';
import 'inspection_profile_measurements.dart';

class InspectionProfileFieldsSection extends StatefulWidget {
  final VesselChecklist checklist;
  final VoidCallback onChanged;
  const InspectionProfileFieldsSection(
      {super.key, required this.checklist, required this.onChanged});
  @override
  State<InspectionProfileFieldsSection> createState() =>
      _InspectionProfileFieldsSectionState();
}

class _InspectionProfileFieldsSectionState
    extends State<InspectionProfileFieldsSection> {
  late Future<void> _loading = ReportFieldSchema.ensureLoaded();
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return TextButton(
              onPressed: () =>
                  setState(() => _loading = ReportFieldSchema.ensureLoaded()),
              child: const Text('Повторить загрузку характеристик'));
        if (snapshot.connectionState != ConnectionState.done)
          return const LinearProgressIndicator();
        final fields = ReportFieldSchema.fieldsFor(
            widget.checklist.reportFormId ?? 'to-1');
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildSectionHeader('Характеристики по типу оборудования'),
              Text(
                  'Заполняйте по паспорту и результатам обследования. Введённые здесь характеристики имеют приоритет в отчёте.',
                  style: TextStyle(color: AppColors.mutedText(context))),
              const SizedBox(height: 16),
              for (final field in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    initialValue:
                        (widget.checklist.additionalData?['profile_values']
                                    as Map?)?[field['key']]
                                ?.toString() ??
                            '',
                    style: TextStyle(color: AppColors.onSurface(context)),
                    minLines: 1,
                    maxLines: field['type'] == 'number' ? 1 : 3,
                    keyboardType: field['type'] == 'number'
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    decoration: InputDecoration(
                        labelText: field['label'] as String,
                        suffixText: field['unit'] as String,
                        labelStyle:
                            TextStyle(color: AppColors.mutedText(context)),
                        border: const OutlineInputBorder()),
                    onChanged: (value) {
                      widget.checklist.additionalData ??= {};
                      final previous =
                          widget.checklist.additionalData!['profile_values'];
                      widget.checklist.additionalData!['profile_values'] = {
                        ...(previous is Map
                            ? Map<String, dynamic>.from(previous)
                            : <String, dynamic>{}),
                        field['key'] as String: value,
                      };
                      widget.onChanged();
                    },
                  ),
                ),
              InspectionProfileMeasurements(
                  checklist: widget.checklist, onChanged: widget.onChanged),
            ]);
      });
}
