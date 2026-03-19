import 'package:flutter/material.dart';

import '../../models/assignment.dart';
import '../../services/sync_service.dart';
import '../../theme/app_colors.dart';

class AssignmentSyncBadges extends StatelessWidget {
  const AssignmentSyncBadges({
    super.key,
    required this.assignment,
    required this.localState,
    required this.opoDataFilled,
  });

  final Assignment assignment;
  final LocalAssignmentInspectionState localState;
  final bool opoDataFilled;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (localState.hasDraft) {
      chips.add(const _SyncChip(text: 'Черновик (локально)', color: Colors.orange));
    }
    if (localState.hasSigned) {
      chips.add(const _SyncChip(text: 'Подписано (локально)', color: AppColors.darkPrimary));
    }
    if (assignment.status == 'COMPLETED') {
      chips.add(const _SyncChip(text: 'На сервере', color: Colors.green));
    } else if (localState.hasSigned) {
      chips.add(const _SyncChip(text: 'Ожидает синхронизации', color: Colors.purple));
    }

    final opoId = assignment.opoId;
    if (opoId != null && opoId.isNotEmpty && opoDataFilled) {
      chips.add(const _SyncChip(text: 'ОПО заполнено', color: Colors.teal));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: chips,
      ),
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
