import 'package:flutter/material.dart';
import '../models/diagnostic_menu_config.dart';
import '../models/diagnostic_menu_structure.dart';
import '../services/diagnostic_menu_service.dart';
import '../models/experience_base_entry.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'experience_base_add_entry_screen.dart';
import 'select_equipment_for_act_screen.dart';

/// Опытная база: справочник архетипов (xlsx) + записи с сервера.
class ExperienceBaseCatalogScreen extends StatefulWidget {
  const ExperienceBaseCatalogScreen({super.key});

  @override
  State<ExperienceBaseCatalogScreen> createState() =>
      _ExperienceBaseCatalogScreenState();
}

class _ExperienceBaseCatalogScreenState extends State<ExperienceBaseCatalogScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  late final TabController _tabs;
  String _query = '';
  List<ExperienceBaseEntry> _entries = [];
  bool _loadingEntries = false;
  String? _entriesError;
  late Future<DiagnosticMenuConfig> _menuFuture =
      DiagnosticMenuService.instance.getConfig();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
      if (_tabs.index == 1 && _entries.isEmpty && !_loadingEntries) {
        _loadEntries();
      }
    });
    _loadEntries();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loadingEntries = true;
      _entriesError = null;
    });
    try {
      final raw = await _api.getExperienceBaseEntries(
        q: _query.isEmpty ? null : _query,
        includeArchetypes: false,
      );
      if (mounted) {
        setState(() {
          _entries = raw
              .map((e) => ExperienceBaseEntry.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ))
              .toList();
          _loadingEntries = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _entriesError = e.toString();
          _loadingEntries = false;
        });
      }
    }
  }

  void _openAddEntry({
    required String categoryCode,
    required String equipmentKind,
    String equipmentMark = '',
  }) {
    Navigator.of(context)
        .push<bool>(
      MaterialPageRoute(
        builder: (_) => ExperienceBaseAddEntryScreen(
          categoryCode: categoryCode,
          equipmentKind: equipmentKind,
          equipmentMark: equipmentMark,
        ),
      ),
    )
        .then((ok) {
      if (ok == true) _loadEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: const Text('Опытная база'),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.accent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Справочник'),
            Tab(text: 'Записи'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 1
          ? FloatingActionButton(
              onPressed: () => _showAddEntryPicker(),
              backgroundColor: AppColors.accent,
              child: const Icon(Icons.add),
            )
          : null,
      body: FutureBuilder<DiagnosticMenuConfig>(
        future: _menuFuture,
        builder: (context, menuSnap) {
          final categories = menuSnap.data?.objectCategories ??
              DiagnosticMenuConfig.builtin().objectCategories;
          return TabBarView(
        controller: _tabs,
        children: [
          _CatalogTab(
            categories: categories,
            query: _query,
            searchCtrl: _searchCtrl,
            onQueryChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            onSelectArchetype: (cat, archetype) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SelectEquipmentForActScreen(
                    presetCategory: cat.equipmentPreset,
                    flowTitleSuffix:
                        '${archetype.kind} ${archetype.exampleMark}'.trim(),
                    categoryCode: cat.id,
                    archetypeKind: archetype.kind,
                    archetypeMark: archetype.exampleMark,
                  ),
                ),
              );
            },
            onAddEntry: (cat, archetype) {
              _openAddEntry(
                categoryCode: cat.id,
                equipmentKind: archetype.kind,
                equipmentMark: archetype.exampleMark,
              );
            },
          ),
          _EntriesTab(
            loading: _loadingEntries,
            error: _entriesError,
            entries: _entries,
            onRefresh: _loadEntries,
          ),
        ],
      );
        },
      ),
    );
  }

  void _showAddEntryPicker() async {
    final config = await _menuFuture;
    final categories = config.objectCategories;
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1e293b),
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Категория объекта',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final cat in categories)
                for (final a in cat.archetypes)
                  ListTile(
                    title: Text(
                      a.kind,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${cat.title}${a.exampleMark.isEmpty ? '' : ' · ${a.exampleMark}'}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openAddEntry(
                        categoryCode: cat.id,
                        equipmentKind: a.kind,
                        equipmentMark: a.exampleMark,
                      );
                    },
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _CatalogTab extends StatelessWidget {
  final List<DiagnosticObjectCategory> categories;
  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;
  final void Function(
    DiagnosticObjectCategory cat,
    DiagnosticEquipmentArchetype archetype,
  ) onSelectArchetype;
  final void Function(
    DiagnosticObjectCategory cat,
    DiagnosticEquipmentArchetype archetype,
  ) onAddEntry;

  const _CatalogTab({
    required this.categories,
    required this.query,
    required this.searchCtrl,
    required this.onQueryChanged,
    required this.onSelectArchetype,
    required this.onAddEntry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: searchCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Поиск по марке, типу…',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF1e293b),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: onQueryChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Выберите марку для протокола. Записи опытной базы подтянутся при выборе '
            'оборудования (привязка «Задание → Объект»).',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              for (final cat in categories)
                _CategoryBlock(
                  category: cat,
                  query: query,
                  onSelectArchetype: (a) => onSelectArchetype(cat, a),
                  onAddEntry: (a) => onAddEntry(cat, a),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EntriesTab extends StatelessWidget {
  final bool loading;
  final String? error;
  final List<ExperienceBaseEntry> entries;
  final Future<void> Function() onRefresh;

  const _EntriesTab({
    required this.loading,
    required this.error,
    required this.entries,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: onRefresh, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'Пока нет пользовательских записей.\nНажмите + чтобы добавить рекомендацию.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: entries.length,
        itemBuilder: (_, i) {
          final e = entries[i];
          return Card(
            color: const Color(0xFF1e293b),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(e.displayTitle, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                '${e.entryTypeLabel}\n${e.body}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  final DiagnosticObjectCategory category;
  final String query;
  final void Function(DiagnosticEquipmentArchetype archetype) onSelectArchetype;
  final void Function(DiagnosticEquipmentArchetype archetype) onAddEntry;

  const _CategoryBlock({
    required this.category,
    required this.query,
    required this.onSelectArchetype,
    required this.onAddEntry,
  });

  @override
  Widget build(BuildContext context) {
    final items = category.archetypes.where((a) {
      if (query.isEmpty) return true;
      final hay = '${a.kind} ${a.exampleMark}'.toLowerCase();
      return hay.contains(query);
    }).toList();

    if (items.isEmpty && query.isNotEmpty) return const SizedBox.shrink();

    return Card(
      color: const Color(0xFF1e293b),
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.white12),
        child: ExpansionTile(
          leading: Icon(category.icon, color: AppColors.darkPrimary),
          title: Text(
            category.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: category.inspectionTypeLabels.isEmpty
              ? null
              : Text(
                  category.inspectionTypeLabels.join(' · '),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
          children: items
              .map(
                (a) => ListTile(
                  title: Text(
                    a.kind,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: a.exampleMark.isEmpty
                      ? null
                      : Text(
                          a.exampleMark,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white38),
                    color: const Color(0xFF1e293b),
                    onSelected: (v) {
                      if (v == 'act') {
                        onSelectArchetype(a);
                      } else if (v == 'add') {
                        onAddEntry(a);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'act', child: Text('Создать акт')),
                      PopupMenuItem(value: 'add', child: Text('Добавить запись')),
                    ],
                  ),
                  onTap: () => onSelectArchetype(a),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
