import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/assignment.dart';
import '../models/equipment.dart';
import '../data/technical_report_form_registry.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/recent_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../widgets/assignments/assignment_dialogs.dart';
import '../widgets/assignments/assignment_group.dart';
import '../widgets/assignments/assignments_flat_list.dart';
import '../widgets/assignments/assignments_grouped_list.dart';
import 'custom_protocol_screen.dart';

enum _AssignmentEntryChoice { template, inspection, cancel }

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen>
    with SingleTickerProviderStateMixin {
  static const String _prefsFilterStatus = 'assignments_filter_status';
  static const String _prefsFilterSort = 'assignments_filter_sort';
  static const String _prefsFilterAsc = 'assignments_filter_asc';
  static const String _prefsFilterAssignmentType = 'assignments_filter_assignment_type';
  static const String _prefsFilterSearch = 'assignments_filter_search';
  static const String _prefsViewMode = 'assignments_view_mode_grouped';

  late final TabController _tabController;

  static const List<_StatusTab> _tabs = [
    _StatusTab('all', 'Все', null),
    _StatusTab('PENDING', 'Ожидает', AppColors.warning),
    _StatusTab('IN_PROGRESS', 'В работе', AppColors.accent),
    _StatusTab('COMPLETED', 'Завершено', AppColors.success),
  ];

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

  /// Вид списка: false — обычный список, true — выпадающие группы по предприятиям
  bool _groupByEnterprise = false;
  final Map<String, bool> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final tab = _tabs[_tabController.index];
        _onStatusChanged(tab.value);
      }
    });
    _restoreFilterAndLoad();
    _loadRecent();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      final savedStatus = prefs.getString(_prefsFilterStatus) ?? 'all';
      setState(() {
        _selectedStatus = savedStatus;
        _selectedSort = prefs.getString(_prefsFilterSort) ?? 'due_date';
        _sortAscending = prefs.getBool(_prefsFilterAsc) ?? false;
        _selectedAssignmentType =
            prefs.getString(_prefsFilterAssignmentType) ?? 'all';
        _searchQuery = prefs.getString(_prefsFilterSearch) ?? '';
        _groupByEnterprise = prefs.getBool(_prefsViewMode) ?? false;
      });
      _searchController.text = _searchQuery;
      // Синхронизировать TabController с сохранённым статусом
      final tabIdx = _tabs.indexWhere((t) => t.value == savedStatus);
      if (tabIdx >= 0) _tabController.animateTo(tabIdx);
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
      await prefs.setBool(_prefsViewMode, _groupByEnterprise);
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

  Future<void> _openInspectionScreen({
    required Equipment equipment,
    required String assignmentId,
    String? existingInspectionId,
    required String assignmentType,
    String? initialReportFormId,
  }) async {
    // Если форма ТО уже задана в задании — не спрашиваем повторно
    if (initialReportFormId != null && initialReportFormId.trim().isNotEmpty) {
      final inspectionType =
          TechnicalReportFormRegistry.inspectionTypeFromAssignment(
              assignmentType);
      if (!mounted) return;
      await context.push('/inspection', extra: {
        'equipment': equipment,
        'assignmentId': assignmentId,
        'existingInspectionId': existingInspectionId,
        'inspectionType': inspectionType,
        'reportFormId': initialReportFormId.trim(),
      });
      return;
    }
    final selection = await showTechnicalReportFormSelectDialog(
      context,
      equipment: equipment,
      assignmentType: assignmentType,
      initialFormId: initialReportFormId,
    );
    if (!mounted || selection == null) return;
    await context.push('/inspection', extra: {
      'equipment': equipment,
      'assignmentId': assignmentId,
      'existingInspectionId': existingInspectionId,
      'inspectionType': selection.inspectionType,
      'reportFormId': selection.reportFormId,
    });
  }

  Future<_AssignmentEntryChoice?> _promptAssignmentEntry(Assignment assignment) async {
    final name = assignment.protocolTemplateName;
    return showDialog<_AssignmentEntryChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text(
          'Шаблон задания',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          name != null && name.isNotEmpty
              ? 'К заданию привязан шаблон: $name. Что открыть?'
              : 'К заданию привязан обязательный шаблон протокола. Что открыть?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _AssignmentEntryChoice.cancel),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, _AssignmentEntryChoice.inspection),
            child: const Text('Акт ТД / обследование'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, _AssignmentEntryChoice.template),
            child: const Text('По шаблону'),
          ),
        ],
      ),
    );
  }

  Future<void> _openMandatoryTemplate(Assignment assignment) async {
    final tid = assignment.protocolTemplateId;
    if (tid == null || tid.isEmpty) return;
    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) =>
              const Center(child: CircularProgressIndicator()),
        );
      }
      final raw = await _apiService.getProtocolTemplateById(tid);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      final tpl = Map<String, dynamic>.from(raw);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CustomProtocolScreen(
            template: tpl,
            assignmentId: assignment.id,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось открыть шаблон: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openInspectionAfterTemplateChoice({
    required Assignment assignment,
    required Equipment equipment,
    String? existingInspectionId,
  }) async {
    if (assignment.protocolTemplateId != null &&
        assignment.protocolTemplateId!.trim().isNotEmpty) {
      final choice = await _promptAssignmentEntry(assignment);
      if (!mounted) return;
      if (choice == null || choice == _AssignmentEntryChoice.cancel) return;
      if (choice == _AssignmentEntryChoice.template) {
        await _openMandatoryTemplate(assignment);
        return;
      }
    }
    await _openInspectionScreen(
      equipment: equipment,
      assignmentId: assignment.id,
      existingInspectionId: existingInspectionId,
      assignmentType: assignment.assignmentType,
      initialReportFormId: assignment.reportFormId,
    );
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

  /// Группировка заданий по предприятиям (для выпадающего списка).
  /// Филиал/цех/ОПО выводятся в заголовке группы, только если они
  /// одинаковы у всех заданий группы.
  List<AssignmentGroup> _groupAssignments(List<Assignment> assignments) {
    final Map<String, List<Assignment>> groups = {};

    for (final assignment in assignments) {
      final key = (assignment.enterpriseName?.isNotEmpty ?? false)
          ? assignment.enterpriseName!
          : 'Без предприятия';
      groups.putIfAbsent(key, () => []).add(assignment);
    }

    return groups.entries.map((entry) {
      final list = entry.value;
      final first = list.first;

      String? uniform(String? Function(Assignment a) pick) {
        final v = pick(first);
        if (v == null || v.isEmpty) return null;
        return list.every((a) => pick(a) == v) ? v : null;
      }

      return AssignmentGroup(
        enterpriseName: first.enterpriseName,
        branchName: uniform((a) => a.branchName),
        workshopName: uniform((a) => a.workshopName),
        opoName: uniform((a) => a.opoName),
        assignments: list,
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
                await _openInspectionAfterTemplateChoice(
                  assignment: assignment,
                  equipment: eq,
                  existingInspectionId: existingInspection['id'] as String,
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
                await _openInspectionAfterTemplateChoice(
                  assignment: assignment,
                  equipment: eq,
                );
                _loadAssignments();
                _loadRecent();
              }
            }
          } catch (e) {
            if (mounted) {
              await _openInspectionAfterTemplateChoice(
                assignment: assignment,
                equipment: eq,
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
            await _openInspectionAfterTemplateChoice(
              assignment: assignment,
              equipment: eq,
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
        await _openInspectionAfterTemplateChoice(
          assignment: assignment,
          equipment: resolvedEquipment,
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
    Assignment? asg;
    try {
      asg = _assignments.firstWhere((a) => a.id == item.assignmentId);
    } catch (_) {
      asg = null;
    }
    if (asg != null) {
      await _openInspectionAfterTemplateChoice(
        assignment: asg,
        equipment: equipment,
      );
    } else {
      await _openInspectionScreen(
        equipment: equipment,
        assignmentId: item.assignmentId,
        assignmentType: 'DIAGNOSTICS',
      );
    }
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
    final pending = _assignments.where((a) => a.status == 'PENDING').length;
    final inProgress = _assignments.where((a) => a.status == 'IN_PROGRESS').length;
    final completed = _assignments.where((a) => a.status == 'COMPLETED').length;
    final counts = [_assignments.length, pending, inProgress, completed];

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Задания',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            if (_filteredAssignments.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.darkBorder,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_filteredAssignments.length}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: AppColors.darkBackgroundDeep,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: Column(
            children: [
              // Строка поиска — всегда видна
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Поиск по коду, названию, предприятию…',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                            onPressed: _onClearSearch,
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.darkSurface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.darkBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.darkBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              // Вкладки статусов
              TabBar(
                controller: _tabController,
                isScrollable: false,
                labelColor: AppColors.accent,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.accent,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorWeight: 2,
                dividerColor: AppColors.darkBorder,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 12),
                tabs: List.generate(_tabs.length, (i) {
                  final tab = _tabs[i];
                  final cnt = counts[i];
                  return Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tab.color != null)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(
                              color: tab.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Text(tab.label),
                        if (cnt > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.darkBorder,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$cnt',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        actions: [
          // Переключатель вида: список / группы по предприятиям
          IconButton(
            icon: Icon(
              _groupByEnterprise
                  ? Icons.view_list_outlined
                  : Icons.folder_copy_outlined,
              size: 20,
            ),
            tooltip: _groupByEnterprise
                ? 'Обычный список'
                : 'Группировка по предприятиям',
            onPressed: () {
              setState(() => _groupByEnterprise = !_groupByEnterprise);
              _saveFilterToPrefs();
            },
          ),
          // Быстрая сортировка
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, size: 20),
            tooltip: 'Сортировка',
            color: AppColors.darkSurface,
            itemBuilder: (_) => [
              _sortItem('due_date', 'По сроку', Icons.calendar_today_outlined),
              _sortItem('priority', 'По приоритету', Icons.flag_outlined),
              _sortItem('created_at', 'По дате создания', Icons.access_time),
              _sortItem('equipment_name', 'По оборудованию', Icons.precision_manufacturing_outlined),
            ],
            onSelected: (v) {
              if (_selectedSort == v) {
                setState(() {
                  _sortAscending = !_sortAscending;
                  _filterAssignments();
                });
              } else {
                setState(() {
                  _selectedSort = v;
                  _filterAssignments();
                });
              }
              _saveFilterToPrefs();
            },
          ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                    ),
                  )
                : const Icon(Icons.sync, size: 20),
            onPressed: _isSyncing ? null : _syncAssignments,
            tooltip: 'Синхронизировать',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredAssignments.isEmpty && _recentItems.isEmpty
              ? _buildEmpty()
              : _groupByEnterprise
                  ? _buildGroupedList()
                  : AssignmentsFlatList(
                      assignments: _filteredAssignments,
                      recentItems: _recentItems,
                      localInspectionState: _localInspectionState,
                      opoHasData: _opoHasData,
                      formatDate: _formatDate,
                      onAssignmentTap: _startAssignment,
                      onRecentItemTap: _openRecentItem,
                      onAssignmentsReload: _loadAssignments,
                    ),
    );
  }

  Widget _buildGroupedList() {
    final groups = _groupAssignments(_filteredAssignments);
    // По умолчанию группы свёрнуты — компактный выпадающий список предприятий
    final expanded = <String, bool>{
      for (final g in groups) g.key: _expandedGroups[g.key] ?? false,
    };
    return RefreshIndicator(
      onRefresh: _loadAssignments,
      child: AssignmentsGroupedList(
        groups: groups,
        recentItems: _recentItems,
        expandedGroups: expanded,
        localInspectionState: _localInspectionState,
        opoHasData: _opoHasData,
        formatDate: _formatDate,
        onExpansionChanged: (key, isExpanded) {
          _expandedGroups[key] = isExpanded;
        },
        onAssignmentTap: _startAssignment,
        onRecentItemTap: _openRecentItem,
        onAssignmentsReload: _loadAssignments,
      ),
    );
  }

  PopupMenuItem<String> _sortItem(String value, String label, IconData icon) {
    final selected = _selectedSort == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: selected ? AppColors.accent : AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.accent : Colors.white,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (selected) ...[
            const Spacer(),
            Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: AppColors.accent,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: const Icon(
              Icons.assignment_outlined,
              size: 36,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Список заданий пуст',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Нажмите иконку синхронизации вверху,\nчтобы загрузить задания с сервера',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StatusTab {
  const _StatusTab(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color? color;
}
