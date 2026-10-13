import 'package:flutter/material.dart';

/// Coordinates are local to the owning part, independent of measurement points.
const vesselElementNames = <String, String>{
  'nozzle': 'Штуцер',
  'manway': 'Люк',
  'instrument': 'Бобышка КИП',
  'drain': 'Дренаж',
  'vent': 'Воздушник',
  'pad': 'Укрепляющая накладка',
  'support': 'Опора',
  'lug': 'Строповая проушина',
};

void paintVesselElement(Canvas c, Offset p, String kind, {double radius = 10, bool engineering = false}) {
  if (engineering && (kind == 'nozzle' || kind == 'manway')) {
    final line = Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1.3;
    c.drawCircle(p, radius, line);
    if (kind == 'manway') c.drawCircle(p, radius * .87, line);
    final axis = Paint()..color = Colors.grey..strokeWidth = .6;
    c.drawLine(p - Offset(radius + 4, 0), p + Offset(radius + 4, 0), axis);
    c.drawLine(p - Offset(0, radius + 4), p + Offset(0, radius + 4), axis);
    return;
  }
  if(engineering && kind=='support'){c.drawRect(Rect.fromCenter(center:p,width:12,height:40),Paint()..color=Colors.black..style=PaintingStyle.stroke);return;}
  final ink = Paint()
    ..color = const Color(0xff245a91)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final r = radius;
  if (kind == 'support' || kind == 'pad') {
    c.drawRect(Rect.fromCenter(center: p, width: r * 2, height: r * 1.5), ink);
    if (kind == 'support') {
      c.drawLine(p + Offset(-r * 1.4, r), p + Offset(r * 1.4, r), ink);
    }
  } else if (kind == 'manway') {
    c.drawOval(Rect.fromCenter(center: p, width: r * 2.8, height: r * 2), ink);
    c.drawOval(Rect.fromCenter(center: p, width: r * 2, height: r * 1.2), ink);
  } else {
    c.drawCircle(p, r, ink);
    if (kind == 'manway' || kind == 'nozzle' || kind == 'pad') {
      c.drawCircle(p, r * .6, ink);
    }
    if (kind == 'instrument') {
      c.drawLine(p + Offset(-r, 0), p + Offset(r, 0), ink);
      c.drawLine(p + Offset(0, -r), p + Offset(0, r), ink);
    }
    if (kind == 'drain' || kind == 'vent') {
      final sign = kind == 'drain' ? 1.0 : -1.0;
      c.drawLine(p, p + Offset(0, sign * r * 1.8), ink);
      c.drawLine(p + Offset(-r * .5, sign * r * 1.2),
          p + Offset(0, sign * r * 1.8), ink);
      c.drawLine(p + Offset(r * .5, sign * r * 1.2),
          p + Offset(0, sign * r * 1.8), ink);
    }
    if (kind == 'lug') {
      c.drawRect(Rect.fromLTRB(p.dx - r, p.dy, p.dx + r, p.dy + r * 1.5), ink);
    }
  }
}

class VesselElementsEditor extends StatefulWidget {
  final int shellCount;
  final String orientation;
  final List<Map<String, dynamic>> elements;
  final VoidCallback onChanged;
  const VesselElementsEditor(
      {super.key,
      required this.shellCount,
      required this.orientation,
      required this.elements,
      required this.onChanged});
  @override
  State<VesselElementsEditor> createState() => _VesselElementsEditorState();
}

class _VesselElementsEditorState extends State<VesselElementsEditor> {
  String part = 'shell_1';
  String kind = 'nozzle';
  String? selected;
  Map<String, dynamic>? get active {
    for (final e in widget.elements) {
      if (e['id'] == selected) return e;
    }
    return null;
  }

  void change(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  void locate(Offset p, Size size) {
    final e = active;
    if (e == null) return;
    var x = ((p.dx - 24) / (size.width - 48)).clamp(.06, .94).toDouble();
    var y = ((p.dy - 24) / (size.height - 48)).clamp(.06, .94).toDouble();
    if (part.startsWith('head')) {
      final d = Offset(x - .5, y - .5);
      if (d.distance > .42) {
        x = .5 + d.dx / d.distance * .42;
        y = .5 + d.dy / d.distance * .42;
      }
    }
    change(() {
      e['x'] = x;
      e['y'] = y;
    });
  }

  @override
  Widget build(BuildContext context) {
    final parts = <String, String>{
      'head_top':
          widget.orientation == 'horizontal' ? 'Левое днище' : 'Верхнее днище',
      for (var i = 1; i <= widget.shellCount; i++) 'shell_$i': 'Обечайка $i',
      'head_bottom':
          widget.orientation == 'horizontal' ? 'Правое днище' : 'Нижнее днище',
    };
    if (!parts.containsKey(part)) part = 'shell_1';
    final current = widget.elements.where((e) => e['part_id'] == part).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
          'Выберите часть → добавьте элемент → укажите место на чертеже'),
      Wrap(
          spacing: 6,
          children: parts.entries
              .map((p) => ChoiceChip(
                    label: Text(
                        '${p.value} (${widget.elements.where((e) => e['part_id'] == p.key).length})'),
                    selected: part == p.key,
                    onSelected: (_) => setState(() {
                      part = p.key;
                      selected = null;
                    }),
                  ))
              .toList()),
      const SizedBox(height: 12),
      Wrap(
          spacing: 6,
          children: vesselElementNames.entries
              .map((e) => ChoiceChip(
                    avatar: CustomPaint(
                        size: const Size(28, 28),
                        painter: _SymbolPainter(e.key)),
                    label: Text(e.value),
                    selected: kind == e.key,
                    onSelected: (_) => setState(() => kind = e.key),
                  ))
              .toList()),
      FilledButton.icon(
          icon: const Icon(Icons.add),
          label: Text('Добавить: ${vesselElementNames[kind]}'),
          onPressed: () => change(() {
                final id = 'E${DateTime.now().microsecondsSinceEpoch}';
                var number = 1;
                while (widget.elements.any((e) => e['label'] == 'Э$number')) {
                  number++;
                }
                widget.elements.add({
                  'id': id,
                  'kind': kind,
                  'part_id': part,
                  'x': .5,
                  'y': .5,
                  'label': 'Э$number',
                  'dn': 50,
                  'control_points': 0
                });
                selected = id;
              })),
      AspectRatio(
          aspectRatio: 1.3,
          child: LayoutBuilder(builder: (context, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            return GestureDetector(
              onTapDown: (d) {
                for (final e in current.reversed) {
                  final p = Offset(
                      24 + (size.width - 48) * (e['x'] as num).toDouble(),
                      24 + (size.height - 48) * (e['y'] as num).toDouble());
                  if ((p - d.localPosition).distance < 24) {
                    setState(() => selected = e['id'] as String);
                    return;
                  }
                }
                locate(d.localPosition, size);
              },
              onPanUpdate: (d) => locate(d.localPosition, size),
              child: CustomPaint(
                  painter: VesselPartPainter(
                      current, part.startsWith('head'), selected),
                  child: const SizedBox.expand()),
            );
          })),
      const Text(
          'Нажмите на элемент для выбора. Перемещайте выбранный элемент пальцем.'),
      Wrap(
          spacing: 6,
          children: current
              .map((e) => ChoiceChip(
                  label: Text(
                      '${e['label']} · ${vesselElementNames[e['kind']] ?? e['kind']}'),
                  selected: selected == e['id'],
                  onSelected: (_) =>
                      setState(() => selected = e['id'] as String)))
              .toList()),
      if (active != null) ...[
        TextFormField(
            key: ValueKey('$selected-label'),
            initialValue: active!['label'] as String,
            decoration: const InputDecoration(labelText: 'Обозначение'),
            onChanged: (v) => change(() => active!['label'] = v)),
        TextFormField(
            key: ValueKey('$selected-dn'),
            initialValue: '${active!['dn'] ?? 50}',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'ДУ / размер, мм'),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n > 0) change(() => active!['dn'] = n);
            }),
        DropdownButtonFormField<int>(
            key: ValueKey('$selected-control'),
            value: (active!['control_points'] as num?)?.toInt() ?? 0,
            decoration: const InputDecoration(
                labelText: 'Обозначения контроля (по примеру Visio)'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Без точек')),
              DropdownMenuItem(value: 2, child: Text('2 точки')),
              DropdownMenuItem(value: 4, child: Text('4 точки'))
            ],
            onChanged: (v) => change(() => active!['control_points'] = v ?? 0)),
        TextButton.icon(
            onPressed: () => change(() {
                  widget.elements.removeWhere((e) => e['id'] == selected);
                  selected = null;
                }),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Удалить элемент')),
      ],
    ]);
  }
}

class _SymbolPainter extends CustomPainter {
  final String kind;
  _SymbolPainter(this.kind);
  @override
  void paint(Canvas c, Size s) =>
      paintVesselElement(c, s.center(Offset.zero), kind, radius: 7);
  @override
  bool shouldRepaint(covariant _SymbolPainter old) => old.kind != kind;
}

class VesselPartPainter extends CustomPainter {
  final List<Map<String, dynamic>> elements;
  final bool head;
  final String? selected;
  VesselPartPainter(this.elements, this.head, this.selected);
  @override
  void paint(Canvas c, Size s) {
    c.drawColor(Colors.white, BlendMode.src);
    final rect = Rect.fromLTWH(24, 24, s.width - 48, s.height - 48);
    final ink = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (head) {
      c.drawOval(rect, ink);
    } else {
      c.drawRect(rect, ink);
    }
    for (final e in elements) {
      final p = Offset(rect.left + rect.width * (e['x'] as num).toDouble(),
          rect.top + rect.height * (e['y'] as num).toDouble());
      if (e['id'] == selected) {
        c.drawCircle(p, 22, Paint()..color = const Color(0x33245a91));
      }
      paintVesselElement(c, p, e['kind'] as String);
      final text = TextPainter(
          text: TextSpan(
              text: '${e['label']}',
              style: const TextStyle(color: Colors.black, fontSize: 12)),
          textDirection: TextDirection.ltr)
        ..layout();
      text.paint(c, p + const Offset(14, -16));
      final count = (e['control_points'] as num?)?.toInt() ?? 0;
      for (var i = 0; i < count; i++) {
        final d = [
          const Offset(0, -17),
          const Offset(0, 17),
          const Offset(-17, 0),
          const Offset(17, 0)
        ][i];
        c.drawCircle(p + d, 2, Paint()..color = Colors.red);
      }
    }
  }

  @override
  bool shouldRepaint(covariant VesselPartPainter old) => true;
}
