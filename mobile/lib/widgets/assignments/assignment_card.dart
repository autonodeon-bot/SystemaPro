import 'package:flutter/material.dart';

import '../../models/assignment.dart';
import '../../services/sync_service.dart';
import '../../theme/app_colors.dart';
import 'assignment_sync_badges.dart';

/// Mobile 2026: плотная карточка задания с цветной боковой «пульсацией» статуса,
/// чипами и семантической палитрой из AppColors.
Color _statusColor(String status) {
  switch (status) {
    case 'PENDING':
      return AppColors.warning;
    case 'IN_PROGRESS':
      return AppColors.accent;
    case 'COMPLETED':
      return AppColors.success;
    case 'CANCELLED':
      return AppColors.danger;
    default:
      return AppColors.textSecondary;
  }
}

Color _priorityColor(String priority) {
  switch (priority) {
    case 'LOW':
      return AppColors.textSecondary;
    case 'NORMAL':
      return AppColors.accent;
    case 'HIGH':
      return AppColors.warning;
    case 'URGENT':
      return AppColors.danger;
    default:
      return AppColors.textSecondary;
  }
}

String _priorityLabel(String priority) {
  switch (priority) {
    case 'LOW':
      return 'Низкий';
    case 'NORMAL':
      return 'Обычный';
    case 'HIGH':
      return 'Высокий';
    case 'URGENT':
      return 'Срочный';
    default:
      return priority;
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
    final hasPendingSync =
        localInspectionState.hasDraft || localInspectionState.hasSigned;

    return Semantics(
      label:
          '${assignment.equipmentName}, статус: ${assignment.statusLabel}, приоритет: ${assignment.priority}',
      button: assignment.status != 'CANCELLED',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: overdue
                    ? AppColors.danger.withOpacity(0.45)
                    : AppColors.darkBorder,
                width: 1,
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: statusCol,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Верхняя строка: код + статус + sync-индикатор
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  assignment.equipmentCode,
                                  style: const TextStyle(
                                    color: AppColors.darkPrimary,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _statusChip(assignment.statusLabel, statusCol),
                              if (hasPendingSync)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(
                                    Icons.cloud_off,
                                    size: 16,
                                    color: AppColors.warning,
                                    semanticLabel: 'Ожидает отправки на сервер',
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            assignment.equipmentName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              letterSpacing: -0.1,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _pill(
                                icon: Icons.assignment_outlined,
                                text: assignment.typeLabel,
                                color: AppColors.textSecondary,
                              ),
                              _pill(
                                icon: Icons.flag_outlined,
                                text: _priorityLabel(assignment.priority),
                                color: priCol,
                                filled: true,
                              ),
                              if (assignment.protocolTemplateId != null &&
                                  assignment.protocolTemplateId!.isNotEmpty)
                                _pill(
                                  icon: Icons.article_outlined,
                                  text: assignment.protocolTemplateName ??
                                      'Шаблон задания',
                                  color: AppColors.accent,
                                  filled: true,
                                ),
                              if (due != null)
                                _pill(
                                  icon: Icons.calendar_today_outlined,
                                  text: 'Срок: ${formatDate(due)}',
                                  color: overdue ? AppColors.danger : AppColors.textSecondary,
                                  filled: overdue,
                                ),
                            ],
                          ),
                          AssignmentSyncBadges(
                            assignment: assignment,
                            localState: localInspectionState,
                            opoDataFilled: opoSurveyFilled,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        border: Border.all(color: color.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required String text,
    required Color color,
    bool filled = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withOpacity(0.12) : Colors.transparent,
        border: Border.all(
          color: filled ? color.withOpacity(0.3) : AppColors.darkBorder,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
