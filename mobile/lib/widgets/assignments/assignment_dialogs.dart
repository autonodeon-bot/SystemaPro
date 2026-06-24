import 'package:flutter/material.dart';

import '../../data/technical_report_form_registry.dart';
import '../../models/equipment.dart';
import '../../theme/app_colors.dart';

Future<InspectionStartSelection?> showTechnicalReportFormSelectDialog(
  BuildContext context, {
  required Equipment equipment,
  required String assignmentType,
  String? initialFormId,
}) async {
  await TechnicalReportFormRegistry.ensureLoaded();
  if (!context.mounted) return null;
  final forms = TechnicalReportFormRegistry.forms;
  final suggested = initialFormId ??
      TechnicalReportFormRegistry.suggestFormId(equipment);
  var selectedId = forms.any((f) => f.id == suggested)
      ? suggested
      : 'to-1';
  final queryController = TextEditingController();

  return showDialog<InspectionStartSelection>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setInner) {
        final query = queryController.text.trim().toLowerCase();
        final filtered = query.isEmpty
            ? forms
            : forms
                .where((f) =>
                    f.displayTitle.toLowerCase().contains(query) ||
                    f.number.toString().contains(query))
                .toList();

        return AlertDialog(
          backgroundColor: AppColors.darkSurface,
          title: const Text(
            'Форма технического отчёта',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  equipment.name,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: queryController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Поиск формы ТО…',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) => setInner(() {}),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'Формы не найдены',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (ctx, index) {
                            final form = filtered[index];
                            final selected = form.id == selectedId;
                            return RadioListTile<String>(
                              value: form.id,
                              groupValue: selectedId,
                              activeColor: AppColors.darkPrimary,
                              title: Text(
                                form.displayTitle,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                'Приложение № ${form.number}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              onChanged: (v) {
                                if (v != null) setInner(() => selectedId = v);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Отмена',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                InspectionStartSelection(
                  reportFormId: selectedId,
                  inspectionType: TechnicalReportFormRegistry
                      .inspectionTypeFromAssignment(assignmentType),
                ),
              ),
              child: const Text(
                'Продолжить',
                style: TextStyle(color: AppColors.darkPrimary),
              ),
            ),
          ],
        );
      },
    ),
  );
}

Future<String?> showCompletedAssignmentChoiceDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Задание выполнено'),
      content: const Text(
        'Это задание уже выполнено. Что вы хотите сделать?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'edit'),
          child: const Text('Внести изменения'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'restart'),
          child: const Text('Пройти заново'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
}
