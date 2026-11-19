import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/vessel_geometry.dart';
import '../models/vessel_editor_tools.dart';
import 'vessel_drawing.dart';

class VesselEditorCanvas extends StatefulWidget {
  final VesselGeometry geometry;
  final String? selection, detail;
  final bool exteriorB, grid, snap, snapWelds, ruler;
  final int divisions;
  final Set<String> hiddenLayers;
  final String layer;
  final TransformationController transform;
  final void Function(Offset, VesselDrawingLayout) onTap;
  final void Function(String) onSelect;
  final Future<void> Function(String, Map<String, dynamic>) onMove;
  const VesselEditorCanvas(
      {super.key,
      required this.geometry,
      required this.transform,
      required this.onTap,
      required this.onSelect,
      required this.onMove,
      this.selection,
      this.detail,
      this.exteriorB = false,
      this.grid = false,
      this.snap = false,
      this.snapWelds = false,
      this.ruler = false,
      this.divisions = 20,
      this.layer = 'Все',
      this.hiddenLayers = const {}});
  @override
  State<VesselEditorCanvas> createState() => VesselEditorCanvasState();
}

class VesselEditorCanvasState extends State<VesselEditorCanvas> {
  final _sheet = GlobalKey(), _viewport = GlobalKey();
  String? _dragId;
  Offset? _start, _origin;
  VesselDrawingLayout? _dragLayout;
  Map<String, dynamic>? _placement;
  VesselGeometry? _preview;
  Offset? _rulerA, _rulerB;
  String? _rulerPart;
  String _readout = '';

  Offset _local(Offset global) =>
      (_sheet.currentContext!.findRenderObject() as RenderBox)
          .globalToLocal(global);
  double _tolerance() {
    final box = _sheet.currentContext!.findRenderObject() as RenderBox;
    final scale =
        (box.localToGlobal(const Offset(1, 0)) - box.localToGlobal(Offset.zero))
            .distance;
    return 18 / scale;
  }

  String? _draggable(VesselDrawingLayout layout, Offset global) {
    if (widget.ruler) return null;
    final p = _local(global), tolerance = _tolerance();
    final candidates = layout.marks.entries
        .where((m) =>
            !widget.hiddenLayers.contains(
                widget.geometry.entity(m.key)!.containsKey('owner_id')
                    ? 'Точки'
                    : 'Элементы') &&
            VesselEditorTools.movable(
                widget.geometry, widget.geometry.entity(m.key)!) &&
            (m.value - p).distance <= tolerance)
        .toList()
      ..sort(
          (a, b) => (a.value - p).distance.compareTo((b.value - p).distance));
    if (candidates.any((e) => e.key == widget.selection))
      return widget.selection;
    if (candidates.isNotEmpty) return candidates.first.key;
    for (final entry in widget.hiddenLayers.contains('Швы')
        ? <MapEntry<String, (Offset, Offset)>>[]
        : layout.weldLines.entries) {
      if (entry.key == widget.selection &&
          VesselEditorTools.movable(
              widget.geometry, widget.geometry.entity(entry.key)!) &&
          lineDistance(p, entry.value.$1, entry.value.$2) <= tolerance)
        return entry.key;
    }
    return null;
  }

  void _begin(DragStartDetails d, VesselDrawingLayout layout) {
    final id = _draggable(layout, d.globalPosition);
    if (id == null) return;
    widget.onSelect(id);
    setState(() {
      _dragId = id;
      _dragLayout = layout;
      _start = _local(d.globalPosition);
      _origin = layout.marks[id] ?? _start;
    });
  }

  void _update(DragUpdateDetails d) {
    if (_dragId == null) return;
    final layout = _dragLayout!, e = widget.geometry.entity(_dragId)!;
    final at = _origin! + _local(d.globalPosition) - _start!;
    Map<String, dynamic>? placement;
    if (e['kind'] == 'longitudinal') {
      final r = layout.parts[(e['connected_part_ids'] as List).first];
      if (r != null && r.contains(at)) {
        final q = widget.geometry.data['orientation'] == 'horizontal'
            ? (at.dy - r.top) / r.height
            : (at.dx - r.left) / r.width;
        placement = {
          'theta_deg': ((widget.snap
                          ? (q * widget.divisions).round() / widget.divisions
                          : q) *
                      360 +
                  widget.geometry.cut) %
              360
        };
      }
    } else {
      var target = at;
      final r = layout.ownerRect(e);
      if (r != null && r.contains(at)) {
        if (widget.snap)
          target = Offset(
              r.left +
                  ((at.dx - r.left) / r.width * widget.divisions).round() /
                      widget.divisions *
                      r.width,
              r.top +
                  ((at.dy - r.top) / r.height * widget.divisions).round() /
                      widget.divisions *
                      r.height);
        if (widget.snapWelds) {
          final lines = layout.weldLines.entries.where((w) =>
              (widget.geometry.entity(w.key)!['connected_part_ids'] as List)
                  .contains(e['parent_id'] ?? e['owner_id']));
          for (final line in lines) {
            if (lineDistance(target, line.value.$1, line.value.$2) <
                _tolerance() / 2) {
              target = nearestOnLine(target, line.value.$1, line.value.$2);
              break;
            }
          }
        }
        placement = layout.placementAt(e, target);
      }
    }
    setState(() {
      _placement = placement;
      if (placement == null) {
        _preview = null;
        _readout = 'Место вне выбранной детали';
        return;
      }
      _preview ??= VesselGeometry.load(widget.geometry.data);
      VesselEditorTools.move(_preview!, _dragId!, placement);
      _readout = placement['mode'] == 'physical' ||
              placement['theta_deg'] != null
          ? '${placement['z_local_mm'] != null ? 'z = ${(placement['z_local_mm'] as num).toStringAsFixed(1)} мм · ' : ''}φ = ${(placement['theta_deg'] as num).toStringAsFixed(1)}°'
          : 'Координаты: ${((placement['u'] as num) * 100).toStringAsFixed(1)}% / ${((placement['v'] as num) * 100).toStringAsFixed(1)}%';
    });
  }

  Future<void> _end() async {
    final id = _dragId, value = _placement;
    setState(() {
      _dragId = null;
      _preview = null;
      _placement = null;
      _readout = '';
    });
    if (id != null && value != null) await widget.onMove(id, value);
  }

  void _cancel() => setState(() {
        _dragId = null;
        _preview = null;
        _placement = null;
        _readout = '';
      });

  void focusObject(String id) {
    widget.transform.value = Matrix4.identity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _sheet.currentContext == null) return;
      final layout = VesselDrawingLayout(
          widget.geometry, vesselSheetSize(widget.geometry),
          detail: widget.detail, exteriorB: widget.exteriorB);
      final point = layout.marks[id] ??
          layout.parts[id]?.center ??
          layout.weldLines[id]?.$1;
      if (point == null) return;
      final box = _viewport.currentContext!.findRenderObject() as RenderBox;
      final sheet = _sheet.currentContext!.findRenderObject() as RenderBox;
      final anchor = box.globalToLocal(sheet.localToGlobal(point));
      const scale = 1.8;
      widget.transform.value = Matrix4.identity()
        ..translate(box.size.width / 2 - anchor.dx * scale,
            box.size.height / 2 - anchor.dy * scale)
        ..scale(scale);
    });
  }

  void _measure(Offset p, VesselDrawingLayout layout) {
    final owners = layout.parts.entries.where((e) => e.value.contains(p));
    if (owners.isEmpty) return;
    final part = owners.first;
    if(widget.geometry.entity(part.key)?['kind']!='shell' && (p-part.value.center).distance>part.value.width/2) return;
    setState(() {
      if (_rulerA == null || _rulerB != null || _rulerPart != part.key) {
        _rulerPart = part.key;
        _rulerA = p;
        _rulerB = null;
        _readout = 'Линейка: укажите вторую точку на той же детали';
      } else {
        _rulerB = p;
        final r = part.value;
        math.Point<double> unit(Offset at) {
          final x = (at.dx - r.left) / r.width, y = (at.dy - r.top) / r.height;
          return widget.geometry.entity(part.key)?['kind'] == 'shell' &&
                  widget.geometry.data['orientation'] != 'horizontal'
              ? math.Point(y, x)
              : math.Point(x, y);
        }

        final mm = VesselEditorTools.distance(widget.geometry,
            widget.geometry.entity(part.key)!, unit(_rulerA!), unit(p));
        _readout = mm == null
            ? 'Задайте размеры детали для измерения в мм'
            : '${widget.geometry.entity(part.key)?['kind'] == 'shell' ? 'По развёртке' : 'По проекции'}: ${mm.toStringAsFixed(1)} мм';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = VesselDrawingLayout(
        _preview ?? widget.geometry, vesselSheetSize(widget.geometry),
        detail: widget.detail, exteriorB: widget.exteriorB);
    return Stack(key: _viewport, children: [
      Positioned.fill(
          child: ClipRect(
              child: InteractiveViewer(
                  transformationController: widget.transform,
                  minScale: .25,
                  maxScale: 5,
                  panEnabled: _dragId == null && !widget.ruler,
                  child: FittedBox(
                      child: RawGestureDetector(
                          key: _sheet,
                          gestures: {
                            _ObjectPan: GestureRecognizerFactoryWithHandlers<
                                    _ObjectPan>(
                                () => _ObjectPan(),
                                (recognizer) => recognizer
                                  ..acceptAt = ((global) =>
                                      _draggable(layout, global) != null)
                                  ..dragStartBehavior = DragStartBehavior.down
                                  ..onStart = ((d) => _begin(d, layout))
                                  ..onUpdate = _update
                                  ..onEnd = ((_) => _end())
                                  ..onCancel = _cancel)
                          },
                          child: GestureDetector(
                              onTapUp: (d) => widget.ruler
                                  ? _measure(d.localPosition, layout)
                                  : widget.onTap(d.localPosition, layout),
                              child: CustomPaint(
                                  size: layout.size,
                                  painter: VesselDrawingPainter(layout,
                                      selection: widget.selection,
                                      layer: widget.layer,
                                      hiddenLayers: widget.hiddenLayers),
                                  foregroundPainter: _EditorOverlay(layout,
                                      grid: widget.grid,
                                      divisions: widget.divisions,
                                      selection: widget.selection,
                                      a: widget.ruler ? _rulerA : null,
                                      b: widget.ruler ? _rulerB : null)))))))),
      if (_readout.isNotEmpty || widget.ruler)
        Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: IgnorePointer(
                child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(_readout.isEmpty
                            ? 'Линейка: укажите две точки одной детали'
                            : _readout))))),
    ]);
  }
}

class _ObjectPan extends PanGestureRecognizer {
  bool Function(Offset)? acceptAt;
  @override
  bool isPointerAllowed(PointerEvent event) =>
      (acceptAt?.call(event.position) ?? false) &&
      super.isPointerAllowed(event);
}

Offset nearestOnLine(Offset p, Offset a, Offset b) {
  final d = b - a, length = d.dx * d.dx + d.dy * d.dy;
  if (length == 0) return a;
  return a +
      d * (((p - a).dx * d.dx + (p - a).dy * d.dy) / length).clamp(0.0, 1.0);
}

double lineDistance(Offset p, Offset a, Offset b) =>
    (p - nearestOnLine(p, a, b)).distance;

class _EditorOverlay extends CustomPainter {
  final VesselDrawingLayout layout;
  final bool grid;
  final int divisions;
  final String? selection;
  final Offset? a, b;
  _EditorOverlay(this.layout,
      {required this.grid,
      required this.divisions,
      this.selection,
      this.a,
      this.b});
  @override
  void paint(Canvas c, Size size) {
    if (grid)
      for (final r in layout.parts.values) {
        final p = Paint()
          ..color = const Color(0x223579c9)
          ..strokeWidth = .6;
        for (var i = 1; i < divisions; i++) {
          c.drawLine(Offset(r.left + r.width * i / divisions, r.top),
              Offset(r.left + r.width * i / divisions, r.bottom), p);
          c.drawLine(Offset(r.left, r.top + r.height * i / divisions),
              Offset(r.right, r.top + r.height * i / divisions), p);
        }
      }
    final line = layout.weldLines[selection];
    if (line != null)
      c.drawLine(
          line.$1,
          line.$2,
          Paint()
            ..color = Colors.blue
            ..strokeWidth = 3);
    if (a != null) {
      final p = Paint()
        ..color = Colors.deepOrange
        ..strokeWidth = 2;
      c.drawCircle(a!, 5, p);
      if (b != null) {
        c.drawCircle(b!, 5, p);
        c.drawLine(a!, b!, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EditorOverlay oldDelegate) => true;
}
