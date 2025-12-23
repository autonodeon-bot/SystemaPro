import 'package:flutter/material.dart';
import '../models/assignment.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import 'vessel_inspection_screen.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

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
  bool _isLoading = true;
  String _selectedStatus = 'all';
  String _selectedSort = 'due_date'; // due_date, priority, created_at, equipment_name
  bool _sortAscending = false;
  String _searchQuery = '';
  bool _isSyncing = false;
  bool _showFilters = false;

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
      // Обновляем статус задания на "В работе"
      await _apiService.updateAssignmentStatus(assignment.id, 'IN_PROGRESS');
      
      // Получаем информацию об оборудовании
      final equipment = await _apiService.getAssignmentEquipment(assignment.id);
      
      // Сохраняем оборудование локально
      await _syncService.saveEquipmentOffline([equipment]);

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
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
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
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _filteredAssignments.length,
                          itemBuilder: (context, index) {
                            final assignment = _filteredAssignments[index];
                            return Card(
                              color: const Color(0xFF1e293b),
                              margin: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: assignment.status == 'COMPLETED' ||
                                        assignment.status == 'CANCELLED'
                                    ? null
                                    : () => _startAssignment(assignment),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
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
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                // Иерархия
                                                if (assignment.enterpriseName != null ||
                                                    assignment.branchName != null ||
                                                    assignment.workshopName != null) ...[
                                                  const SizedBox(height: 6),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 4,
                                                    children: [
                                                      if (assignment.enterpriseName != null)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.blue.withOpacity(0.2),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              const Icon(Icons.business, size: 12, color: Colors.blue),
                                                              const SizedBox(width: 4),
                                                              Text(
                                                                assignment.enterpriseName!,
                                                                style: const TextStyle(color: Colors.blue, fontSize: 10),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      if (assignment.branchName != null)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.green.withOpacity(0.2),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              const Icon(Icons.location_on, size: 12, color: Colors.green),
                                                              const SizedBox(width: 4),
                                                              Text(
                                                                assignment.branchName!,
                                                                style: const TextStyle(color: Colors.green, fontSize: 10),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      if (assignment.workshopName != null)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.purple.withOpacity(0.2),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              const Icon(Icons.build, size: 12, color: Colors.purple),
                                                              const SizedBox(width: 4),
                                                              Text(
                                                                assignment.workshopName!,
                                                                style: const TextStyle(color: Colors.purple, fontSize: 10),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _getStatusColor(
                                                      assignment.status)
                                                  .withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              assignment.statusLabel,
                                              style: TextStyle(
                                                color: _getStatusColor(
                                                    assignment.status),
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.assignment,
                                            size: 16,
                                            color: Colors.grey[400],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            assignment.typeLabel,
                                            style: TextStyle(
                                              color: Colors.grey[300],
                                              fontSize: 14,
                                            ),
                                          ),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _getPriorityColor(
                                                      assignment.priority)
                                                  .withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              assignment.priority,
                                              style: TextStyle(
                                                color: _getPriorityColor(
                                                    assignment.priority),
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (assignment.dueDate != null) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.calendar_today,
                                              size: 16,
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
                                                fontSize: 12,
                                                fontWeight: assignment.dueDate!.isBefore(DateTime.now()) && assignment.status != 'COMPLETED'
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                            if (assignment.dueDate!.isBefore(DateTime.now()) && assignment.status != 'COMPLETED')
                                              const Padding(
                                                padding: EdgeInsets.only(left: 8),
                                                child: Text(
                                                  'ПРОСРОЧЕНО!',
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                      if (assignment.description != null &&
                                          assignment.description!.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          assignment.description!,
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 12,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

