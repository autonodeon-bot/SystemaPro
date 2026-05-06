import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'dart:io';
import '../../models/vessel_checklist.dart';
import '../../widgets/checklist_progress_indicator.dart';
import 'inspection_form_fields.dart';

class InspectionConclusionSection extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionHeader('12. Заключение'),
        buildMultilineField('conclusion', 'Заключение', (value) {
          checklist.conclusion = value;
        }),
        const SizedBox(height: 32),
        if (lastAutoSaveTime != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Последнее сохранение черновика: ${intl.DateFormat('dd.MM HH:mm').format(lastAutoSaveTime!)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        _buildSubmitButton(context),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget buildProgressIndicator() {
    final progress = _calculateProgress();
    final completed = progress['completed']!;
    final total = progress['total']!;

    List<String> missingRequired = [];
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
      missingRequiredFields:
          missingRequired.isNotEmpty ? missingRequired : null,
    );
  }

  Map<String, int> _calculateProgress() {
    int completed = 0;
    int total = 0;

    total += 3;
    if (checklist.inspectionDate != null &&
        checklist.inspectionDate!.isNotEmpty) completed++;
    if (checklist.executors != null && checklist.executors!.isNotEmpty) {
      completed++;
    }
    if (checklist.organization != null &&
        checklist.organization!.isNotEmpty) completed++;

    total += 1;
    if (selectedEquipmentIds.isNotEmpty) completed++;

    total += 5;
    if (checklist.vesselName != null && checklist.vesselName!.isNotEmpty) {
      completed++;
    }
    if (checklist.serialNumber != null &&
        checklist.serialNumber!.isNotEmpty) completed++;
    if (checklist.regNumber != null && checklist.regNumber!.isNotEmpty) {
      completed++;
    }
    if (checklist.manufacturer != null &&
        checklist.manufacturer!.isNotEmpty) completed++;
    if (checklist.manufactureYear != null &&
        checklist.manufactureYear!.isNotEmpty) completed++;

    total += 1;
    if (factoryPlatePhoto != null ||
        (checklist.factoryPlatePhoto != null &&
            checklist.factoryPlatePhoto!.isNotEmpty)) completed++;

    total += 1;
    if (checklist.conclusion != null && checklist.conclusion!.isNotEmpty) {
      completed++;
    }

    return {'completed': completed, 'total': total};
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
              onPressed: isSubmitting ? null : onSaveDraft,
              style: ElevatedButton.styleFrom(
                backgroundColor: kInspectionAccentBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isSubmitting
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
        if (hasAssignment) ...[
          const SizedBox(height: 12),
          Semantics(
            label:
                'Подписать и завершить осмотр. После подписи осмотр будет отправлен при синхронизации.',
            button: true,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isSubmitting ? null : onSignAndFinish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22c55e),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isSubmitting
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
