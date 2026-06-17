import 'package:flutter/material.dart';
import '../models/inspection_object_template.dart';
import '../theme/app_colors.dart';

/// Выбор шаблона обследования перед созданием акта.
class InspectionTemplatePickerSheet extends StatelessWidget {
  final List<InspectionObjectTemplate> templates;
  final String equipmentName;
  final void Function(InspectionObjectTemplate? selected) onConfirm;

  const InspectionTemplatePickerSheet({
    super.key,
    required this.templates,
    required this.equipmentName,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1e293b),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Шаблон обследования · $equipmentName',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_note, color: Colors.white54),
                  title: const Text(
                    'Без шаблона',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Только данные из карточки оборудования',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () => onConfirm(null),
                ),
                for (final t in templates)
                  ListTile(
                    leading: const Icon(Icons.description_outlined,
                        color: AppColors.accent),
                    title: Text(
                      t.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      [
                        if (t.equipmentKind != null && t.equipmentKind!.isNotEmpty)
                          t.equipmentKind,
                        if (t.description != null) t.description,
                      ].whereType<String>().join(' · '),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () => onConfirm(t),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextButton(
              onPressed: () => onConfirm(null),
              child: const Text('Пропустить'),
            ),
          ),
        ],
      ),
    );
  }
}
