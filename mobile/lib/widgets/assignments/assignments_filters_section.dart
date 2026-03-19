import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class AssignmentsFiltersSection extends StatelessWidget {
  const AssignmentsFiltersSection({
    super.key,
    required this.showExpanded,
    required this.searchController,
    required this.searchQuery,
    required this.selectedStatus,
    required this.selectedAssignmentType,
    required this.selectedSort,
    required this.sortAscending,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onResetFilters,
    required this.onStatusChanged,
    required this.onAssignmentTypeChanged,
    required this.onSortChanged,
    required this.onToggleSortDirection,
  });

  final bool showExpanded;
  final TextEditingController searchController;
  final String searchQuery;
  final String selectedStatus;
  final String selectedAssignmentType;
  final String selectedSort;
  final bool sortAscending;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onResetFilters;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onAssignmentTypeChanged;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onToggleSortDirection;

  @override
  Widget build(BuildContext context) {
    if (showExpanded) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: AppColors.darkSurface,
        child: Column(
          children: [
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Поиск по коду, названию, предприятию...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        tooltip: 'Очистить поиск',
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.close, color: Colors.grey),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.darkBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[700]!),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onResetFilters,
                icon: const Icon(Icons.restart_alt, color: Colors.white70),
                label: const Text(
                  'Сбросить фильтры',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _AssignmentsStatusSegments(
                    selectedStatus: selectedStatus,
                    onStatusChanged: onStatusChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Тип:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: selectedAssignmentType,
                    isExpanded: true,
                    dropdownColor: AppColors.darkSurface,
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Все типы')),
                      DropdownMenuItem(value: 'DIAGNOSTICS', child: Text('DIAGNOSTICS')),
                      DropdownMenuItem(value: 'INSPECTION', child: Text('INSPECTION')),
                      DropdownMenuItem(value: 'EXPERTISE', child: Text('EXPERTISE')),
                    ],
                    onChanged: (value) {
                      if (value != null) onAssignmentTypeChanged(value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Сортировка:',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: selectedSort,
                    isExpanded: true,
                    dropdownColor: AppColors.darkSurface,
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 'due_date', child: Text('По сроку')),
                      DropdownMenuItem(value: 'priority', child: Text('По приоритету')),
                      DropdownMenuItem(value: 'created_at', child: Text('По дате создания')),
                      DropdownMenuItem(value: 'equipment_name', child: Text('По названию')),
                    ],
                    onChanged: (value) {
                      if (value != null) onSortChanged(value);
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(
                    sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    color: Colors.white70,
                  ),
                  onPressed: onToggleSortDirection,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      color: AppColors.darkSurface,
      child: Row(
        children: [
          Expanded(
            child: _AssignmentsStatusSegments(
              selectedStatus: selectedStatus,
              onStatusChanged: onStatusChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentsStatusSegments extends StatelessWidget {
  const _AssignmentsStatusSegments({
    required this.selectedStatus,
    required this.onStatusChanged,
  });

  final String selectedStatus;
  final ValueChanged<String> onStatusChanged;

  static const List<ButtonSegment<String>> _segments = [
    ButtonSegment(value: 'all', label: Text('Все')),
    ButtonSegment(value: 'PENDING', label: Text('Ожидает')),
    ButtonSegment(value: 'IN_PROGRESS', label: Text('В работе')),
    ButtonSegment(value: 'COMPLETED', label: Text('Завершено')),
  ];

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: _segments,
      selected: {selectedStatus},
      onSelectionChanged: (Set<String> newSelection) {
        onStatusChanged(newSelection.first);
      },
    );
  }
}
