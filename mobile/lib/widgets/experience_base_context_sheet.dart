import 'package:flutter/material.dart';
import '../models/experience_base_entry.dart';
import '../theme/app_colors.dart';

/// Подсказки опытной базы перед созданием акта по объекту.
class ExperienceBaseContextSheet extends StatelessWidget {
  final List<ExperienceBaseEntry> items;
  final String equipmentName;
  final VoidCallback onContinue;

  const ExperienceBaseContextSheet({
    super.key,
    required this.items,
    required this.equipmentName,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final userItems = items.where((e) => !e.isArchetype).toList();
    final archetypes = items.where((e) => e.isArchetype).toList();
    final show = userItems.isNotEmpty ? userItems : archetypes;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.menu_book_outlined, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Опытная база · $equipmentName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final e in show.take(12))
                  Card(
                    color: const Color(0xFF0f172a),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        e.displayTitle,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.entryTypeLabel,
                            style: TextStyle(
                              color: AppColors.accent.withOpacity(0.9),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            e.body,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkPrimary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('Продолжить создание акта'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
