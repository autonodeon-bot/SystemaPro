import 'package:flutter/material.dart';
import '../models/equipment.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../models/experience_base_entry.dart';
import '../theme/app_colors.dart';
import '../models/inspection_object_template.dart';
import '../widgets/experience_base_context_sheet.dart';
import '../widgets/inspection_template_picker_sheet.dart';
import 'acoustic_emission_protocol_screen.dart';
import 'pressure_test_quick_screen.dart';
import 'vessel_inspection_screen.dart';
import '../models/inspection_matrix.dart';

/// Экран выбора оборудования для создания Акта ТД(ЭПБ) — П.1.1.3
class SelectEquipmentForActScreen extends StatefulWidget {
  /// Фильтр из мастера: vessel, boiler, valve_ps, drilling, pipeline, other
  final String? presetCategory;
  /// Подзаголовок потока (напр. «Внутренний осмотр · Сосуд»)
  final String? flowTitleSuffix;
  /// Код категории опытной базы (srpd, bu, …).
  final String? categoryCode;
  final String? archetypeKind;
  final String? archetypeMark;
  final String? assignmentId;
  /// Направление из мастера: external, technical, hydraulic, ae, …
  final String? inspectionDirection;
  /// VISUAL / NDT / EXPERTISE — приоритет над шаблоном и direction.
  final String? preferredInspectionType;

  const SelectEquipmentForActScreen({
    super.key,
    this.presetCategory,
    this.flowTitleSuffix,
    this.categoryCode,
    this.archetypeKind,
    this.archetypeMark,
    this.assignmentId,
    this.inspectionDirection,
    this.preferredInspectionType,
  });

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
        final matchWizard =
            _matchesPresetCategory(widget.presetCategory, eq);
        return matchType && matchSearch && matchWizard;
      }).toList();
    });
  }

  bool _matchesPresetCategory(String? preset, Equipment eq) {
    if (preset == null || preset.isEmpty) return true;
    final code = (eq.typeCode ?? '').toLowerCase();
    final name = (eq.typeName ?? '').toLowerCase();
    final ename = eq.name.toLowerCase();
    switch (preset) {
      case 'vessel':
        return code.contains('vessel') ||
            name.contains('сосуд') ||
            name.contains('аппарат') ||
            name.contains('ёмкост') ||
            ename.contains('сосуд');
      case 'pipeline':
        return code.contains('pipeline') || name.contains('трубопровод');
      case 'compressor':
        return code.contains('compressor') || name.contains('компрессор');
      case 'boiler':
        return name.contains('котл') ||
            code.contains('boiler') ||
            ename.contains('котл');
      case 'drilling':
        return name.contains('бур') ||
            ename.contains('буров') ||
            code.contains('drill');
      case 'valve_ps':
        return name.contains('клапан') ||
            name.contains('предохран') ||
            name.contains('пс ') ||
            code.contains('valve') ||
            code.contains('zra');
      case 'other':
      default:
        return true;
    }
  }

  Future<void> _openAct(Equipment eq) async {
    if (widget.categoryCode != null && widget.categoryCode!.isNotEmpty) {
      try {
        final ctx = await _api.getExperienceBaseContext(
          equipmentId: eq.id,
          assignmentId: widget.assignmentId,
          categoryCode: widget.categoryCode,
          equipmentKind: widget.archetypeKind ?? eq.name,
          equipmentMark: widget.archetypeMark,
        );
        final raw = ctx['items'];
        if (raw is List && raw.isNotEmpty && mounted) {
          final items = raw
              .map((e) => ExperienceBaseEntry.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ))
              .toList();
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (sheetCtx) => ExperienceBaseContextSheet(
              items: items,
              equipmentName: eq.name ?? 'Объект',
              onContinue: () => Navigator.pop(sheetCtx),
            ),
          );
        }
      } catch (_) {
        // не блокируем создание акта
      }
    }
    InspectionObjectTemplate? selectedTemplate;

    if (widget.categoryCode != null &&
        widget.inspectionDirection != null &&
        widget.inspectionDirection!.isNotEmpty) {
      try {
        final resolved = await _api.resolveInspectionObjectTemplates(
          categoryCode: widget.categoryCode!,
          inspectionDirection: widget.inspectionDirection!,
          equipmentId: eq.id,
          equipmentKind: widget.archetypeKind ?? eq.name,
          equipmentMark: widget.archetypeMark,
          equipmentPreset: widget.presetCategory,
        );
        final rawList = resolved['templates'];
        if (rawList is List && rawList.isNotEmpty && mounted) {
          final templates = rawList
              .map((e) => InspectionObjectTemplate.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ))
              .toList();
          selectedTemplate = await showModalBottomSheet<InspectionObjectTemplate?>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (sheetCtx) => InspectionTemplatePickerSheet(
              templates: templates,
              equipmentName: eq.name ?? 'Объект',
              onConfirm: (t) => Navigator.pop(sheetCtx, t),
            ),
          );
        }
      } catch (_) {}
    }

    if (!mounted) return;

    final tpl = selectedTemplate;

    if (widget.inspectionDirection == 'ae') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AcousticEmissionProtocolScreen(
            equipment: eq,
            assignmentId: widget.assignmentId,
          ),
        ),
      );
      return;
    }

    final dir = widget.inspectionDirection;
    final isPressureDir = dir == 'hydraulic' || dir == 'pneumatic';
    if ((tpl != null && tpl.targetFlow == 'pressure_test') || isPressureDir) {
      final testType = tpl?.defaultData['test_type']?.toString() ??
          (dir == 'pneumatic' ? 'ПИ' : 'ГИ');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PressureTestQuickScreen(
            initialTestType: testType,
          ),
        ),
      );
      return;
    }

    final inspectionType = widget.preferredInspectionType ??
        tpl?.defaultData['inspection_type']?.toString() ??
        (widget.inspectionDirection != null
            ? inspectionTypeForDirection(widget.inspectionDirection!)
            : 'NDT');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VesselInspectionScreen(
          equipment: eq,
          assignmentId: widget.assignmentId,
          inspectionType: inspectionType,
          initialChecklistJson: tpl?.defaultData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: Text(
          widget.flowTitleSuffix != null && widget.flowTitleSuffix!.isNotEmpty
              ? 'Акт ТД — ${widget.flowTitleSuffix}'
              : 'Акт ТД (ЭПБ) — выбор объекта',
        ),
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
