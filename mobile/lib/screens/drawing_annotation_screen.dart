import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/drawing_template.dart';
import '../theme/app_colors.dart';

/// Экран аннотации шаблона чертежа с точками замера (П.2 ТЗ 2026-04).
///
/// Возможности:
///  * предопределённые точки из [DrawingTemplate] отображаются как есть
///  * инженер может добавить свои точки (long-press) и перенести их
///  * вводит фактическое значение (actualValue) — привязывается к точке
///  * все координаты хранятся в процентах (0-100) от размеров изображения,
///    поэтому корректно работают на любом экране и после экспорта
///
/// Возвращает обновлённый список [DrawingTemplatePoint] при Save.
class DrawingAnnotationScreen extends StatefulWidget {
  final DrawingTemplate template;

  /// Существующие значения инженера (по id точки → actualValue).
  final Map<String, double>? existingMeasurements;

  final String? equipmentName;

  const DrawingAnnotationScreen({
    super.key,
    required this.template,
    this.existingMeasurements,
    this.equipmentName,
  });

  @override
  State<DrawingAnnotationScreen> createState() => _DrawingAnnotationScreenState();
}

class _DrawingAnnotationScreenState extends State<DrawingAnnotationScreen> {
  late List<DrawingTemplatePoint> _points;
  String? _selectedId;
  final TransformationController _transformCtrl = TransformationController();
  Size? _imageRenderSize;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingMeasurements ?? const {};
    _points = widget.template.points.map((p) {
      final actual = existing[p.id];
      return actual != null ? p.copyWith(actualValue: actual) : p;
    }).toList();
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  bool get _hasLocalImage =>
      widget.template.localImagePath != null &&
      File(widget.template.localImagePath!).existsSync();

  // ── Добавление точки (long-press) ──────────────────────────────────────
  void _onLongPress(Offset local, Size renderSize) {
    if (renderSize.width == 0 || renderSize.height == 0) return;
    final xp = (local.dx / renderSize.width) * 100;
    final yp = (local.dy / renderSize.height) * 100;
    if (xp < 0 || xp > 100 || yp < 0 || yp > 100) return;
    final userAdded = _points.where((p) => p.isUserAdded).length;
    final label = 'U${userAdded + 1}';
    final p = DrawingTemplatePoint(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      label: label,
      pointType: DrawingPointType.custom,
      xPercent: xp,
      yPercent: yp,
      sortOrder: _points.length,
      isUserAdded: true,
    );
    HapticFeedback.lightImpact();
    setState(() {
      _points.add(p);
      _selectedId = p.id;
    });
    _editPointDialog(p);
  }

  void _onPointTap(DrawingTemplatePoint p) {
    setState(() => _selectedId = p.id);
    _editPointDialog(p);
  }

  void _movePoint(DrawingTemplatePoint p, Offset local, Size renderSize) {
    if (renderSize.width == 0 || renderSize.height == 0) return;
    if (!p.isUserAdded) return; // предопределённые точки не двигаем
    final xp = (local.dx / renderSize.width * 100).clamp(0.0, 100.0);
    final yp = (local.dy / renderSize.height * 100).clamp(0.0, 100.0);
    setState(() {
      _points = _points
          .map((x) => x.id == p.id ? x.copyWith(xPercent: xp, yPercent: yp) : x)
          .toList();
    });
  }

  void _deletePoint(DrawingTemplatePoint p) {
    if (!p.isUserAdded) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Предопределённые точки можно только снять, удалить нельзя'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    setState(() {
      _points.removeWhere((x) => x.id == p.id);
      if (_selectedId == p.id) _selectedId = null;
    });
  }

  Future<void> _editPointDialog(DrawingTemplatePoint p) async {
    final labelCtrl = TextEditingController(text: p.label);
    final actualCtrl = TextEditingController(
      text: p.actualValue == null ? '' : p.actualValue!.toStringAsFixed(2),
    );
    final expectedCtrl = TextEditingController(
      text: p.expectedValue == null ? '' : p.expectedValue!.toStringAsFixed(2),
    );
    final notesCtrl = TextEditingController(text: p.notes ?? '');

    DrawingPointType pointType = p.pointType;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          p.label,
                          style: TextStyle(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (p.isUserAdded)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _deletePoint(p);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Метка',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    enabled: p.isUserAdded,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<DrawingPointType>(
                    value: pointType,
                    decoration: const InputDecoration(
                      labelText: 'Тип точки',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: DrawingPointType.thickness, child: Text('Толщинометрия')),
                      DropdownMenuItem(value: DrawingPointType.ndt, child: Text('НК (ВИК/УЗК/ПВК)')),
                      DropdownMenuItem(value: DrawingPointType.reference, child: Text('Опорная')),
                      DropdownMenuItem(value: DrawingPointType.custom, child: Text('Произвольная')),
                    ],
                    onChanged: p.isUserAdded
                        ? (v) {
                            if (v != null) setLocal(() => pointType = v);
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: expectedCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Проектное (мм)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          enabled: p.isUserAdded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: actualCtrl,
                          autofocus: p.actualValue == null,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Факт (мм) *',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            labelStyle: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Примечание',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _points = _points.map((x) {
                            if (x.id != p.id) return x;
                            return x.copyWith(
                              label: labelCtrl.text.trim().isEmpty ? x.label : labelCtrl.text.trim(),
                              pointType: pointType,
                              expectedValue: double.tryParse(expectedCtrl.text.replaceAll(',', '.')),
                              actualValue: double.tryParse(actualCtrl.text.replaceAll(',', '.')),
                              notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                            );
                          }).toList();
                        });
                        Navigator.of(ctx).pop();
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Сохранить точку'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _save() {
    Navigator.of(context).pop(_points);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filledCount = _points.where((p) => p.actualValue != null).length;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackgroundDeep : AppColors.lightBackground,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(widget.template.name, style: const TextStyle(fontSize: 16)),
            if (widget.equipmentName != null)
              Text(
                widget.equipmentName!,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
              ),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$filledCount / ${_points.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Сохранить',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildCanvas(isDark)),
          _buildPointsPanel(isDark),
        ],
      ),
    );
  }

  Widget _buildCanvas(bool isDark) {
    if (!_hasLocalImage) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_download, size: 48, color: AppColors.warning),
              const SizedBox(height: 8),
              const Text(
                'Изображение шаблона не закешировано.\nПодключитесь к сети и синхронизируйте данные.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      return InteractiveViewer(
        transformationController: _transformCtrl,
        boundaryMargin: const EdgeInsets.all(32),
        minScale: 0.5,
        maxScale: 6,
        child: Center(
          child: _ImageWithPoints(
            imageFile: File(widget.template.localImagePath!),
            points: _points,
            selectedId: _selectedId,
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
            onImageSize: (s) {
              if (_imageRenderSize == null ||
                  _imageRenderSize!.width != s.width ||
                  _imageRenderSize!.height != s.height) {
                _imageRenderSize = s;
              }
            },
            onLongPress: _onLongPress,
            onPointTap: _onPointTap,
            onPointDrag: _movePoint,
          ),
        ),
      );
    });
  }

  Widget _buildPointsPanel(bool isDark) {
    if (_points.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: isDark ? AppColors.darkSurface : Colors.white,
        child: Text(
          'Long-press по чертежу — добавить свою точку.\nТап по точке — ввести значение.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        itemCount: _points.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = _points[i];
          final filled = p.actualValue != null;
          final color = _pointColor(p.pointType);
          return InkWell(
            onTap: () => _onPointTap(p),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 108,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: filled ? color.withValues(alpha: 0.12) : (isDark ? Colors.black26 : Colors.grey.shade100),
                border: Border.all(
                  color: _selectedId == p.id ? AppColors.accent : color.withValues(alpha: 0.4),
                  width: _selectedId == p.id ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(
                          p.label.length > 2 ? p.label.substring(0, 2) : p.label,
                          style: const TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          p.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    filled ? '${p.actualValue!.toStringAsFixed(2)} мм' : '— не задано',
                    style: TextStyle(
                      fontSize: 12,
                      color: filled ? color : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (p.expectedValue != null)
                    Text(
                      'пр. ${p.expectedValue!.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Color _pointColor(DrawingPointType t) {
  switch (t) {
    case DrawingPointType.thickness:
      return AppColors.accent;
    case DrawingPointType.ndt:
      return AppColors.warning;
    case DrawingPointType.reference:
      return AppColors.textSecondary;
    case DrawingPointType.custom:
      return AppColors.success;
  }
}

/// Виджет изображения с наложенными точками.
/// Использует [Image.file] + [LayoutBuilder] для пересчёта % → px в момент build.
class _ImageWithPoints extends StatefulWidget {
  final File imageFile;
  final List<DrawingTemplatePoint> points;
  final String? selectedId;
  final double maxWidth;
  final double maxHeight;
  final void Function(Size renderSize) onImageSize;
  final void Function(Offset local, Size renderSize) onLongPress;
  final void Function(DrawingTemplatePoint p) onPointTap;
  final void Function(DrawingTemplatePoint p, Offset local, Size renderSize) onPointDrag;

  const _ImageWithPoints({
    required this.imageFile,
    required this.points,
    required this.selectedId,
    required this.maxWidth,
    required this.maxHeight,
    required this.onImageSize,
    required this.onLongPress,
    required this.onPointTap,
    required this.onPointDrag,
  });

  @override
  State<_ImageWithPoints> createState() => _ImageWithPointsState();
}

class _ImageWithPointsState extends State<_ImageWithPoints> {
  Size? _natural;

  @override
  void initState() {
    super.initState();
    _loadNaturalSize();
  }

  Future<void> _loadNaturalSize() async {
    final image = Image.file(widget.imageFile);
    final completer = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() {
          _natural = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
      }
    });
    image.image.resolve(const ImageConfiguration()).addListener(completer);
  }

  @override
  Widget build(BuildContext context) {
    if (_natural == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      );
    }
    // Fit image inside maxWidth / maxHeight, preserving aspect
    final ar = _natural!.width / _natural!.height;
    double w = widget.maxWidth;
    double h = w / ar;
    if (h > widget.maxHeight) {
      h = widget.maxHeight;
      w = h * ar;
    }
    final renderSize = Size(w, h);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onImageSize(renderSize));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (d) => widget.onLongPress(d.localPosition, renderSize),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.file(widget.imageFile, fit: BoxFit.fill),
            ),
            for (final p in widget.points)
              _PositionedPoint(
                p: p,
                selected: p.id == widget.selectedId,
                renderSize: renderSize,
                onTap: () => widget.onPointTap(p),
                onDrag: (local) => widget.onPointDrag(p, local, renderSize),
              ),
          ],
        ),
      ),
    );
  }
}

class _PositionedPoint extends StatelessWidget {
  final DrawingTemplatePoint p;
  final bool selected;
  final Size renderSize;
  final VoidCallback onTap;
  final void Function(Offset local) onDrag;

  const _PositionedPoint({
    required this.p,
    required this.selected,
    required this.renderSize,
    required this.onTap,
    required this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    const double size = 26;
    final left = renderSize.width * p.xPercent / 100 - size / 2;
    final top = renderSize.height * p.yPercent / 100 - size / 2;
    final color = _pointColor(p.pointType);
    final filled = p.actualValue != null;
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        onPanUpdate: p.isUserAdded
            ? (d) {
                final renderBox = context.findRenderObject() as RenderBox?;
                if (renderBox == null) return;
                // Преобразуем глобальные координаты к локальным координатам изображения:
                final ancestor = renderBox.parent;
                if (ancestor is RenderBox) {
                  final local = ancestor.globalToLocal(d.globalPosition);
                  onDrag(local);
                }
              }
            : null,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : color.withValues(alpha: 0.5),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 4,
                spreadRadius: 0.5,
              ),
              if (selected)
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.8),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            p.label.length > 3 ? p.label.substring(0, 3) : p.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
