import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../services/auto_save_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import 'quick_control_screen.dart';
import 'new_ndk_protocol_screen.dart';
import 'custom_protocol_screen.dart';

/// Экран реестра протоколов/актов (П.1.2 + П.1.3)
/// Показывает:
///  - Незавершённые черновики (статус «не завершён»)
///  - Все когда-либо оформленные протоколы с сервера
class ProtocolsRegistryScreen extends StatefulWidget {
  const ProtocolsRegistryScreen({super.key});

  @override
  State<ProtocolsRegistryScreen> createState() =>
      _ProtocolsRegistryScreenState();
}

class _ProtocolsRegistryScreenState extends State<ProtocolsRegistryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _autoSaveService = AutoSaveService();
  final _syncService = SyncService();

  bool _loading = true;
  List<Map<String, dynamic>> _drafts = [];
  List<Map<String, dynamic>> _serverProtocols = [];

  final _fmt = intl.DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final draftsMap = await _autoSaveService.getDrafts();
      final drafts = draftsMap.values.toList()
        ..sort((a, b) {
          final aDate = a['saved_at'] as String? ?? '';
          final bDate = b['saved_at'] as String? ?? '';
          return bDate.compareTo(aDate);
        });

      // Загружаем синхронизированные обследования
      List<Map<String, dynamic>> serverProtos = [];
      try {
        final pending = await _syncService.getPendingInspections();
        for (final p in pending) {
          serverProtos.add({
            'id': p['local_id'] ?? p['id'] ?? '',
            'object': _extractObjectName(p),
            'type': 'НК - протокол',
            'date': p['created_at'] ?? p['inspection_date'] ?? '',
            'status': p['status'] == 'COMPLETED' ? 'завершён' : 'не завершён',
            'source': 'local',
          });
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _drafts = drafts;
          _serverProtocols = serverProtos;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _extractObjectName(Map<String, dynamic> data) {
    final checklist = data['checklist_data'];
    if (checklist is Map) {
      return (checklist['vessel_name'] as String?) ??
          (checklist['object_name'] as String?) ??
          'Объект';
    }
    return (data['equipment_id'] as String?) ?? 'Объект';
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw);
      return _fmt.format(dt.toLocal());
    } catch (_) {
      return raw;
    }
  }

  /// Открывает черновик в нужном экране в зависимости от типа
  void _openDraft(Map<String, dynamic> draft) {
    final screenType = (draft['screen_type'] as String?) ?? 'inspection';

    switch (screenType) {
      case AutoSaveService.screenTypeQuickControl:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => QuickControlScreen(savedDraft: draft),
        ));
        break;

      case AutoSaveService.screenTypeNdkProtocol:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => NewNdkProtocolScreen(savedDraft: draft),
        ));
        break;

      case AutoSaveService.screenTypeCustomProtocol:
        final checklist = draft['checklist_data'] as Map<String, dynamic>? ?? {};
        final templateId = checklist['template_id'] as String?;
        final templateName = checklist['template_name'] as String? ?? 'Протокол';
        // Восстанавливаем минимальный шаблон из сохранённых данных
        final fakeTemplate = {
          'id': templateId ?? 'unknown',
          'name': templateName,
          'structure': const [],
        };
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CustomProtocolScreen(template: fakeTemplate),
        ));
        break;

      default:
        // Акт НДТ сосуда — требует Equipment, показываем уведомление
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Для открытия НДТ-акта перейдите в «Оборудование» и выберите объект',
            ),
            duration: Duration(seconds: 4),
          ),
        );
    }
  }

  Future<void> _deleteDraft(String draftId, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтверждение удаления'),
        content: Text('Удалить черновик "$label"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _autoSaveService.deleteDraft(draftId);
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text('Реестр протоколов / актов'),
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Обновить',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.darkPrimary,
          labelColor: AppColors.darkPrimary,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(
              text: 'Незавершённые',
              icon: Badge(
                isLabelVisible: _drafts.isNotEmpty,
                label: Text('${_drafts.length}'),
                child: const Icon(Icons.pending_actions, size: 18),
              ),
            ),
            const Tab(
              text: 'Все протоколы',
              icon: Icon(Icons.list_alt, size: 18),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDraftsTab(),
                _buildAllProtocolsTab(),
              ],
            ),
    );
  }

  // ---- Вкладка незавершённых черновиков ----
  Widget _buildDraftsTab() {
    if (_drafts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: Colors.white30),
            SizedBox(height: 16),
            Text('Нет незавершённых протоколов',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    final rows = _drafts.map((d) {
      final id = (d['id'] as String?) ?? '';
      final equipId = (d['equipment_id'] as String?) ?? '';
      final checklist = d['checklist_data'];
      String objectName = equipId;
      String controlType = 'НДТ акт';
      if (checklist is Map) {
        objectName = (checklist['vessel_name'] as String?) ??
            (checklist['object_name'] as String?) ??
            equipId;
        final iType = checklist['inspection_type'] as String?;
        if (iType != null) controlType = _mapInspectionType(iType);
        // Попробуем извлечь из meta
        final meta = d['meta'] as Map?;
        if (meta != null) {
          objectName = (meta['objectName'] as String?)?.isNotEmpty == true
              ? meta['objectName'] as String
              : objectName;
          controlType = (meta['controlType'] as String?) ?? controlType;
        }
      }
      return {
        'id': id,
        'date': d['saved_at'] as String? ?? '',
        'object': objectName,
        'type': controlType,
        'status': 'не завершён',
        'source': 'draft',
        '_draft': d,
      };
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: _buildRegistryTable(
        rows: rows,
        onTap: (item) {
          final draft = item['_draft'] as Map<String, dynamic>?;
          if (draft != null) _openDraft(draft);
        },
        onDelete: (item) => _deleteDraft(item['id'] as String, item['object'] as String),
        showDelete: true,
      ),
    );
  }

  // ---- Вкладка всех протоколов ----
  Widget _buildAllProtocolsTab() {
    final all = [..._serverProtocols];
    for (final d in _drafts) {
      final checklist = d['checklist_data'];
      String objectName = (d['equipment_id'] as String?) ?? 'Объект';
      String controlType = 'НДТ акт';
      if (checklist is Map) {
        objectName = (checklist['vessel_name'] as String?) ??
            (checklist['object_name'] as String?) ??
            objectName;
        final iType = checklist['inspection_type'] as String?;
        if (iType != null) controlType = _mapInspectionType(iType);
        final meta = d['meta'] as Map?;
        if (meta != null) {
          objectName = (meta['objectName'] as String?)?.isNotEmpty == true
              ? meta['objectName'] as String
              : objectName;
          controlType = (meta['controlType'] as String?) ?? controlType;
        }
      }
      all.add({
        'id': d['id'] ?? '',
        'object': objectName,
        'type': controlType,
        'date': d['saved_at'] ?? '',
        'status': 'не завершён',
        'source': 'draft',
        '_draft': d,
      });
    }

    if (all.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 48, color: Colors.white30),
            SizedBox(height: 16),
            Text('Реестр пуст', style: TextStyle(color: Colors.white54)),
            SizedBox(height: 8),
            Text('Созданные протоколы будут отображаться здесь',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: _buildRegistryTable(
        rows: all,
        onTap: (item) {
          if (item['source'] == 'draft') {
            final draft = item['_draft'] as Map<String, dynamic>?;
            if (draft != null) _openDraft(draft);
          }
        },
        onDelete: (item) {
          if (item['source'] == 'draft') {
            _deleteDraft(item['id'] as String, item['object'] as String);
          }
        },
        showDelete: true,
      ),
    );
  }

  /// Универсальная таблица реестра протоколов
  Widget _buildRegistryTable({
    required List<Map<String, dynamic>> rows,
    required void Function(Map<String, dynamic>) onTap,
    required void Function(Map<String, dynamic>) onDelete,
    bool showDelete = false,
  }) {
    return Column(
      children: [
        // Шапка таблицы
        Container(
          color: AppColors.darkSurface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              const SizedBox(
                width: 88,
                child: Text('Дата',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              const Expanded(
                child: Text('Объект',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              SizedBox(
                width: showDelete ? 104 : 120,
                child: const Text('Вид контроля',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              SizedBox(
                width: showDelete ? 86 : 90,
                child: const Text('Статус',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              if (showDelete) const SizedBox(width: 32),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white24),
        // Строки
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: Colors.white10),
            itemBuilder: (ctx, idx) {
              final item = rows[idx];
              final isCompleted = item['status'] == 'завершён';
              final statusColor =
                  isCompleted ? Colors.greenAccent : Colors.redAccent;
              final statusLabel = isCompleted ? 'завершён' : 'не завершён';
              final isDraft = item['source'] == 'draft';
              return InkWell(
                onTap: () => onTap(item),
                child: Container(
                  color: idx.isOdd
                      ? Colors.white.withOpacity(0.03)
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(
                          _formatDate(item['date'] as String?),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          (item['object'] as String?) ?? '',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: showDelete ? 104 : 120,
                        child: Text(
                          (item['type'] as String?) ?? '',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: showDelete ? 86 : 90,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      if (showDelete && isDraft)
                        InkWell(
                          onTap: () => onDelete(item),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.delete_outline,
                                color: Colors.redAccent, size: 16),
                          ),
                        )
                      else if (showDelete)
                        const SizedBox(width: 32),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _mapInspectionType(String code) {
    switch (code.toUpperCase()) {
      case 'NDT':
      case 'VISUAL':
        return 'ТД(ЭПБ) - акт';
      case 'QUESTIONNAIRE':
        return 'Опросный лист';
      case 'EXPERTISE':
        return 'Экспертиза';
      default:
        return code;
    }
  }
}
