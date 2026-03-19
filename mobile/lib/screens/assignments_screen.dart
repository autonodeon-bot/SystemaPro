import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/assignment.dart';
import '../models/equipment.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/recent_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../widgets/assignments/assignment_dialogs.dart';
import '../widgets/assignments/assignment_group.dart';
import '../widgets/assignments/assignments_filters_section.dart';
import '../widgets/assignments/assignments_grouped_list.dart';

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  static const String _prefsFilterStatus = 'assignments_filter_status';
  static const String _prefsFilterSort = 'assignments_filter_sort';
  static const String _prefsFilterAsc = 'assignments_filter_asc';
  static const String _prefsFilterAssignmentType = 'assignments_filter_assignment_type';
  static const String _prefsFilterSearch = 'assignments_filter_search';

  final _apiService = ApiService();
  final _syncService = SyncService();
  final _authService = AuthService();
  final _recentService = RecentService();
  final TextEditingController _searchController = TextEditingController();
  List<Assignment> _assignments = [];
  List<Assignment> _filteredAssignments = [];
  List<RecentItem> _recentItems = [];
  Map<String, LocalAssignmentInspectionState> _localInspectionState = {};
  final Map<String, bool> _opoHasData = {};
  bool _isLoading = true;
  String _selectedStatus = 'all';
  String _selectedAssignmentType = 'all';
  String _selectedSort = 'due_date';
  bool _sortAscending = false;
  String _searchQuery = '';
  bool _isSyncing = false;
  bool _showFilters = false;

  final Map<String, bool> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _restoreFilterAndLoad();
    _loadRecent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final list = await _recentService.getRecent();
    if (!mounted) return;
    setState(() {
      _recentItems = list;
    });
  }

  Future<void> _restoreFilterAndLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _selectedStatus = prefs.getString(_prefsFilterStatus) ?? 'all';
        _selectedSort = prefs.getString(_prefsFilterSort) ?? 'due_date';
        _sortAscending = prefs.getBool(_prefsFilterAsc) ?? false;
        _selectedAssignmentType =
            prefs.getString(_prefsFilterAssignmentType) ?? 'all';
        _searchQuery = prefs.getString(_prefsFilterSearch) ?? '';
      });
      _searchController.text = _searchQuery;
    } catch (_) {}
    await _loadAssignments();
  }

  Future<void> _saveFilterToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsFilterStatus, _selectedStatus);
      await prefs.setString(_prefsFilterSort, _selectedSort);
      await prefs.setBool(_prefsFilterAsc, _sortAscending);
      await prefs.setString(_prefsFilterAssignmentType, _selectedAssignmentType);
      await prefs.setString(_prefsFilterSearch, _searchQuery);
    } catch (_) {}
  }

  String _formatDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd.$mm.${date.year}';
  }

  Future<void> _resetFilters() async {
    setState(() {
      _selectedStatus = 'all';
      _selectedAssignmentType = 'all';
      _selectedSort = 'due_date';
      _sortAscending = false;
      _searchQuery = '';
      _searchController.clear();
      _filterAssignments();
    });
    await _saveFilterToPrefs();
  }

  String _defaultInspectionTypeFromAssignment(String assignmentType) {
    switch (assignmentType.toUpperCase()) {
      case 'EXPERTISE':
        return 'EXPERTISE';
      case 'INSPECTION':
        return 'VISUAL';
      case 'DIAGNOSTICS':
      default:
        return 'NDT';
    }
  }

  Future<void> _openInspectionScreen({
    required Equipment equipment,
    required String assignmentId,
    String? existingInspectionId,
    required String assignmentType,
  }) async {
    final selectedType = await showInspectionTypeSelectDialog(
      context,
      initialType: _defaultInspectionTypeFromAssignment(assignmentType),
    );
    if (!mounted || selectedType == null) return;
    await context.push('/inspection', extra: {
      'equipment': equipment,
      'assignmentId': assignmentId,
      'existingInspectionId': existingInspectionId,
      'inspectionType': selectedType,
    });
  }

  Future<void> _loadAssignments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final assignments = await _apiService.getAssignments();
      await _syncService.saveAssignmentsOffline(assignments);
      setState(() {
        _assignments = assignments;
        _isLoading = false;
      });
      await _refreshLocalInspectionState(assignments);
      await _refreshOpoSurveyState(assignments);
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
        context.go('/login');
        return;
      }
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
            const SnackBar(
              content: Text(
                  'Режим офлайн: загружены сохранённые задания. При появлении интернета выполните синхронизацию.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
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

  Future<void> _refreshOpoSurveyState(List<Assignment> assignments) async {
    try {
      final opoIds = assignments
          .map((a) => a.opoId)
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      if (opoIds.isEmpty) return;

      try {
        final pending = await _syncService.getPendingOpoSurveys();
        for (final p in pending) {
          final id = p['opo_id']?.toString();
          if (id != null && id.isNotEmpty) {
            _opoHasData[id] = true;
          }
        }
      } catch (_) {}

      for (final id in opoIds) {
        if (_opoHasData[id] == true) continue;
        try {
          final resp = await _apiService.getOpoSurvey(id);
          final data = resp['survey_data'];
          bool has = false;
          if (data is Map) {
            final m = Map<String, dynamic>.from(data);
            if ((m['organization']?.toString().trim().isNotEmpty ?? false) ||
                (m['executors']?.toString().trim().isNotEmpty ?? false)) {
              has = true;
            }
            final docs = m['documents'];
            if (docs is Map) {
              for (final e in docs.entries) {
                if (e.value == true) {
                  has = true;
                  break;
                }
              }
            }
          }
          _opoHasData[id] = has;
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {});
    } catch (_) {}
  }

  Future<void> _syncAssignments() async {
    final hasConnection = await _apiService.checkConnection();
    if (!hasConnection) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет интернета. Подключитесь к сети и повторите.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final assignments = await _apiService.getAssignments();
      await _syncService.saveAssignmentsOffline(assignments);

      for (var assignment in assignments) {
        try {
          final equipment = await _apiService.getAssignmentEquipment(assignment.id);
          await _syncService.saveEquipmentOffline([equipment]);
        } catch (e) {}
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
        context.go('/login');
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
    } catch (_) {}
  }

  List<AssignmentGroup> _groupAssignments(List<Assignment> assignments) {
    final Map<String, List<Assignment>> groups = {};

    for (final assignment in assignments) {
      final key =
          '${assignment.enterpriseName ?? 'Без предприятия'}_${assignment.branchName ?? ''}_${assignment.workshopName ?? ''}_${assignment.opoName ?? ''}';
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
        opoName: firstAssignment.opoName,
        assignments: entry.value,
      );
    }).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  void _filterAssignments() {
    List<Assignment> filtered = _assignments;

    if (_selectedStatus != 'all') {
      filtered = filtered.where((a) => a.status == _selectedStatus).toList();
    }
    if (_selectedAssignmentType != 'all') {
      filtered = filtered.where((a) => a.assignmentType == _selectedAssignmentType).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((a) {
        return a.equipmentCode.toLowerCase().contains(query) ||
            a.equipmentName.toLowerCase().contains(query) ||
            (a.enterpriseName?.toLowerCase().contains(query) ?? false) ||
            (a.branchName?.toLowerCase().contains(query) ?? false) ||
            (a.workshopName?.toLowerCase().contains(query) ?? false) ||
            (a.opoName?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

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

  Future<void> _startAssignment(Assignment assignment) async {
    try {
      if (assignment.status == 'COMPLETED') {
        final choice = await showCompletedAssignmentChoiceDialog(context);

        if (choice == null) return;

        Equipment? equipment;
        try {
          equipment = await _apiService.getAssignmentEquipment(assignment.id);
          if (equipment.id.isEmpty) equipment = null;
        } catch (e) {
          final msg = e.toString().toLowerCase();
          if (msg.contains('токен авторизации не найден') ||
              msg.contains('socketexception') ||
              msg.contains('failed host lookup')) {
            final offlineList = await _syncService.getOfflineEquipment();
            try {
              equipment = offlineList.firstWhere((e) => e.id == assignment.equipmentId);
            } catch (_) {
              equipment = null;
            }
          }
        }
        if (equipment == null || equipment.id.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Не удалось загрузить информацию об оборудовании. Проверьте сеть или загрузите задания при интернете.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        final eq = equipment;
        await _syncService.saveEquipmentOffline([eq]);

        if (choice == 'edit') {
          try {
            final inspections = await _apiService.getInspections(eq.id);
            Map<String, dynamic>? existingInspection;
            for (var insp in inspections) {
              final data = insp['data'] as Map<String, dynamic>?;
              if (data != null) {
                final assignmentIdInData = data['assignment_id'] as String?;
                if (assignmentIdInData == assignment.id) {
                  existingInspection = insp;
                  break;
                }
              }
            }

            if (existingInspection != null) {
              if (mounted) {
                _recentService.addRecent(
                  assignmentId: assignment.id,
                  equipmentId: eq.id,
                  title: assignment.equipmentName,
                );
                await _openInspectionScreen(
                  equipment: eq,
                  assignmentId: assignment.id,
                  existingInspectionId: existingInspection['id'] as String,
                  assignmentType: assignment.assignmentType,
                );
                _loadAssignments();
                _loadRecent();
              }
            } else {
              if (mounted) {
                _recentService.addRecent(
                  assignmentId: assignment.id,
                  equipmentId: eq.id,
                  title: assignment.equipmentName,
                );
                await _openInspectionScreen(
                  equipment: eq,
                  assignmentId: assignment.id,
                  assignmentType: assignment.assignmentType,
                );
                _loadAssignments();
                _loadRecent();
              }
            }
          } catch (e) {
            if (mounted) {
              await _openInspectionScreen(
                equipment: eq,
                assignmentId: assignment.id,
                assignmentType: assignment.assignmentType,
              );
              _loadAssignments();
              _loadRecent();
              _recentService.addRecent(
                assignmentId: assignment.id,
                equipmentId: eq.id,
                title: assignment.equipmentName,
              );
            }
          }
        } else if (choice == 'restart') {
          if (mounted) {
            await _openInspectionScreen(
              equipment: eq,
              assignmentId: assignment.id,
              assignmentType: assignment.assignmentType,
            );
            _loadAssignments();
            _loadRecent();
            _recentService.addRecent(
              assignmentId: assignment.id,
              equipmentId: eq.id,
              title: assignment.equipmentName,
            );
          }
        }
        return;
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      bool usedOffline = false;
      Equipment? equipment;

      try {
        if (assignment.status != 'COMPLETED') {
          await _apiService.updateAssignmentStatus(assignment.id, 'IN_PROGRESS');
        }
        equipment = await _apiService.getAssignmentEquipment(assignment.id);
        if (equipment.id.isNotEmpty) {
          await _syncService.saveEquipmentOffline([equipment]);
        }
      } catch (e) {
        final msg = e.toString().toLowerCase();
        final isNetworkError = msg.contains('socketexception') ||
            msg.contains('clientexception') ||
            msg.contains('network is unreachable') ||
            msg.contains('нет подключения') ||
            msg.contains('failed host lookup') ||
            msg.contains('connection failed');
        final isOfflineNoToken = msg.contains('токен авторизации не найден') ||
            msg.contains('токен авторизации отсутствует');
        if (isNetworkError || isOfflineNoToken) {
          final offlineList = await _syncService.getOfflineEquipment();
          try {
            equipment = offlineList.firstWhere((e) => e.id == assignment.equipmentId);
          } catch (_) {
            equipment = null;
          }
          if (equipment != null) {
            usedOffline = true;
          }
        }
        if (equipment == null) {
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  (isNetworkError || isOfflineNoToken)
                      ? 'Нет сети. Оборудование по заданию не найдено в кэше — загрузите задания при интернете.'
                      : 'Ошибка: $e',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
      }

      final resolvedEquipment = equipment;
      if (resolvedEquipment.id.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось загрузить информацию об оборудовании'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (mounted) {
        if (usedOffline) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Режим офлайн: работа с сохранёнными данными. При появлении интернета выполните синхронизацию.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        _recentService.addRecent(
          assignmentId: assignment.id,
          equipmentId: resolvedEquipment.id,
          title: assignment.equipmentName,
        );
        await _openInspectionScreen(
          equipment: resolvedEquipment,
          assignmentId: assignment.id,
          assignmentType: assignment.assignmentType,
        );
        _loadAssignments();
        _loadRecent();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
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

  Future<void> _openRecentItem(RecentItem item) async {
    Equipment? equipment;
    try {
      final list = await _syncService.getOfflineEquipment();
      equipment = list.firstWhere((e) => e.id == item.equipmentId);
    } catch (_) {}
    if (equipment == null) {
      try {
        final fetched = await _apiService.getEquipmentById(item.equipmentId);
        equipment = fetched;
        await _syncService.saveEquipmentOffline([fetched]);
      } catch (_) {}
    }
    if (equipment == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Оборудование не найдено. Загрузите задания при подключении к интернету.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    await _openInspectionScreen(
      equipment: equipment,
      assignmentId: item.assignmentId,
      assignmentType: 'DIAGNOSTICS',
    );
    _loadAssignments();
    _loadRecent();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _filterAssignments();
    });
    _saveFilterToPrefs();
  }

  void _onClearSearch() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _filterAssignments();
    });
    _saveFilterToPrefs();
  }

  void _onStatusChanged(String status) {
    setState(() {
      _selectedStatus = status;
      _filterAssignments();
    });
    _saveFilterToPrefs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text('Мои задания'),
        backgroundColor: AppColors.darkBackground,
        foregroundColor: Colors.white,
        actions: [
          Semantics(
            label: 'Показать или скрыть фильтры',
            child: IconButton(
              icon: Icon(
                _showFilters ? Icons.filter_list : Icons.filter_list_off,
                semanticLabel: _showFilters ? 'Фильтры активны' : 'Фильтры скрыты',
              ),
              onPressed: () {
                setState(() {
                  _showFilters = !_showFilters;
                });
              },
              tooltip: 'Фильтры',
            ),
          ),
          Semantics(
            label: 'Синхронизировать задания с сервером',
            child: IconButton(
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
          ),
        ],
      ),
      body: Column(
        children: [
          AssignmentsFiltersSection(
            showExpanded: _showFilters,
            searchController: _searchController,
            searchQuery: _searchQuery,
            selectedStatus: _selectedStatus,
            selectedAssignmentType: _selectedAssignmentType,
            selectedSort: _selectedSort,
            sortAscending: _sortAscending,
            onSearchChanged: _onSearchChanged,
            onClearSearch: _onClearSearch,
            onResetFilters: _resetFilters,
            onStatusChanged: _onStatusChanged,
            onAssignmentTypeChanged: (v) {
              setState(() {
                _selectedAssignmentType = v;
                _filterAssignments();
              });
              _saveFilterToPrefs();
            },
            onSortChanged: (v) {
              setState(() {
                _selectedSort = v;
                _filterAssignments();
              });
              _saveFilterToPrefs();
            },
            onToggleSortDirection: () {
              setState(() {
                _sortAscending = !_sortAscending;
                _filterAssignments();
              });
              _saveFilterToPrefs();
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : (_filteredAssignments.isEmpty && _recentItems.isEmpty)
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.assignment_outlined,
                              size: 64,
                              color: Colors.grey[600],
                              semanticLabel: 'Нет заданий',
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
                        child: AssignmentsGroupedList(
                          groups: _groupAssignments(_filteredAssignments),
                          recentItems: _recentItems,
                          expandedGroups: _expandedGroups,
                          localInspectionState: _localInspectionState,
                          opoHasData: _opoHasData,
                          formatDate: _formatDate,
                          onExpansionChanged: (groupKey, expanded) {
                            setState(() {
                              _expandedGroups[groupKey] = expanded;
                            });
                          },
                          onAssignmentTap: _startAssignment,
                          onRecentItemTap: _openRecentItem,
                          onAssignmentsReload: _loadAssignments,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
