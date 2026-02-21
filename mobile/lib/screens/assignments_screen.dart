import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/assignment.dart';
import '../models/equipment.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import 'vessel_inspection_screen.dart';
import '../services/auth_service.dart';
import '../services/recent_service.dart';
import 'login_screen.dart';
import 'opo_survey_screen.dart';

// Вспомогательный класс для группировки заданий
class AssignmentGroup {
  final String? enterpriseName;
  final String? branchName;
  final String? workshopName;
  final String? opoName;
  final List<Assignment> assignments;
  
  AssignmentGroup({
    this.enterpriseName,
    this.branchName,
    this.workshopName,
    this.opoName,
    required this.assignments,
  });
  
  String get key {
    return '${enterpriseName ?? 'Без предприятия'}_${branchName ?? ''}_${workshopName ?? ''}_${opoName ?? ''}';
  }
  
  String get displayName {
    if (enterpriseName != null && enterpriseName!.isNotEmpty) {
      if (branchName != null && branchName!.isNotEmpty) {
        if (workshopName != null && workshopName!.isNotEmpty) {
          if (opoName != null && opoName!.isNotEmpty) {
            return '$enterpriseName → $branchName → $workshopName → $opoName';
          }
          return '$enterpriseName → $branchName → $workshopName';
        }
        return '$enterpriseName → $branchName';
      }
      return enterpriseName!;
    }
    if (branchName != null && branchName!.isNotEmpty) {
      if (workshopName != null && workshopName!.isNotEmpty) {
        if (opoName != null && opoName!.isNotEmpty) {
          return '[Филиал] $branchName → $workshopName → $opoName';
        }
        return '[Филиал] $branchName → $workshopName';
      }
      return '[Филиал] $branchName';
    }
    if (workshopName != null && workshopName!.isNotEmpty) {
      if (opoName != null && opoName!.isNotEmpty) {
        return '[Цех] $workshopName → $opoName';
      }
      return '[Цех] $workshopName';
    }
    if (opoName != null && opoName!.isNotEmpty) {
      return '[ОПО] $opoName';
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
  final _recentService = RecentService();
  List<Assignment> _assignments = [];
  List<Assignment> _filteredAssignments = [];
  List<RecentItem> _recentItems = [];
  Map<String, LocalAssignmentInspectionState> _localInspectionState = {};
  final Map<String, bool> _opoHasData = {}; // opo_id -> есть ли данные ОПО (локально или на сервере)
  bool _isLoading = true;
  String _selectedStatus = 'all';
  String _selectedAssignmentType = 'all';
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
    _restoreFilterAndLoad();
    _loadRecent();
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
        _selectedStatus = prefs.getString('assignments_filter_status') ?? 'all';
        _selectedSort = prefs.getString('assignments_filter_sort') ?? 'due_date';
        _sortAscending = prefs.getBool('assignments_filter_asc') ?? false;
      });
    } catch (_) {}
    await _loadAssignments();
  }

  Future<void> _saveFilterToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('assignments_filter_status', _selectedStatus);
      await prefs.setString('assignments_filter_sort', _selectedSort);
      await prefs.setBool('assignments_filter_asc', _sortAscending);
    } catch (_) {}
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

  Future<String?> _selectInspectionType({String? initialType}) async {
    String selected = initialType ?? 'NDT';
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1e293b),
          title: const Text('Тип обследования', style: TextStyle(color: Colors.white)),
          content: DropdownButtonFormField<String>(
            value: selected,
            decoration: const InputDecoration(
              labelText: 'Выберите тип',
              labelStyle: TextStyle(color: Colors.white70),
            ),
            dropdownColor: const Color(0xFF1e293b),
            items: const [
              DropdownMenuItem(value: 'VISUAL', child: Text('VISUAL', style: TextStyle(color: Colors.white))),
              DropdownMenuItem(value: 'NDT', child: Text('NDT', style: TextStyle(color: Colors.white))),
              DropdownMenuItem(value: 'QUESTIONNAIRE', child: Text('QUESTIONNAIRE', style: TextStyle(color: Colors.white))),
              DropdownMenuItem(value: 'EXPERTISE', child: Text('EXPERTISE', style: TextStyle(color: Colors.white))),
            ],
            onChanged: (v) => setInner(() => selected = v ?? selected),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Продолжить', style: TextStyle(color: Color(0xFF3b82f6))),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInspectionScreen({
    required Equipment equipment,
    required String assignmentId,
    String? existingInspectionId,
    required String assignmentType,
  }) async {
    final selectedType = await _selectInspectionType(
      initialType: _defaultInspectionTypeFromAssignment(assignmentType),
    );
    if (!mounted || selectedType == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VesselInspectionScreen(
          equipment: equipment,
          assignmentId: assignmentId,
          existingInspectionId: existingInspectionId,
          inspectionType: selectedType,
        ),
      ),
    );
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
            const SnackBar(
              content: Text('Режим офлайн: загружены сохранённые задания. При появлении интернета выполните синхронизацию.'),
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

      // 1) Локальные несинхронизированные опросники ОПО
      try {
        final pending = await _syncService.getPendingOpoSurveys();
        for (final p in pending) {
          final id = p['opo_id']?.toString();
          if (id != null && id.isNotEmpty) {
            _opoHasData[id] = true;
          }
        }
      } catch (_) {}

      // 2) Данные на сервере (подтягиваем и кэшируем)
      for (final id in opoIds) {
        if (_opoHasData[id] == true) continue; // уже знаем, что есть
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
        } catch (_) {
          // игнорируем ошибки сети
        }
      }

      if (!mounted) return;
      setState(() {});
    } catch (_) {
      // игнорируем
    }
  }

  Future<void> _syncAssignments() async {
    // Проверка доступности сети перед синхронизацией
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

    final opoId = assignment.opoId;
    if (opoId != null && opoId.isNotEmpty && (_opoHasData[opoId] == true)) {
      chips.add(_chip('ОПО заполнено', Colors.teal));
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
    
    // Фильтр по статусу
    if (_selectedStatus != 'all') {
      filtered = filtered.where((a) => a.status == _selectedStatus).toList();
    }
    // Фильтр по типу задания/обследования
    if (_selectedAssignmentType != 'all') {
      filtered = filtered.where((a) => a.assignmentType == _selectedAssignmentType).toList();
    }
    
    // Поиск
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
      // Если задание уже выполнено, показываем диалог выбора
      if (assignment.status == 'COMPLETED') {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Задание выполнено'),
            content: const Text(
              'Это задание уже выполнено. Что вы хотите сделать?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'edit'),
                child: const Text('Внести изменения'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'restart'),
                child: const Text('Пройти заново'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Отмена'),
              ),
            ],
          ),
        );

        if (choice == null) return;

        // Получаем информацию об оборудовании (при офлайне — из кэша)
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
        if (equipment == null || equipment!.id.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Не удалось загрузить информацию об оборудовании. Проверьте сеть или загрузите задания при интернете.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        final eq = equipment!;
        await _syncService.saveEquipmentOffline([eq]);

        if (choice == 'edit') {
          // Внести изменения - загружаем существующую инспекцию
          try {
            final inspections = await _apiService.getInspections(eq.id);
            // Ищем инспекцию для этого задания
            Map<String, dynamic>? existingInspection;
            for (var insp in inspections) {
              // Проверяем, связана ли инспекция с этим заданием
              // (можно проверить по assignment_id в data или другим способом)
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
              // Открываем экран редактирования с существующей инспекцией
              if (mounted) {
                _recentService.addRecent(
                  assignmentId: assignment.id,
                  equipmentId: eq.id,
                  title: assignment.equipmentName,
                );
                await _openInspectionScreen(
                  equipment: eq,
                  assignmentId: assignment.id,
                  existingInspectionId: existingInspection!['id'] as String,
                  assignmentType: assignment.assignmentType,
                );
                _loadAssignments();
                _loadRecent();
              }
            } else {
              // Инспекция не найдена, создаем новую
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
            // Если не удалось загрузить инспекции, просто открываем новый экран
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
          // Пройти заново - создаем новую инспекцию, статус остается COMPLETED
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

      // Для заданий в статусе не COMPLETED - обычная логика
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

      bool usedOffline = false;
      Equipment? equipment;

      try {
        // Обновляем статус задания на "В работе" только если не COMPLETED (только при наличии сети)
        if (assignment.status != 'COMPLETED') {
          await _apiService.updateAssignmentStatus(assignment.id, 'IN_PROGRESS');
        }
        equipment = await _apiService.getAssignmentEquipment(assignment.id);
        if (equipment != null && equipment!.id.isNotEmpty) {
          await _syncService.saveEquipmentOffline([equipment!]);
        }
      } catch (e) {
        final msg = e.toString().toLowerCase();
        final isNetworkError = msg.contains('socketexception') ||
            msg.contains('clientexception') ||
            msg.contains('network is unreachable') ||
            msg.contains('нет подключения') ||
            msg.contains('failed host lookup') ||
            msg.contains('connection failed');
        // Офлайн-вход без токена: считаем режимом офлайн и берём данные из кэша
        final isOfflineNoToken = msg.contains('токен авторизации не найден') ||
            msg.contains('токен авторизации отсутствует');
        if (isNetworkError || isOfflineNoToken) {
          // Режим офлайн: берём оборудование из локального кэша
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

      // Закрываем индикатор загрузки
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (equipment == null || equipment!.id.isEmpty) {
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
              content: Text('Режим офлайн: работа с сохранёнными данными. При появлении интернета выполните синхронизацию.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        _recentService.addRecent(
          assignmentId: assignment.id,
          equipmentId: equipment!.id,
          title: assignment.equipmentName,
        );
        await _openInspectionScreen(
          equipment: equipment!,
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
                            _saveFilterToPrefs();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Фильтр по типу задания/обследования
                  Row(
                    children: [
                      const Text('Тип:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          value: _selectedAssignmentType,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1e293b),
                          style: const TextStyle(color: Colors.white),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('Все типы')),
                            DropdownMenuItem(value: 'DIAGNOSTICS', child: Text('DIAGNOSTICS')),
                            DropdownMenuItem(value: 'INSPECTION', child: Text('INSPECTION')),
                            DropdownMenuItem(value: 'EXPERTISE', child: Text('EXPERTISE')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedAssignmentType = value;
                                _filterAssignments();
                              });
                            }
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
                              _saveFilterToPrefs();
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
                          _saveFilterToPrefs();
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
                        _saveFilterToPrefs();
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
  
  Widget _buildRecentSection() {
    if (_recentItems.isEmpty) return const SizedBox.shrink();
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
              itemCount: _recentItems.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _recentItems[index];
                return ActionChip(
                  avatar: const Icon(Icons.history, color: Colors.white54, size: 18),
                  label: Text(
                    item.title,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  backgroundColor: const Color(0xFF1e293b),
                  side: BorderSide(color: Colors.blue.withOpacity(0.5)),
                  onPressed: () => _openRecentItem(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRecentItem(RecentItem item) async {
    Equipment? equipment;
    try {
      final list = await _syncService.getOfflineEquipment();
      equipment = list.firstWhere((e) => e.id == item.equipmentId);
    } catch (_) {}
    if (equipment == null) {
      try {
        equipment = await _apiService.getEquipmentById(item.equipmentId);
        await _syncService.saveEquipmentOffline([equipment!]);
      } catch (_) {}
    }
    if (equipment == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Оборудование не найдено. Загрузите задания при подключении к интернету.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    await _openInspectionScreen(
      equipment: equipment!,
      assignmentId: item.assignmentId,
      assignmentType: 'DIAGNOSTICS',
    );
    _loadAssignments();
    _loadRecent();
  }

  Widget _buildHierarchicalList() {
    final groups = _groupAssignments(_filteredAssignments);
    final hasRecent = _recentItems.isNotEmpty;
    
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
          return _buildRecentSection();
        }
        final groupIndex = hasRecent ? listIndex - 1 : listIndex;
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
                        (group.assignments.isNotEmpty) &&
                        ((group.assignments.first.opoId ?? '').isNotEmpty))
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                        tooltip: 'Заполнить ОПО',
                        onPressed: () async {
                          final first = group.assignments.first;
                          final ok = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OpoSurveyScreen(
                                opoId: first.opoId!,
                                opoName: group.opoName!,
                              ),
                            ),
                          );
                          if (ok == true) {
                            await _loadAssignments();
                          }
                        },
                        icon: const Icon(Icons.assignment_turned_in, color: Colors.green, size: 20),
                      ),
                    if ((group.assignments.isNotEmpty) &&
                        ((group.assignments.first.opoId ?? '').isNotEmpty) &&
                        (_opoHasData[group.assignments.first.opoId!] == true))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal.withOpacity(0.35)),
                        ),
                        child: const Text(
                          'ОПО заполнено',
                          style: TextStyle(color: Colors.teal, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
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
                    onTap: assignment.status == 'CANCELLED'
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
                              if ((_localInspectionState[assignment.id] ?? LocalAssignmentInspectionState.none()).hasDraft ||
                                  (_localInspectionState[assignment.id] ?? LocalAssignmentInspectionState.none()).hasSigned)
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

