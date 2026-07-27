import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/assignment.dart';
import '../../services/recent_service.dart';
import '../../services/sync_service.dart';
import '../../theme/app_colors.dart';
import 'assignment_card.dart';
import 'assignment_group.dart';

class AssignmentsGroupedList extends StatelessWidget {
  const AssignmentsGroupedList({
    super.key,
    required this.groups,
    required this.recentItems,
    required this.expandedGroups,
    required this.localInspectionState,
    required this.opoHasData,
    required this.formatDate,
    required this.onExpansionChanged,
    required this.onAssignmentTap,
    this.onAssignmentDetails,
    required this.onRecentItemTap,
    required this.onAssignmentsReload,
  });

  final List<AssignmentGroup> groups;
  final List<RecentItem> recentItems;
  final Map<String, bool> expandedGroups;
  final Map<String, LocalAssignmentInspectionState> localInspectionState;
  final Map<String, bool> opoHasData;
  final String Function(DateTime date) formatDate;
  final void Function(String groupKey, bool expanded) onExpansionChanged;
  final void Function(Assignment assignment) onAssignmentTap;
  final void Function(Assignment assignment)? onAssignmentDetails;
  final void Function(RecentItem item) onRecentItemTap;
  final Future<void> Function() onAssignmentsReload;

  @override
  Widget build(BuildContext context) {
    final hasRecent = recentItems.isNotEmpty;

    if (groups.isEmpty && !hasRecent) {
      return const Center(
        child: Text(
          'Нет заданий',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: (hasRecent ? 1 : 0) + groups.length,
      itemBuilder: (context, listIndex) {
        if (hasRecent && listIndex == 0) {
          return _RecentSection(
            items: recentItems,
            onItemTap: onRecentItemTap,
          );
        }
        final groupIndex = hasRecent ? listIndex - 1 : listIndex;
        final group = groups[groupIndex];
        final groupKey = group.key;
        final isExpanded = expandedGroups[groupKey] ?? true;

        return Card(
          color: AppColors.darkSurface,
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            key: Key(groupKey),
            initiallyExpanded: isExpanded,
            onExpansionChanged: (expanded) => onExpansionChanged(groupKey, expanded),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.folder,
                      color: Colors.blue[300],
                      size: 20,
                      semanticLabel: 'Группа заданий',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        group.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${group.assignments.length}',
                        style: TextStyle(
                          color: Colors.blue[300],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if ((group.opoName ?? '').isNotEmpty &&
                        group.assignments.isNotEmpty &&
                        ((group.assignments.first.opoId ?? '').isNotEmpty))
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                        tooltip: 'Заполнить ОПО',
                        onPressed: () async {
                          final first = group.assignments.first;
                          final ok = await context.push<bool>('/opo-survey', extra: {
                            'opoId': first.opoId!,
                            'opoName': group.opoName!,
                          });
                          if (ok == true) {
                            await onAssignmentsReload();
                          }
                        },
                        icon: const Icon(Icons.assignment_turned_in, color: Colors.green, size: 20),
                      ),
                    if (group.assignments.isNotEmpty &&
                        ((group.assignments.first.opoId ?? '').isNotEmpty) &&
                        (opoHasData[group.assignments.first.opoId!] == true))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal.withOpacity(0.35)),
                        ),
                        child: const Text(
                          'ОПО заполнено',
                          style: TextStyle(
                              color: Colors.teal, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            children: group.assignments.map((assignment) {
              final opoId = assignment.opoId;
              final opoFilled = opoId != null &&
                  opoId.isNotEmpty &&
                  (opoHasData[opoId] == true);

              final card = AssignmentCard(
                assignment: assignment,
                localInspectionState:
                    localInspectionState[assignment.id] ?? LocalAssignmentInspectionState.none(),
                opoSurveyFilled: opoFilled,
                formatDate: formatDate,
                onTap: assignment.status == 'CANCELLED'
                    ? null
                    : () => onAssignmentTap(assignment),
              );

              return Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Dismissible(
                  key: ValueKey('gasg_${assignment.id}'),
                  confirmDismiss: (direction) async {
                    if (assignment.status == 'CANCELLED') return false;
                    if (direction == DismissDirection.startToEnd) {
                      onAssignmentTap(assignment);
                    } else {
                      onAssignmentDetails?.call(assignment);
                    }
                    return false;
                  },
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 16),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text('Начать',
                        style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700)),
                  ),
                  secondaryBackground: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text('Детали',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700)),
                  ),
                  child: card,
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({
    required this.items,
    required this.onItemTap,
  });

  final List<RecentItem> items;
  final void Function(RecentItem item) onItemTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Недавно открытые',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return ActionChip(
                  avatar: const Icon(Icons.history, color: Colors.white54, size: 18),
                  label: Text(
                    item.title,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  backgroundColor: AppColors.darkSurface,
                  side: BorderSide(color: AppColors.darkPrimary.withOpacity(0.5)),
                  onPressed: () => onItemTap(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
