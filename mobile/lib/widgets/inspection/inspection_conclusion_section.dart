import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'dart:io';
import '../../data/technical_report_form_registry.dart';
import '../../models/vessel_checklist.dart';
import '../../widgets/checklist_progress_indicator.dart';
import 'inspection_form_fields.dart';

/// Стандартные тексты заключения по оценке пригодности.
String suitabilityConclusionText(
  String status,
  VesselChecklist checklist, {
  String restrictions = '',
}) {
  final name = checklist.vesselName ?? 'оборудование';
  final serial = checklist.serialNumber ?? '';
  final reg = checklist.regNumber ?? '';
  final inv = checklist.regNumber ?? '';
  var ident = name;
  if (serial.isNotEmpty) ident += ' зав. № $serial';
  if (reg.isNotEmpty) ident += ', рег. № $reg';
  if (inv.isNotEmpty) ident += ', инв. № $inv';

  switch (status.toUpperCase()) {
    case 'UNFIT':
    case 'NOT_FIT':
      return 'На основании результатов выполненного комплекса работ по техническому '
          'диагностированию $ident техническое состояние оценивается как неудовлетворительное. '
          'Дальнейшая эксплуатация оборудования не допускается до устранения выявленных недостатков '
          'и проведения повторного обследования.';
    case 'LIMITED_FIT':
    case 'LIMITED':
      final restr = restrictions.trim().isNotEmpty
          ? ' Эксплуатация допускается при соблюдении ограничений: $restrictions.'
          : ' Эксплуатация допускается при соблюдении установленных ограничений.';
      return 'На основании результатов выполненного комплекса работ по техническому '
          'диагностированию $ident техническое состояние оценивается как ограниченно пригодное.$restr';
    case 'COMPLIANT':
      return 'На основании результатов выполненного комплекса работ по техническому '
          'диагностированию $ident оборудование соответствует требованиям нормативно-технической '
          'документации и пригодно к дальнейшей эксплуатации.';
    case 'NON_COMPLIANT':
    case 'NOT_COMPLIANT':
      return 'На основании результатов выполненного комплекса работ по техническому '
          'диагностированию $ident оборудование не соответствует требованиям нормативно-технической '
          'документации. Дальнейшая эксплуатация не допускается до устранения выявленных недостатков.';
    case 'PARTIALLY_COMPLIANT':
      return 'На основании результатов выполненного комплекса работ по техническому '
          'диагностированию $ident оборудование ограниченно соответствует требованиям '
          'нормативно-технической документации при соблюдении установленных ограничений.';
    default:
      return 'На основании результатов выполненного комплекса работ по техническому '
          'диагностированию $ident, работающего под давлением, техническое состояние оценивается '
          'как работоспособное. Оборудование пригодно к дальнейшей эксплуатации при соблюдении '
          'проектных параметров.';
  }
}

/// Индикатор заполнения чек-листа — вынесен из State для использования на странице 0.
Widget buildInspectionProgressIndicator({
  required VesselChecklist checklist,
  required List<String> selectedEquipmentIds,
  required File? factoryPlatePhoto,
}) {
  int completed = 0;
  int total = 0;

  total += 3;
  if (checklist.inspectionDate != null && checklist.inspectionDate!.isNotEmpty) {
    completed++;
  }
  if (checklist.executors != null && checklist.executors!.isNotEmpty) {
    completed++;
  }
  if (checklist.organization != null && checklist.organization!.isNotEmpty) {
    completed++;
  }

  total += 1;
  if (selectedEquipmentIds.isNotEmpty) completed++;

  total += 5;
  if (checklist.vesselName != null && checklist.vesselName!.isNotEmpty) {
    completed++;
  }
  if (checklist.serialNumber != null && checklist.serialNumber!.isNotEmpty) {
    completed++;
  }
  if (checklist.regNumber != null && checklist.regNumber!.isNotEmpty) {
    completed++;
  }
  if (checklist.manufacturer != null && checklist.manufacturer!.isNotEmpty) {
    completed++;
  }
  if (checklist.manufactureYear != null && checklist.manufactureYear!.isNotEmpty) {
    completed++;
  }

  total += 1;
  if (factoryPlatePhoto != null ||
      (checklist.factoryPlatePhoto != null &&
          checklist.factoryPlatePhoto!.isNotEmpty)) {
    completed++;
  }

  total += 1;
  if (checklist.conclusion != null && checklist.conclusion!.isNotEmpty) {
    completed++;
  }

  final missingRequired = <String>[];
  if (checklist.inspectionDate == null || checklist.inspectionDate!.isEmpty) {
    missingRequired.add('Дата обследования');
  }
  if (checklist.executors == null || checklist.executors!.isEmpty) {
    missingRequired.add('Исполнители');
  }
  if (checklist.organization == null || checklist.organization!.isEmpty) {
    missingRequired.add('Организация');
  }
  if (selectedEquipmentIds.isEmpty) {
    missingRequired.add('Оборудование для поверок');
  }
  if (factoryPlatePhoto == null &&
      (checklist.factoryPlatePhoto == null ||
          checklist.factoryPlatePhoto!.isEmpty)) {
    missingRequired.add('Фото заводской таблички');
  }
  if (checklist.conclusion == null || checklist.conclusion!.isEmpty) {
    missingRequired.add('Заключение');
  }

  return ChecklistProgressIndicator(
    completedFields: completed,
    totalFields: total,
    missingRequiredFields: missingRequired.isNotEmpty ? missingRequired : null,
  );
}

class InspectionConclusionSection extends StatefulWidget {
  final VesselChecklist checklist;
  final bool isSubmitting;
  final bool hasAssignment;
  final DateTime? lastAutoSaveTime;
  final List<String> selectedEquipmentIds;
  final File? factoryPlatePhoto;
  final VoidCallback onSaveDraft;
  final VoidCallback onSignAndFinish;

  const InspectionConclusionSection({
    super.key,
    required this.checklist,
    required this.isSubmitting,
    required this.hasAssignment,
    required this.lastAutoSaveTime,
    required this.selectedEquipmentIds,
    required this.factoryPlatePhoto,
    required this.onSaveDraft,
    required this.onSignAndFinish,
  });

  @override
  State<InspectionConclusionSection> createState() =>
      _InspectionConclusionSectionState();
}

class _InspectionConclusionSectionState extends State<InspectionConclusionSection> {
  String _suitabilityStatus = 'FIT';
  final _restrictionsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final add = widget.checklist.additionalData;
    final saved = add?['suitability_status']?.toString();
    if (saved != null && saved.isNotEmpty) {
      _suitabilityStatus = saved;
    }
    _restrictionsController.text =
        add?['suitability_restrictions']?.toString() ?? '';
    if (widget.checklist.conclusion == null ||
        widget.checklist.conclusion!.trim().isEmpty) {
      _applySuitability(_suitabilityStatus);
    }
  }

  @override
  void dispose() {
    _restrictionsController.dispose();
    super.dispose();
  }

  void _applySuitability(String status) {
    setState(() => _suitabilityStatus = status);
    widget.checklist.additionalData ??= <String, dynamic>{};
    widget.checklist.additionalData!['suitability_status'] = status;
    widget.checklist.conclusion = suitabilityConclusionText(
      status,
      widget.checklist,
      restrictions: _restrictionsController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final checklist = widget.checklist;
    final form = TechnicalReportFormRegistry.formForChecklist(checklist.reportFormId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionHeader(
          form.sectionHeader('conclusion', fallback: '12. Заключение'),
        ),
        const Text(
          'Оценка пригодности',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Пригоден'),
              selected: _suitabilityStatus == 'FIT',
              onSelected: (_) => _applySuitability('FIT'),
            ),
            ChoiceChip(
              label: const Text('Ограниченно пригоден'),
              selected: _suitabilityStatus == 'LIMITED_FIT',
              onSelected: (_) => _applySuitability('LIMITED_FIT'),
            ),
            ChoiceChip(
              label: const Text('Не пригоден'),
              selected: _suitabilityStatus == 'UNFIT',
              onSelected: (_) => _applySuitability('UNFIT'),
            ),
            ChoiceChip(
              label: const Text('Соответствует'),
              selected: _suitabilityStatus == 'COMPLIANT',
              onSelected: (_) => _applySuitability('COMPLIANT'),
            ),
            ChoiceChip(
              label: const Text('Не соответствует'),
              selected: _suitabilityStatus == 'NON_COMPLIANT',
              onSelected: (_) => _applySuitability('NON_COMPLIANT'),
            ),
            ChoiceChip(
              label: const Text('Ограниченно соответствует'),
              selected: _suitabilityStatus == 'PARTIALLY_COMPLIANT',
              onSelected: (_) => _applySuitability('PARTIALLY_COMPLIANT'),
            ),
          ],
        ),
        if (_suitabilityStatus == 'LIMITED_FIT') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _restrictionsController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Ограничения эксплуатации',
              labelStyle: TextStyle(color: Colors.white54),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _applySuitability('LIMITED_FIT'),
          ),
        ],
        const SizedBox(height: 16),
        buildMultilineField('conclusion', 'Заключение (можно отредактировать)', (value) {
          checklist.conclusion = value;
        }),
        const SizedBox(height: 32),
        if (widget.lastAutoSaveTime != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Последнее сохранение черновика: ${intl.DateFormat('dd.MM HH:mm').format(widget.lastAutoSaveTime!)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        _buildSubmitButton(context),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget buildProgressIndicator() {
    return buildInspectionProgressIndicator(
      checklist: widget.checklist,
      selectedEquipmentIds: widget.selectedEquipmentIds,
      factoryPlatePhoto: widget.factoryPlatePhoto,
    );
  }

  Widget _buildSubmitButton(BuildContext context) {
    return Column(
      children: [
        Semantics(
          label:
              'Сохранить черновик осмотра. Данные будут отправлены при синхронизации.',
          button: true,
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: widget.isSubmitting ? null : widget.onSaveDraft,
              style: ElevatedButton.styleFrom(
                backgroundColor: kInspectionAccentBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: widget.isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Сохранить (черновик)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
        if (widget.hasAssignment) ...[
          const SizedBox(height: 12),
          Semantics(
            label:
                'Подписать и завершить осмотр. После подписи осмотр будет отправлен при синхронизации.',
            button: true,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: widget.isSubmitting ? null : widget.onSignAndFinish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22c55e),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: widget.isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Подписать / Завершить',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        ],
        SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 12),
      ],
    );
  }
}
