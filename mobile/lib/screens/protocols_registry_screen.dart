import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../services/auto_save_service.dart';
import '../services/api_service.dart';
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
  final _apiService = ApiService();

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

      List<Map<String, dynamic>> serverProtos = [];
      try {
        final sp = await _apiService.listStandaloneProtocols();
        for (final row in sp) {
          serverProtos.add({
            'id': row['id']?.toString() ?? '',
            'object': row['title']?.toString() ?? 'Протокол',
            'type': _standaloneKindRu(row['kind']?.toString()),
            'date': row['created_at']?.toString() ?? '',
            'status': 'завершён',
            'source': 'server_standalone',
          });
        }
      } catch (_) {}

      // Обследования (чек-листы) с сервера — история ранее завершённых работ
      try {
        final inspections = await _apiService.listServerInspections();
        for (final row in inspections) {
          final status = (row['status'] ?? '').toString().toUpperCase();
          final eqName = (row['equipment_name'] as String?)?.trim();
          serverProtos.add({
            'id': row['id']?.toString() ?? '',
            'object': (eqName != null && eqName.isNotEmpty)
                ? eqName
                : 'Обследование',
            'type': _mapInspectionType(
                (row['inspection_type'] ?? 'NDT').toString()),
            'date': (row['date_performed'] ?? row['created_at'] ?? '')
                .toString(),
            'status': status == 'DRAFT' ? 'черновик (сервер)' : 'завершён',
            'source': 'server_inspection',
          });
        }
      } catch (_) {}

      // Свежие записи сверху
      serverProtos.sort((a, b) => (b['date'] ?? '')
          .toString()
          .compareTo((a['date'] ?? '').toString()));

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

  String _standaloneKindRu(String? kind) {
    switch (kind) {
      case 'ndk_protocol':
        return 'Протокол НК (мобильный)';
      case 'quick_control':
        return 'Быстрый контроль ВИК/УЗТ';
      case 'custom_template':
        return 'Протокол по шаблону';
      default:
        return kind?.isNotEmpty == true ? kind! : 'Протокол (мобильный)';
    }
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
      appBar: AppBar(
        title: const Text(
          'Реестр протоколов',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadData,
            tooltip: 'Обновить',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          indicatorWeight: 2,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          tabs: [
            Tab(
              height: 42,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.pending_actions, size: 15),
                  const SizedBox(width: 6),
                  const Text('Черновики'),
                  if (_drafts.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_drafts.length}',
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(
              height: 42,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_alt, size: 15),
                  SizedBox(width: 6),
                  Text('Все протоколы'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
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
            Icon(Icons.check_circle_outline, size: 40, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('Нет незавершённых протоколов',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
            Icon(Icons.folder_open, size: 40, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('Реестр пуст',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            SizedBox(height: 4),
            Text('Созданные протоколы будут отображаться здесь',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
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
          } else if (item['source'] == 'server_standalone') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Скачать DOCX: веб → Генерация отчётов → блок «Протоколы только с телефона».',
                ),
                duration: Duration(seconds: 5),
              ),
            );
          } else if (item['source'] == 'server_inspection') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Обследование на сервере. Отчёт можно сформировать в веб-версии → Генерация отчётов.',
                ),
                duration: Duration(seconds: 5),
              ),
            );
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
          decoration: const BoxDecoration(
            color: AppColors.darkSurface,
            border: Border(
              bottom: BorderSide(color: AppColors.darkBorder, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              const SizedBox(
                width: 82,
                child: Text('Дата',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ),
              const Expanded(
                child: Text('Объект',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ),
              SizedBox(
                width: showDelete ? 104 : 120,
                child: const Text('Вид контроля',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ),
              SizedBox(
                width: showDelete ? 86 : 90,
                child: const Text('Статус',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ),
              if (showDelete) const SizedBox(width: 28),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              color: AppColors.darkBorder,
            ),
            itemBuilder: (ctx, idx) {
              final item = rows[idx];
              final statusLabel = (item['status'] as String?) ?? 'не завершён';
              final isCompleted = statusLabel == 'завершён';
              final statusColor = isCompleted ? AppColors.success : AppColors.warning;
              final isDraft = item['source'] == 'draft';
              return InkWell(
                onTap: () => onTap(item),
                child: Container(
                  color: idx.isOdd
                      ? Colors.white.withOpacity(0.02)
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 82,
                        child: Text(
                          _formatDate(item['date'] as String?),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10.5,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          (item['object'] as String?) ?? '',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: showDelete ? 104 : 120,
                        child: Text(
                          (item['type'] as String?) ?? '',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: showDelete ? 86 : 90,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: statusColor.withOpacity(0.35),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                                color: statusColor,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      if (showDelete && isDraft)
                        InkWell(
                          onTap: () => onDelete(item),
                          child: const Padding(
                            padding: EdgeInsets.all(5),
                            child: Icon(Icons.delete_outline,
                                color: AppColors.danger, size: 14),
                          ),
                        )
                      else if (showDelete)
                        const SizedBox(width: 28),
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
