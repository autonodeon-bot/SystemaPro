import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

Future<String?> showInspectionTypeSelectDialog(
  BuildContext context, {
  String? initialType,
}) async {
  String selected = initialType ?? 'NDT';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setInner) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Тип обследования', style: TextStyle(color: Colors.white)),
        content: DropdownButtonFormField<String>(
          value: selected,
          decoration: const InputDecoration(
            labelText: 'Выберите тип',
            labelStyle: TextStyle(color: Colors.white70),
          ),
          dropdownColor: AppColors.darkSurface,
          items: const [
            DropdownMenuItem(
                value: 'VISUAL',
                child: Text('VISUAL', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(
                value: 'NDT', child: Text('NDT', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(
                value: 'QUESTIONNAIRE',
                child: Text('QUESTIONNAIRE', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(
                value: 'EXPERTISE',
                child: Text('EXPERTISE', style: TextStyle(color: Colors.white))),
          ],
          onChanged: (v) => setInner(() => selected = v ?? selected),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, selected),
            child: const Text('Продолжить', style: TextStyle(color: AppColors.darkPrimary)),
          ),
        ],
      ),
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
