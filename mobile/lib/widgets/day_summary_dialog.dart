import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Сводка «Итоги дня» после синхронизации.
Future<void> showDaySummaryDialog(
  BuildContext context, {
  required int syncedCount,
  required int failedCount,
  required int draftsLeft,
  required int pendingLeft,
  List<String> completedAssignmentTitles = const [],
}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.darkSurface,
      title: const Row(
        children: [
          Icon(Icons.summarize_outlined, color: AppColors.accent, size: 22),
          SizedBox(width: 8),
          Text('Итоги синхронизации', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(Icons.cloud_done, AppColors.success,
                'Отправлено на сервер', '$syncedCount'),
            const SizedBox(height: 8),
            if (failedCount > 0)
              _row(Icons.error_outline, AppColors.danger,
                  'Не удалось отправить', '$failedCount'),
            if (failedCount > 0) const SizedBox(height: 8),
            _row(Icons.edit_note, AppColors.warning, 'Черновиков осталось',
                '$draftsLeft'),
            const SizedBox(height: 8),
            _row(Icons.sync_problem, AppColors.warning,
                'В очереди на отправку', '$pendingLeft'),
            if (completedAssignmentTitles.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Завершённые задания:',
                style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
              const SizedBox(height: 6),
              ...completedAssignmentTitles.take(8).map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: AppColors.success, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              t,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

Widget _row(IconData icon, Color color, String label, String value) {
  return Row(
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ),
      Text(value,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 15)),
    ],
  );
}
