import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Редактор зон УЗК / МПК на схеме сосуда.
///
/// Сохраняет список зон в формате:
/// `{weld_label|nozzle_label, extent_start, extent_end, band_width, radius_percent?}`
/// либо прямоугольник `{x_percent,y_percent,width_percent,height_percent}`.
class NdtZoneEditorScreen extends StatefulWidget {
  final String layer; // uzk | mpk
  final File? schemeImage;
  final Map<String, dynamic>? geometry;
  final List<Map<String, dynamic>>? existingZones;
  final String title;

  const NdtZoneEditorScreen({
    super.key,
    required this.layer,
    this.schemeImage,
    this.geometry,
    this.existingZones,
    this.title = 'Зоны контроля',
  });

  @override
  State<NdtZoneEditorScreen> createState() => _NdtZoneEditorScreenState();
}

class _NdtZoneEditorScreenState extends State<NdtZoneEditorScreen> {
  late List<_WeldZoneItem> _welds;
  late List<_NozzleZoneItem> _nozzles;
  final List<_RectZone> _rects = [];
  int? _selectedRect;

  bool get _isUzk => widget.layer.toLowerCase() == 'uzk';

  @override
  void initState() {
    super.initState();
    _welds = _buildWeldItems();
    _nozzles = _buildNozzleItems();
    _applyExisting(widget.existingZones ?? []);
  }

  List<_WeldZoneItem> _buildWeldItems() {
    final geo = widget.geometry ?? {};
    final raw = geo['welds'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((w) {
            final lab = (w['label'] ?? w['id'] ?? '').toString();
            final kind = (w['kind'] ?? '').toString();
            return _WeldZoneItem(
              label: lab,
              kind: kind.contains('long') ? 'longitudinal' : 'circumferential',
            );
          })
          .where((w) => w.label.isNotEmpty)
          .toList();
    }
    final preset = (geo['weld_preset'] ?? 'long_plus_rings').toString();
    final shell = ((geo['shell_count'] ??
                (geo['shell'] is Map ? (geo['shell'] as Map)['count'] : 1)) as num?)
            ?.toInt() ??
        1;
    final n = shell < 1 ? 1 : shell;
    final items = <_WeldZoneItem>[];
    final ringCount = n + 1;
    for (var i = 0; i < ringCount; i++) {
      items.add(_WeldZoneItem(label: 'К${i + 1}', kind: 'circumferential'));
    }
    if (preset != 'ring_only') {
      var pIdx = 1;
      for (var s = 0; s < n; s++) {
        final dual = preset == 'multi_shell' && n >= 3 && s > 0 && s < n - 1 && s.isOdd;
        final count = dual ? 2 : 1;
        for (var k = 0; k < count; k++) {
          items.add(_WeldZoneItem(label: 'П$pIdx', kind: 'longitudinal'));
          pIdx++;
        }
      }
    }
    return items;
  }

  List<_NozzleZoneItem> _buildNozzleItems() {
    final raw = widget.geometry?['nozzles'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((n) {
          final lab = (n['label'] ?? '').toString();
          final purpose = (n['purpose'] ?? '').toString();
          return _NozzleZoneItem(
            label: lab.isEmpty ? 'Пт' : lab,
            purpose: purpose,
          );
        })
        .where((n) => n.label.isNotEmpty)
        .toList();
  }

  void _applyExisting(List<Map<String, dynamic>> zones) {
    if (zones.isEmpty) {
      // По умолчанию — все швы и патрубки (как fallback all_welds)
      for (final w in _welds) {
        w.enabled = true;
      }
      for (final n in _nozzles) {
        n.enabled = true;
      }
      return;
    }
    for (final w in _welds) {
      w.enabled = false;
    }
    for (final n in _nozzles) {
      n.enabled = false;
    }
    for (final z in zones) {
      final kind = (z['kind'] ?? '').toString();
      if (kind == 'all_welds') {
        for (final w in _welds) {
          w.enabled = true;
        }
        continue;
      }
      if (kind == 'all_nozzles') {
        for (final n in _nozzles) {
          n.enabled = true;
        }
        continue;
      }
      final weld = (z['weld_label'] ?? '').toString();
      final nzz = (z['nozzle_label'] ?? '').toString();
      if (weld.isNotEmpty) {
        for (final item in _welds) {
          if (item.label != weld) continue;
          item.enabled = true;
          item.extentStart = _as01(z['extent_start'], 0);
          item.extentEnd = _as01(z['extent_end'], 1);
          item.bandWidth = (z['band_width'] as num?)?.toDouble() ?? 6;
          break;
        }
      }
      if (nzz.isNotEmpty) {
        for (final item in _nozzles) {
          if (item.label != nzz) continue;
          item.enabled = true;
          item.radiusPercent = (z['radius_percent'] as num?)?.toDouble() ?? 2.5;
          break;
        }
      }
      final wp = (z['width_percent'] as num?)?.toDouble();
      final hp = (z['height_percent'] as num?)?.toDouble();
      final xp = (z['x_percent'] as num?)?.toDouble();
      final yp = (z['y_percent'] as num?)?.toDouble();
      if (wp != null && hp != null && xp != null && yp != null && wp > 0 && hp > 0) {
        _rects.add(_RectZone(
          x: xp,
          y: yp,
          w: wp,
          h: hp,
          label: weld.isNotEmpty ? weld : nzz,
        ));
      }
    }
  }

  double _as01(dynamic v, double fallback) {
    if (v == null || v == '') return fallback;
    final d = (v is num) ? v.toDouble() : double.tryParse(v.toString().replaceAll(',', '.'));
    if (d == null) return fallback;
    if (d > 1.0) return (d / 100.0).clamp(0.0, 1.0);
    return d.clamp(0.0, 1.0);
  }

  List<Map<String, dynamic>> _buildResult() {
    final out = <Map<String, dynamic>>[];
    for (final w in _welds.where((e) => e.enabled)) {
      out.add({
        'weld_label': w.label,
        'kind': w.kind,
        'extent_start': double.parse(w.extentStart.toStringAsFixed(3)),
        'extent_end': double.parse(w.extentEnd.toStringAsFixed(3)),
        'band_width': w.bandWidth.round(),
      });
    }
    for (final n in _nozzles.where((e) => e.enabled)) {
      out.add({
        'nozzle_label': n.label,
        'kind': 'nozzle',
        'radius_percent': double.parse(n.radiusPercent.toStringAsFixed(2)),
      });
    }
    for (final r in _rects) {
      out.add({
        'kind': 'rect',
        if (r.label.isNotEmpty) 'weld_label': r.label,
        'x_percent': double.parse(r.x.toStringAsFixed(2)),
        'y_percent': double.parse(r.y.toStringAsFixed(2)),
        'width_percent': double.parse(r.w.toStringAsFixed(2)),
        'height_percent': double.parse(r.h.toStringAsFixed(2)),
      });
    }
    return out;
  }

  void _save() {
    final zones = _buildResult();
    context.pop({
      'layer': widget.layer,
      'zones': zones,
      'zone_key': _isUzk ? 'uzk_zones' : 'mpk_zones',
    });
  }

  void _onSchemeTap(Offset local, Size box) {
    // Режим добавления прямоугольной зоны: тап = центр, размер по умолчанию
    final xp = (local.dx / box.width) * 100;
    final yp = (local.dy / box.height) * 100;
    if (xp < 0 || xp > 100 || yp < 0 || yp > 100) return;
    setState(() {
      _rects.add(_RectZone(
        x: (xp - 4).clamp(0, 96),
        y: (yp - 2).clamp(0, 96),
        w: 8,
        h: 4,
        label: '',
      ));
      _selectedRect = _rects.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = _isUzk ? const Color(0xFF00BED2) : const Color(0xFF32BE46);
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Сохранить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1e293b),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: widget.schemeImage == null
                  ? const Center(
                      child: Text(
                        'Нет схемы. Сначала создайте схему в конструкторе.',
                        style: TextStyle(color: Colors.white54),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          onTapDown: (d) {
                            final box = Size(constraints.maxWidth, constraints.maxHeight);
                            _onSchemeTap(d.localPosition, box);
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              InteractiveViewer(
                                child: Image.file(
                                  widget.schemeImage!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              ..._rects.asMap().entries.map((e) {
                                final i = e.key;
                                final r = e.value;
                                return Positioned(
                                  left: constraints.maxWidth * r.x / 100,
                                  top: constraints.maxHeight * r.y / 100,
                                  width: constraints.maxWidth * r.w / 100,
                                  height: constraints.maxHeight * r.h / 100,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _selectedRect = i),
                                    onPanUpdate: (d) {
                                      setState(() {
                                        r.x = (r.x + d.delta.dx / constraints.maxWidth * 100)
                                            .clamp(0, 100 - r.w);
                                        r.y = (r.y + d.delta.dy / constraints.maxHeight * 100)
                                            .clamp(0, 100 - r.h);
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: _selectedRect == i ? Colors.amber : accent,
                                          width: _selectedRect == i ? 3 : 2,
                                        ),
                                        color: accent.withValues(alpha: 0.18),
                                      ),
                                      child: Align(
                                        alignment: Alignment.bottomRight,
                                        child: GestureDetector(
                                          onPanUpdate: (d) {
                                            setState(() {
                                              r.w = (r.w + d.delta.dx / constraints.maxWidth * 100)
                                                  .clamp(2, 100 - r.x);
                                              r.h = (r.h +
                                                      d.delta.dy / constraints.maxHeight * 100)
                                                  .clamp(1.5, 100 - r.y);
                                            });
                                          },
                                          child: Container(
                                            width: 18,
                                            height: 18,
                                            color: accent,
                                            child: const Icon(Icons.open_in_full,
                                                size: 12, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Тап по схеме — прямоугольная зона. Ниже — швы/патрубки и протяжённость.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
            ),
          ),
          if (_selectedRect != null && _selectedRect! < _rects.length)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Text('Зона ${_selectedRect! + 1}',
                      style: const TextStyle(color: Colors.white70)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () {
                      setState(() {
                        _rects.removeAt(_selectedRect!);
                        _selectedRect = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            flex: 4,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        for (final w in _welds) {
                          w.enabled = true;
                          w.extentStart = 0;
                          w.extentEnd = 1;
                        }
                      }),
                      child: const Text('Все швы'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        for (final w in _welds) {
                          w.enabled = false;
                        }
                      }),
                      child: const Text('Сбросить швы'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        for (final n in _nozzles) {
                          n.enabled = true;
                        }
                      }),
                      child: const Text('Все патрубки'),
                    ),
                  ],
                ),
                const Text('Сварные швы',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                ..._welds.map((w) {
                  return Card(
                    color: const Color(0xFF1e293b),
                    margin: const EdgeInsets.only(top: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${w.label} (${w.kind == 'longitudinal' ? 'продольный' : 'кольцевой'})',
                              style: const TextStyle(color: Colors.white),
                            ),
                            value: w.enabled,
                            activeColor: accent,
                            onChanged: (v) => setState(() => w.enabled = v),
                          ),
                          if (w.enabled) ...[
                            Text(
                              'Протяжённость: ${(w.extentStart * 100).round()}–${(w.extentEnd * 100).round()}%',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            RangeSlider(
                              values: RangeValues(w.extentStart, w.extentEnd),
                              min: 0,
                              max: 1,
                              divisions: 20,
                              activeColor: accent,
                              labels: RangeLabels(
                                '${(w.extentStart * 100).round()}%',
                                '${(w.extentEnd * 100).round()}%',
                              ),
                              onChanged: (v) => setState(() {
                                w.extentStart = v.start;
                                w.extentEnd = v.end;
                              }),
                            ),
                            Text(
                              'Толщина зоны: ${w.bandWidth.round()}',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            Slider(
                              value: w.bandWidth.clamp(4, 20),
                              min: 4,
                              max: 20,
                              divisions: 16,
                              activeColor: accent,
                              onChanged: (v) => setState(() => w.bandWidth = v),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
                if (_nozzles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Патрубки',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                  ..._nozzles.map((n) {
                    return Card(
                      color: const Color(0xFF1e293b),
                      margin: const EdgeInsets.only(top: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            SwitchListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                n.purpose.isEmpty ? n.label : '${n.label} — ${n.purpose}',
                                style: const TextStyle(color: Colors.white),
                              ),
                              value: n.enabled,
                              activeColor: accent,
                              onChanged: (v) => setState(() => n.enabled = v),
                            ),
                            if (n.enabled)
                              Slider(
                                value: n.radiusPercent.clamp(1, 8),
                                min: 1,
                                max: 8,
                                divisions: 14,
                                label: 'R ${n.radiusPercent.toStringAsFixed(1)}%',
                                activeColor: accent,
                                onChanged: (v) => setState(() => n.radiusPercent = v),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeldZoneItem {
  final String label;
  final String kind;
  bool enabled;
  double extentStart;
  double extentEnd;
  double bandWidth;

  _WeldZoneItem({
    required this.label,
    required this.kind,
    this.enabled = false,
    this.extentStart = 0,
    this.extentEnd = 1,
    this.bandWidth = 6,
  });
}

class _NozzleZoneItem {
  final String label;
  final String purpose;
  bool enabled;
  double radiusPercent;

  _NozzleZoneItem({
    required this.label,
    this.purpose = '',
    this.enabled = false,
    this.radiusPercent = 2.5,
  });
}

class _RectZone {
  double x, y, w, h;
  String label;
  _RectZone({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.label = '',
  });
}
