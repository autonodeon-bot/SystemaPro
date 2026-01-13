import 'package:flutter/material.dart';
import '../models/assignment.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import 'vessel_inspection_screen.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

// Вспомогательный класс для группировки заданий
class AssignmentGroup {
  final String? enterpriseName;
  final String? branchName;
  final String? workshopName;
  final List<Assignment> assignments;
  
  AssignmentGroup({
    this.enterpriseName,
    this.branchName,
    this.workshopName,
    required this.assignments,
  });
  
  String get key {
    return '${enterpriseName ?? 'Без предприятия'}_${branchName ?? ''}_${workshopName ?? ''}';
  }
  
  String get displayName {
    if (enterpriseName != null && enterpriseName!.isNotEmpty) {
      if (branchName != null && branchName!.isNotEmpty) {
        if (workshopName != null && workshopName!.isNotEmpty) {
          return '$enterpriseName → $branchName → $workshopName';
        }
        return '$enterpriseName → $branchName';
      }
      return enterpriseName!;
    }
    if (branchName != null && branchName!.isNotEmpty) {
      if (workshopName != null && workshopName!.isNotEmpty) {
        return '[Филиал] $branchName → $workshopName';
      }
      return '[Филиал] $branchName';
    }
    if (workshopName != null && workshopName!.isNotEmpty) {
      return '[Цех] $workshopName';
    }
    return 'Без привязки';
  }
}

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  final _apiService = ApiService();
  final _syncService = SyncService();
  final _authService = AuthService();
  List<Assignment> _assignments = [];
  List<Assignment> _filteredAssignments = [];
  Map<String, LocalAssignmentInspectionState> _localInspectionState = {};
  bool _isLoading = true;
  String _selectedStatus = 'all';
  String _selectedSort = 'due_date'; // due_date, priority, created_at, equipment_name
  bool _sortAscending = false;
  String _searchQuery = '';
  bool _isSyncing = false;
  bool _showFilters = false;
  
  // Состояние раскрытия иерархии
  final Map<String, bool> _expandedGroups = {}; // Ключ: "enterprise_branch_workshop", значение: раскрыто/свернуто

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Пытаемся загрузить с сервера
      final assignments = await _apiService.getAssignments();
      // Сохраняем локально для офлайн-режима
      await _syncService.saveAssignmentsOffline(assignments);
      setState(() {
        _assignments = assignments;
        _isLoading = false;
      });
      await _refreshLocalInspectionState(assignments);
      _filterAssignments();
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('AUTH_INVALID') ||
          msg.contains('Invalid authentication credentials') ||
          msg.contains('401')) {
        await _authService.logout();
        try {
          await SyncService().clearOfflineCache();
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сессия истекла или токен недействителен. Войдите заново.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        return;
      }
      // Если не удалось загрузить с сервера, используем локальное хранилище
      try {
        final offlineAssignments = await _syncService.getOfflineAssignments();
        setState(() {
          _assignments = offlineAssignments;
          _isLoading = false;
        });
        await _refreshLocalInspectionState(offlineAssignments);
        _filterAssignments();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Используются сохраненные данные. Ошибка: $e'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (offlineError) {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки заданий: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _syncAssignments() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      final assignments = await _apiService.getAssignments();
      await _syncService.saveAssignmentsOffline(assignments);
      
      // Также синхронизируем оборудование из заданий (MERGE внутри saveEquipmentOffline)
      for (var assignment in assignments) {
        try {
          final equipment = await _apiService.getAssignmentEquipment(assignment.id);
          await _syncService.saveEquipmentOffline([equipment]);
        } catch (e) {
          // Игнорируем ошибки получения оборудования
        }
      }

      setState(() {
        _assignments = assignments;
        _isSyncing = false;
      });
      await _refreshLocalInspectionState(assignments);
      _filterAssignments();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Синхронизация завершена'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('AUTH_INVALID') ||
          msg.contains('Invalid authentication credentials') ||
          msg.contains('401')) {
        await _authService.logout();
        try {
          await SyncService().clearOfflineCache();
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сессия истекла или токен недействителен. Войдите заново.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        return;
      }
      setState(() {
        _isSyncing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка синхронизации: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _refreshLocalInspectionState(List<Assignment> assignments) async {
    try {
      final ids = assignments.map((a) => a.id).toList();
      final st = await _syncService.getLocalAssignmentInspectionState(ids);
      if (!mounted) return;
      setState(() {
        _localInspectionState = st;
      });
    } catch (_) {
      // Игнорируем
    }
  }

  Widget _buildSyncBadges(Assignment assignment) {
    final local = _localInspectionState[assignment.id] ?? LocalAssignmentInspectionState.none();
    final chips = <Widget>[];

    if (local.hasDraft) {
      chips.add(_chip('Черновик (локально)', Colors.orange));
    }
    if (local.hasSigned) {
      chips.add(_chip('Подписано (локально)', const Color(0xFF3b82f6)));
    }
    if (assignment.status == 'COMPLETED') {
      chips.add(_chip('На сервере', Colors.green));
    } else if (local.hasSigned) {
      chips.add(_chip('Ожидает синхронизации', Colors.purple));
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

  Widget _chip(String text, Color color) {
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

  // Группировка заданий по иерархии
  List<AssignmentGroup> _groupAssignments(List<Assignment> assignments) {
    final Map<String, List<Assignment>> groups = {};
    
    for (final assignment in assignments) {
      final key = '${assignment.enterpriseName ?? 'Без предприятия'}_${assignment.branchName ?? ''}_${assignment.workshopName ?? ''}';
      if (!groups.containsKey(key)) {
        groups[key] = [];
      }
      groups[key]!.add(assignment);
    }
    
    return groups.entries.map((entry) {
      final firstAssignment = entry.value.first;
      return AssignmentGroup(
        enterpriseName: firstAssignment.enterpriseName,
        branchName: firstAssignment.branchName,
        workshopName: firstAssignment.workshopName,
        assignments: entry.value,
      );
    }).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }
  
  void _filterAssignments() {
    List<Assignment> filtered = _assignments;
    
    // Фильтр по статусу
    if (_selectedStatus != 'all') {
      filtered = filtered.where((a) => a.status == _selectedStatus).toList();
    }
    
    // Поиск
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((a) {
        return a.equipmentCode.toLowerCase().contains(query) ||
               a.equipmentName.toLowerCase().contains(query) ||
               (a.enterpriseName?.toLowerCase().contains(query) ?? false) ||
               (a.branchName?.toLowerCase().contains(query) ?? false) ||
               (a.workshopName?.toLowerCase().contains(query) ?? false);
      }).toList();
    }
    
    // Сортировка
    filtered.sort((a, b) {
      int comparison = 0;
      switch (_selectedSort) {
        case 'due_date':
          final aDate = a.dueDate ?? DateTime(2100);
          final bDate = b.dueDate ?? DateTime(2100);
          comparison = aDate.compareTo(bDate);
          break;
        case 'priority':
          final priorityOrder = {'URGENT': 4, 'HIGH': 3, 'NORMAL': 2, 'LOW': 1};
          final aPriority = priorityOrder[a.priority] ?? 0;
          final bPriority = priorityOrder[b.priority] ?? 0;
          comparison = bPriority.compareTo(aPriority);
          break;
        case 'created_at':
          comparison = a.createdAt.compareTo(b.createdAt);
          break;
        case 'equipment_name':
          comparison = a.equipmentName.compareTo(b.equipmentName);
          break;
        default:
          comparison = 0;
      }
      return _sortAscending ? comparison : -comparison;
    });
    
    setState(() {
      _filteredAssignments = filtered;
    });
  }

  Color _getStatusColor(String status) {
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

  Color _getPriorityColor(String priority) {
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

  Future<void> _startAssignment(Assignment assignment) async {
    try {
      // Показываем индикатор загрузки
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }
      
      // Обновляем статус задания на "В работе"
      await _apiService.updateAssignmentStatus(assignment.id, 'IN_PROGRESS');
      
      // Получаем информацию об оборудовании
      final equipment = await _apiService.getAssignmentEquipment(assignment.id);
      
      // Проверяем, что оборудование получено корректно
      if (equipment.id.isEmpty) {
        throw Exception('Не удалось загрузить информацию об оборудовании');
      }
      
      // Сохраняем оборудование локально
      await _syncService.saveEquipmentOffline([equipment]);

      // Закрываем индикатор загрузки
      if (mounted) {
        Navigator.of(context).pop(); // Закрываем диалог загрузки
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VesselInspectionScreen(
              equipment: equipment,
              assignmentId: assignment.id,
            ),
          ),
        ).then((_) {
          // Обновляем список заданий после возврата
          _loadAssignments();
        }).catchError((error) {
          // Обработка ошибок навигации
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка открытия экрана обследования: $error'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
      }
    } catch (e) {
      // Закрываем индикатор загрузки в случае ошибки
      if (mounted) {
        Navigator.of(context).pop(); // Закрываем диалог загрузки, если он открыт
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: const Text('Мои задания'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_list : Icons.filter_list_off),
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
            tooltip: 'Фильтры',
          ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.sync),
            onPressed: _isSyncing ? null : _syncAssignments,
            tooltip: 'Синхронизировать',
          ),
        ],
      ),
      body: Column(
        children: [
          // Расширенные фильтры
          if (_showFilters)
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF1e293b),
              child: Column(
                children: [
                  // Поиск
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Поиск по коду, названию, предприятию...',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF0f172a),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    style: const TextStyle(color: Colors.white),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _filterAssignments();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  // Фильтр по статусу
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'all', label: Text('Все')),
                            ButtonSegment(value: 'PENDING', label: Text('Ожидает')),
                            ButtonSegment(value: 'IN_PROGRESS', label: Text('В работе')),
                            ButtonSegment(value: 'COMPLETED', label: Text('Завершено')),
                          ],
                          selected: {_selectedStatus},
                          onSelectionChanged: (Set<String> newSelection) {
                            setState(() {
                              _selectedStatus = newSelection.first;
                              _filterAssignments();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Сортировка
                  Row(
                    children: [
                      const Text('Сортировка:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          value: _selectedSort,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1e293b),
                          style: const TextStyle(color: Colors.white),
                          items: const [
                            DropdownMenuItem(value: 'due_date', child: Text('По сроку')),
                            DropdownMenuItem(value: 'priority', child: Text('По приоритету')),
                            DropdownMenuItem(value: 'created_at', child: Text('По дате создания')),
                            DropdownMenuItem(value: 'equipment_name', child: Text('По названию')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedSort = value;
                                _filterAssignments();
                              });
                            }
                          },
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                          color: Colors.white70,
                        ),
                        onPressed: () {
                          setState(() {
                            _sortAscending = !_sortAscending;
                            _filterAssignments();
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          // Фильтр по статусу (компактный вид)
          if (!_showFilters)
            Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xFF1e293b),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('Все')),
                        ButtonSegment(value: 'PENDING', label: Text('Ожидает')),
                        ButtonSegment(value: 'IN_PROGRESS', label: Text('В работе')),
                        ButtonSegment(value: 'COMPLETED', label: Text('Завершено')),
                      ],
                      selected: {_selectedStatus},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _selectedStatus = newSelection.first;
                          _filterAssignments();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          // Список заданий
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredAssignments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.assignment_outlined,
                              size: 64,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Нет заданий',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Нажмите кнопку синхронизации для загрузки заданий',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAssignments,
                        child: _buildHierarchicalList(),
                      ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHierarchicalList() {
    final groups = _groupAssignments(_filteredAssignments);
    
    if (groups.isEmpty) {
      return const Center(
        child: Text(
          'Нет заданий',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final group = groups[groupIndex];
        final groupKey = group.key;
        final isExpanded = _expandedGroups[groupKey] ?? true; // По умолчанию раскрыто
        
        return Card(
          color: const Color(0xFF1e293b),
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            key: Key(groupKey),
            initiallyExpanded: isExpanded,
            onExpansionChanged: (expanded) {
              setState(() {
                _expandedGroups[groupKey] = expanded;
              });
            },
            title: Row(
              children: [
                Icon(
                  Icons.folder,
                  color: Colors.blue[300],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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
            children: group.assignments.map((assignment) {
              return Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Card(
                  color: const Color(0xFF0f172a),
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    onTap: assignment.status == 'COMPLETED' ||
                            assignment.status == 'CANCELLED'
                        ? null
                        : () => _startAssignment(assignment),
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
                                        color: Color(0xFF3b82f6),
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
                                  color: _getStatusColor(assignment.status).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  assignment.statusLabel,
                                  style: TextStyle(
                                    color: _getStatusColor(assignment.status),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.assignment, size: 14, color: Colors.grey[400]),
                              const SizedBox(width: 4),
                              Text(
                                assignment.typeLabel,
                                style: TextStyle(color: Colors.grey[300], fontSize: 12),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getPriorityColor(assignment.priority).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  assignment.priority,
                                  style: TextStyle(
                                    color: _getPriorityColor(assignment.priority),
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          _buildSyncBadges(assignment),
                          if (assignment.dueDate != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 14,
                                  color: assignment.dueDate!.isBefore(DateTime.now()) && assignment.status != 'COMPLETED'
                                      ? Colors.red
                                      : Colors.grey[400],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Срок: ${assignment.dueDate!.day}.${assignment.dueDate!.month}.${assignment.dueDate!.year}',
                                  style: TextStyle(
                                    color: assignment.dueDate!.isBefore(DateTime.now()) && assignment.status != 'COMPLETED'
                                        ? Colors.red
                                        : Colors.grey[300],
                                    fontSize: 11,
                                    fontWeight: assignment.dueDate!.isBefore(DateTime.now()) && assignment.status != 'COMPLETED'
                                        ? FontWeight.bold
                                        : FontWeight.normal,
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
            }).toList(),
          ),
        );
      },
    );
  }
}

