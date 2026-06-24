import 'dart:io';

import 'package:flutter/material.dart';

import '../models/drawing_template.dart';
import '../models/equipment.dart';
import '../services/drawing_templates_service.dart';
import '../theme/app_colors.dart';

/// Экран выбора шаблона чертежа для оборудования (П.2 ТЗ 2026-04).
///
/// Показывает список доступных шаблонов (свои + общие по типу + универсальные),
/// с превью, номером версии и количеством предопределённых точек замера.
/// Поддерживает офлайн-работу: если сети нет — читает только закешированные.
class DrawingTemplatePickerScreen extends StatefulWidget {
  final Equipment equipment;

  /// Если передан — заголовок используется вместо стандартного.
  final String? title;

  const DrawingTemplatePickerScreen({
    super.key,
    required this.equipment,
    this.title,
  });

  @override
  State<DrawingTemplatePickerScreen> createState() =>
      _DrawingTemplatePickerScreenState();
}

class _DrawingTemplatePickerScreenState
    extends State<DrawingTemplatePickerScreen> {
  final DrawingTemplatesService _service = DrawingTemplatesService();
  List<DrawingTemplate> _templates = [];
  bool _loading = true;
  bool _isOffline = false;
  String _search = '';
  String? _categoryFilter;

  static const _categoryLabels = {
    'vessel': 'Сосуды',
    'gas_separator': 'Газосепараторы',
    'oil_settler': 'Отстойники нефти',
    'underground_tank': 'Ёмкости подземные',
    'pipeline': 'Трубопроводы',
    'ndt_scheme': 'Схема НК',
    'thickness_scheme': 'Схема УЗТ',
    'other': 'Прочее',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _isOffline = false;
    });
    try {
      final online = await _service.fetchForEquipment(
        equipment: widget.equipment,
      );
      if (!mounted) return;
      setState(() {
        _templates = online;
        _loading = false;
      });
    } catch (_) {
      final offline = await _service.getOfflineForEquipment(widget.equipment);
      if (!mounted) return;
      setState(() {
        _templates = offline;
        _isOffline = true;
        _loading = false;
      });
    }
  }

  List<DrawingTemplate> get _filtered {
    return _templates.where((t) {
      if (_categoryFilter != null && t.category != _categoryFilter) return false;
      if (_search.isNotEmpty) {
        final s = _search.toLowerCase();
        return t.name.toLowerCase().contains(s) ||
            (t.equipmentTypeName ?? '').toLowerCase().contains(s) ||
            (t.equipmentName ?? '').toLowerCase().contains(s);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackgroundDeep : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(widget.title ?? 'Шаблоны чертежей'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _load(force: true),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              color: AppColors.warning.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Офлайн-режим. Показаны только закешированные шаблоны.',
                      style: TextStyle(color: AppColors.warning, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: 'Поиск шаблона...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _categoryChip(null, 'Все'),
                      for (final e in _categoryLabels.entries) _categoryChip(e.key, e.value),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? _emptyState(isDark)
                    : RefreshIndicator(
                        onRefresh: () => _load(force: true),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _templateCard(_filtered[i], isDark),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(String? key, String label) {
    final selected = _categoryFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => setState(() => _categoryFilter = selected ? null : key),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _emptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              size: 56,
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.25),
            ),
            const SizedBox(height: 12),
            Text(
              'Шаблонов чертежей не найдено',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Попросите администратора загрузить схему для этой единицы\nчерез веб-портал → Шаблоны чертежей.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _templateCard(DrawingTemplate t, bool isDark) {
    final hasLocal = t.localImagePath != null && File(t.localImagePath!).existsSync();
    final isOwnForThisEquipment = t.equipmentId == widget.equipment.id;
    final bg = isDark ? AppColors.darkSurface : Colors.white;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).pop(t),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 72,
                  height: 72,
                  color: (isDark ? Colors.black : Colors.grey).withValues(alpha: 0.25),
                  child: hasLocal
                      ? Image.file(File(t.localImagePath!), fit: BoxFit.cover)
                      : Icon(
                          Icons.image_outlined,
                          size: 32,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: isDark ? Colors.white : AppColors.lightOnSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _badge(
                          'v${t.version}',
                          bg: AppColors.accent.withValues(alpha: 0.15),
                          color: AppColors.accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (t.category != null)
                          _badge(_categoryLabels[t.category] ?? t.category!,
                              bg: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05)),
                        if (isOwnForThisEquipment)
                          _badge('Своя',
                              bg: AppColors.info.withValues(alpha: 0.15),
                              color: AppColors.info),
                        if (hasLocal)
                          _badge('Офлайн',
                              bg: AppColors.success.withValues(alpha: 0.15),
                              color: AppColors.success)
                        else
                          _badge('Требуется загрузка',
                              bg: AppColors.warning.withValues(alpha: 0.15),
                              color: AppColors.warning),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.track_changes,
                            size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${t.points.length} точек',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (t.imageWidth != null && t.imageHeight != null) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.photo_size_select_large,
                              size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            '${t.imageWidth}×${t.imageHeight}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, {required Color bg, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color ?? AppColors.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
