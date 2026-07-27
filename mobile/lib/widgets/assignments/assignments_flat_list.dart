import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/assignment.dart';
import '../../services/recent_service.dart';
import '../../services/sync_service.dart';
import '../../theme/app_colors.dart';
import 'assignment_card.dart';

/// Плоский список заданий с группировкой-разделителем по предприятию.
/// Все задания видны без раскрытия — просто листаем.
class AssignmentsFlatList extends StatelessWidget {
  const AssignmentsFlatList({
    super.key,
    required this.assignments,
    required this.recentItems,
    required this.localInspectionState,
    required this.opoHasData,
    required this.formatDate,
    required this.onAssignmentTap,
    this.onAssignmentDetails,
    required this.onRecentItemTap,
    required this.onAssignmentsReload,
  });

  final List<Assignment> assignments;
  final List<RecentItem> recentItems;
  final Map<String, LocalAssignmentInspectionState> localInspectionState;
  final Map<String, bool> opoHasData;
  final String Function(DateTime date) formatDate;
  final void Function(Assignment assignment) onAssignmentTap;
  final void Function(Assignment assignment)? onAssignmentDetails;
  final void Function(RecentItem item) onRecentItemTap;
  final Future<void> Function() onAssignmentsReload;

  @override
  Widget build(BuildContext context) {
    final hasRecent = recentItems.isNotEmpty;

    if (assignments.isEmpty && !hasRecent) {
      return const Center(
        child: Text(
          'Нет заданий',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    // Группируем для вставки заголовков-разделителей
    final items = <_ListItem>[];
    if (hasRecent) items.add(_RecentItem(recentItems));

    String? lastKey;
    for (final a in assignments) {
      final key = a.enterpriseName ?? '';
      if (key != lastKey) {
        items.add(_GroupHeader(
          enterprise: a.enterpriseName,
          branch: a.branchName,
          opoId: a.opoId,
          opoName: a.opoName,
          opoHasData: opoHasData,
          context: context,
          onAssignmentsReload: onAssignmentsReload,
        ));
        lastKey = key;
      }
      items.add(_AssignmentItem(
        assignment: a,
        localState: localInspectionState[a.id] ?? LocalAssignmentInspectionState.none(),
        opoFilled: a.opoId != null && (opoHasData[a.opoId!] == true),
        formatDate: formatDate,
        onTap: a.status == 'CANCELLED' ? null : () => onAssignmentTap(a),
        onDetails: onAssignmentDetails == null
            ? null
            : () => onAssignmentDetails!(a),
        onStart: a.status == 'CANCELLED' ? null : () => onAssignmentTap(a),
      ));
    }

    return RefreshIndicator(
      onRefresh: onAssignmentsReload,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: items.length,
        itemBuilder: (ctx, i) => items[i].build(ctx),
      ),
    );
  }
}

abstract class _ListItem {
  Widget build(BuildContext context);
}

class _RecentItem extends _ListItem {
  _RecentItem(this.items);
  final List<RecentItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Icon(Icons.history, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'Недавно открытые',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final item = items[i];
                return ActionChip(
                  avatar: const Icon(Icons.history, color: Colors.white54, size: 16),
                  label: Text(
                    item.title,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  backgroundColor: AppColors.darkSurface,
                  side: const BorderSide(color: AppColors.darkBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onPressed: () {},
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends _ListItem {
  _GroupHeader({
    required this.enterprise,
    required this.branch,
    required this.opoId,
    required this.opoName,
    required this.opoHasData,
    required this.context,
    required this.onAssignmentsReload,
  });

  final String? enterprise;
  final String? branch;
  final String? opoId;
  final String? opoName;
  final Map<String, bool> opoHasData;
  final BuildContext context;
  final Future<void> Function() onAssignmentsReload;

  @override
  Widget build(BuildContext ctx) {
    final name = [enterprise, branch].where((s) => s != null && s.isNotEmpty).join(' • ');
    final opoFilled = opoId != null && opoId!.isNotEmpty && (opoHasData[opoId!] == true);

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name.isEmpty ? 'Без предприятия' : name,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (opoId != null && opoId!.isNotEmpty && opoName != null) ...[
            if (opoFilled)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'ОПО ✓',
                  style: TextStyle(color: Colors.teal, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () async {
                final ok = await ctx.push<bool>('/opo-survey', extra: {
                  'opoId': opoId!,
                  'opoName': opoName!,
                });
                if (ok == true) await onAssignmentsReload();
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.assignment_turned_in_outlined,
                  size: 22,
                  color: opoFilled ? Colors.teal : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssignmentItem extends _ListItem {
  _AssignmentItem({
    required this.assignment,
    required this.localState,
    required this.opoFilled,
    required this.formatDate,
    required this.onTap,
    this.onDetails,
    this.onStart,
  });

  final Assignment assignment;
  final LocalAssignmentInspectionState localState;
  final bool opoFilled;
  final String Function(DateTime) formatDate;
  final VoidCallback? onTap;
  final VoidCallback? onDetails;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final card = AssignmentCard(
      assignment: assignment,
      localInspectionState: localState,
      opoSurveyFilled: opoFilled,
      formatDate: formatDate,
      onTap: onTap,
    );
    if (onStart == null && onDetails == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: card,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Dismissible(
        key: ValueKey('asg_${assignment.id}'),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            onStart?.call();
          } else {
            onDetails?.call();
          }
          return false; // не удаляем карточку
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.25),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            children: [
              Icon(Icons.play_arrow, color: AppColors.success, size: 28),
              SizedBox(width: 8),
              Text('Начать',
                  style: TextStyle(
                      color: AppColors.success, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.25),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Детали',
                  style: TextStyle(
                      color: AppColors.accent, fontWeight: FontWeight.w700)),
              SizedBox(width: 8),
              Icon(Icons.info_outline, color: AppColors.accent, size: 28),
            ],
          ),
        ),
        child: card,
      ),
    );
  }
}
