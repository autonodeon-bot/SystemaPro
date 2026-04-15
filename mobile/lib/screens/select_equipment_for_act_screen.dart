import 'package:flutter/material.dart';
import '../models/equipment.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import 'vessel_inspection_screen.dart';

/// Экран выбора оборудования для создания Акта ТД(ЭПБ) — П.1.1.3
class SelectEquipmentForActScreen extends StatefulWidget {
  const SelectEquipmentForActScreen({super.key});

  @override
  State<SelectEquipmentForActScreen> createState() =>
      _SelectEquipmentForActScreenState();
}

class _SelectEquipmentForActScreenState
    extends State<SelectEquipmentForActScreen> {
  final _api = ApiService();
  final _sync = SyncService();

  bool _loading = true;
  String? _error;
  List<Equipment> _all = [];
  List<Equipment> _filtered = [];

  final _searchCtrl = TextEditingController();
  String? _filterType;

  // Типы оборудования, для которых есть акт ТД(ЭПБ)
  static const _supportedTypes = ['vessel', 'compressor', 'pipeline'];
  static const _typeLabels = {
    'vessel': 'Сосуд / Аппарат',
    'compressor': 'Компрессор',
    'pipeline': 'Трубопровод',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<Equipment> items;
      try {
        items = await _api.getAllEquipment();
        await _sync.saveEquipmentOffline(items);
      } catch (_) {
        items = await _sync.getOfflineEquipment();
      }
      if (mounted) {
        setState(() {
          _all = items;
          _loading = false;
        });
        _applyFilter();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = _all.where((eq) {
        final typeCode = (eq.typeCode ?? '').toLowerCase();
        final typeName = (eq.typeName ?? '').toLowerCase();
        final matchType = _filterType == null ||
            typeCode.contains(_filterType!.toLowerCase()) ||
            typeName.contains(_filterType!.toLowerCase());
        final matchSearch = q.isEmpty ||
            eq.name.toLowerCase().contains(q) ||
            (eq.serialNumber ?? '').toLowerCase().contains(q);
        return matchType && matchSearch;
      }).toList();
    });
  }

  void _openAct(Equipment eq) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VesselInspectionScreen(
          equipment: eq,
          inspectionType: 'NDT',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text('Акт ТД (ЭПБ) — выбор объекта'),
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Поиск
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Поиск по наименованию, зав./инв. №...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchCtrl.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.darkSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Фильтр по типу
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _typeChip(null, 'Все типы'),
                ..._typeLabels.entries
                    .map((e) => _typeChip(e.key, e.value))
                    .toList(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Список
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _typeChip(String? type, String label) {
    final selected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.white70)),
        selected: selected,
        onSelected: (_) {
          setState(() => _filterType = type);
          _applyFilter();
        },
        selectedColor: AppColors.darkPrimary,
        backgroundColor: AppColors.darkSurface,
        checkmarkColor: Colors.white,
        side: BorderSide(color: selected ? AppColors.darkPrimary : Colors.white24),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Повторить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkPrimary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (_filtered.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.white24),
            SizedBox(height: 12),
            Text('Оборудование не найдено', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _filtered.length,
        itemBuilder: (ctx, i) => _buildCard(_filtered[i]),
      ),
    );
  }

  Widget _buildCard(Equipment eq) {
    final typeCode = (eq.typeCode ?? '').toLowerCase();
    final typeName = (eq.typeName ?? '').toLowerCase();
    final typeLabel = _typeLabels.entries
        .firstWhere(
          (e) => typeCode.contains(e.key) || typeName.contains(e.key),
          orElse: () => MapEntry('other', eq.typeName ?? 'Оборудование'),
        )
        .value;

    return Card(
      color: AppColors.darkSurface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () => _openAct(eq),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.darkPrimary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.precision_manufacturing, color: AppColors.darkPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eq.name ?? 'Объект',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      typeLabel,
                      style: TextStyle(color: AppColors.darkPrimary, fontSize: 12),
                    ),
                    if ((eq.serialNumber ?? '').isNotEmpty)
                      Text('зав. № ${eq.serialNumber}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.darkPrimary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Создать акт',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
