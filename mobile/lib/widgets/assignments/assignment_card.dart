import 'package:flutter/material.dart';

import '../../models/assignment.dart';
import '../../services/sync_service.dart';
import '../../theme/app_colors.dart';
import 'assignment_sync_badges.dart';

Color _statusColor(String status) {
  switch (status) {
    case 'PENDING':
      return Colors.orange;
    case 'IN_PROGRESS':
      return Colors.blue;
    case 'COMPLETED':
      return Colors.green;
    case 'CANCELLED':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

Color _priorityColor(String priority) {
  switch (priority) {
    case 'LOW':
      return Colors.grey;
    case 'NORMAL':
      return Colors.blue;
    case 'HIGH':
      return Colors.orange;
    case 'URGENT':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

class AssignmentCard extends StatelessWidget {
  const AssignmentCard({
    super.key,
    required this.assignment,
    required this.localInspectionState,
    required this.opoSurveyFilled,
    required this.formatDate,
    this.onTap,
  });

  final Assignment assignment;
  final LocalAssignmentInspectionState localInspectionState;
  final bool opoSurveyFilled;
  final String Function(DateTime date) formatDate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final statusCol = _statusColor(assignment.status);
    final priCol = _priorityColor(assignment.priority);
    final due = assignment.dueDate;
    final overdue = due != null &&
        due.isBefore(DateTime.now()) &&
        assignment.status != 'COMPLETED';

    return Card(
      color: AppColors.darkBackground,
      margin: EdgeInsets.zero,
      child: Semantics(
        label:
            '${assignment.equipmentName}, статус: ${assignment.statusLabel}, приоритет: ${assignment.priority}',
        button: assignment.status != 'CANCELLED',
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assignment.equipmentCode,
                            style: const TextStyle(
                              color: AppColors.darkPrimary,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            assignment.equipmentName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusCol.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        assignment.statusLabel,
                        style: TextStyle(
                          color: statusCol,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (localInspectionState.hasDraft || localInspectionState.hasSigned)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.cloud_off,
                          size: 18,
                          color: Colors.orange.shade300,
                          semanticLabel: 'Ожидает отправки на сервер',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.assignment,
                        size: 14, color: Colors.grey[400], semanticLabel: 'Тип задания'),
                    const SizedBox(width: 4),
                    Text(
                      assignment.typeLabel,
                      style: TextStyle(color: Colors.grey[300], fontSize: 12),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: priCol.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        assignment.priority,
                        style: TextStyle(
                          color: priCol,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                AssignmentSyncBadges(
                  assignment: assignment,
                  localState: localInspectionState,
                  opoDataFilled: opoSurveyFilled,
                ),
                if (due != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: overdue ? Colors.red : Colors.grey[400],
                        semanticLabel: 'Срок выполнения',
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Срок: ${formatDate(due)}',
                        style: TextStyle(
                          color: overdue ? Colors.red : Colors.grey[300],
                          fontSize: 11,
                          fontWeight: overdue ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
