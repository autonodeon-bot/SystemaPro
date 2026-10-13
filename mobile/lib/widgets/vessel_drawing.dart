import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/vessel_geometry.dart';
import '../models/vessel_checklist.dart';
import 'vessel_elements_editor.dart';

/// Project stable constructor point IDs onto the exported overview for the UZT map.
void syncVesselMeasurementProjection(VesselChecklist checklist) {
  final data = checklist.baseVesselScheme?.geometry;
  if (data?['schema_version'] != 2) return;
  const size = Size(1190, 842);
  final layout = VesselDrawingLayout(VesselGeometry.load(data), size);
  for (final row in checklist.thicknessMeasurements) {
    final at = layout.marks[row.schemePointId];
    if (at == null) continue;
    row.xPercent = at.dx / size.width * 100;
    row.yPercent = at.dy / size.height * 100;
  }
  for (final point in checklist.baseVesselScheme!.points) {
    final at = layout.marks[point.id];
    if (at == null) continue;
    point.xPercent = at.dx / size.width * 100;
    point.yPercent = at.dy / size.height * 100;
  }
}

/// The same layout is used for picking, drawing and offscreen export.
class VesselDrawingLayout {
  final VesselGeometry model;
  final Size size;
  final String? detail;
  final bool exteriorB;
  final Map<String, Rect> parts = {};
  final Map<String, Offset> marks = {};
  VesselDrawingLayout(this.model, this.size,
      {this.detail, this.exteriorB = false}) {
    if (detail != null) {
      final part = model.entity(detail);
      final disk = part?['kind'] != 'shell';
      final r = Rect.fromLTWH(70, 65, size.width - 140, size.height - 140);
      parts[detail!] = disk
          ? Rect.fromCenter(
              center: r.center, width: r.shortestSide, height: r.shortestSide)
          : r;
    } else {
      final horizontal = model.data['orientation'] == 'horizontal';
      final body = horizontal
          ? Rect.fromLTWH(
              size.width * .18, 100, size.width * .62, size.height * .68)
          : Rect.fromLTWH(size.width * .2, size.height * .24, size.width * .6,
              size.height * .54);
      final known =
          model.shells.every((s) => s['dimensions']?['length_mm'] != null);
      final total = model.shells.fold<double>(
          0,
          (s, p) =>
              s +
              (known ? (p['dimensions']['length_mm'] as num).toDouble() : 1));
      var cursor = 0.0;
      for (final p in model.shells) {
        final fraction =
            (known ? (p['dimensions']['length_mm'] as num).toDouble() : 1) /
                total;
        parts[p['id']] = horizontal
            ? Rect.fromLTWH(body.left + body.width * cursor, body.top,
                body.width * fraction, body.height)
            : Rect.fromLTWH(body.left, body.top + body.height * cursor,
                body.width, body.height * fraction);
        cursor += fraction;
      }
      final diameter = horizontal
          ? math.min(size.width * .15, body.height * .8)
          : math.min(size.height * .14, body.width * .8);
      for (final p in model.parts.where((p) => p['kind'] == 'head')) {
        final a = p['side'] == 'A';
        final center = horizontal
            ? Offset(a ? size.width * .09 : size.width * .90, size.height * (a ? .46 : .37))
            : Offset(body.center.dx, a ? size.height * .14 : size.height * .88);
        parts[p['id']] = Rect.fromCircle(center: center, radius: diameter / 2);
      }
    }
    if (detail == null) {
      final covers = model.parts.where((p) => p['kind'] == 'cover').toList();
      for (var i = 0; i < covers.length; i++) {
        final diameter = math.min(size.width * .15, size.height * .30 / covers.length);
        parts[covers[i]['id']] = Rect.fromCircle(
          center: Offset(size.width * .90, size.height * (.64 + .30 * (i + .5) / covers.length)),
          radius: diameter / 2);
      }
    }
    for (final e in [
      ...model.elements.where((e) => e['archived'] != true),
      ...model.points.where((p) => p['archived'] != true)
    ]) {
      final owner = model.entity(e['parent_id'] ?? e['owner_id']);
      Rect? r = parts[owner?['id']];
      if (r == null &&
          owner?['parent_id'] != null &&
          owner?['placement'] != null) {
        final parent = parts[owner?['parent_id']];
        if (parent != null) {
          r = Rect.fromCircle(center: project(owner!, parent), radius: symbolRadius(owner, parent));
        }
      }
      if (r != null) marks[e['id']] = project(e, r);
    }
  }
  double symbolRadius(VesselEntity e, Rect ownerRect) {
    final diameter = (e['dimensions']?['diameter_mm'] as num? ?? num.tryParse('${e['dn']}') ?? 100).toDouble();
    final owner = model.entity(e['parent_id']);
    final scale = owner?['kind'] == 'shell'
        ? (model.data['orientation'] == 'horizontal' ? ownerRect.width : ownerRect.height) /
            (owner?['dimensions']?['length_mm'] as num? ?? 2000)
        : ownerRect.width / (owner?['dimensions']?['diameter_mm'] as num? ?? 2000);
    return (diameter * scale / 2).clamp(owner?['kind'] == 'shell' && model.points.any((p) => p['owner_id'] == e['id']) ? 14.0 : 9.0, 38.0);
  }
  Offset project(VesselEntity e, Rect r) {
    final owner = model.entity(e['parent_id'] ?? e['owner_id']);
    final p = model.position(e);
    if (owner?['kind'] == 'shell' &&
        model.data['orientation'] != 'horizontal') {
      return Offset(r.left + p.y * r.width, r.top + p.x * r.height);
    }
    final mirror = exteriorB && owner?['side'] == 'B';
    return Offset(
        r.left + (mirror ? 1 - p.x : p.x) * r.width, r.top + p.y * r.height);
  }

  List<String> hit(Offset p) {
    final found = marks.entries
        .where((e) => (e.value - p).distance <= 24)
        .map((e) => e.key)
        .toList();
    if (found.isNotEmpty) return found;
    return parts.entries
        .where((e) => e.value.contains(p))
        .map((e) => e.key)
        .toList();
  }
}

class VesselDrawingPainter extends CustomPainter {
  final VesselDrawingLayout layout;
  final String? selection;
  final String layer;
  VesselDrawingPainter(this.layout, {this.selection, this.layer = 'Все'});
  void text(Canvas c, String text, Offset p,
      {double size = 13, Color color = Colors.black, double maxWidth = 1100}) {
    final t = TextPainter(
        text: TextSpan(
            text: text,
            style:
                TextStyle(fontSize: size, color: color, fontFamily: 'Roboto')),
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: maxWidth);
    t.paint(c, p);
  }

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final m = layout.model;
    text(
        c,
        'Сосуд • ${layout.detail == null ? 'общий вид' : m.entity(layout.detail)?['designation']} • рев. ${m.data['revision']}',
        const Offset(20, 12),
        size: 17);
    text(
        c,
        'A → B · угол по часовой стрелке со стороны A · разрез ${m.cut}°${layout.exteriorB ? ' · B снаружи' : ''}',
        const Offset(20, 37),
        size: 12);
    for (final entry in layout.parts.entries) {
      final p = m.entity(entry.key)!;
      final r = entry.value;
      final ink = Paint()
        ..color = selection == entry.key ? Colors.blue : Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = selection == entry.key ? 3 : 1.5;
      if (p['kind'] == 'shell') {
        c.drawRect(r, ink);
      } else {
        c.drawOval(r, ink);
        final mirrored = layout.exteriorB && p['side'] == 'B';
        if (layout.detail != null) {
        text(c, '0°', Offset(r.center.dx + 3, r.top - 16), size: 11);
        text(c, mirrored ? '270°' : '90°', Offset(r.right + 3, r.center.dy),
            size: 11);
        text(c, mirrored ? '90°' : '270°', Offset(r.left - 30, r.center.dy),
            size: 11);
        text(c, '180°', Offset(r.center.dx + 3, r.bottom - 16), size: 11);
        }
      }
      text(
          c,
          p['designation'].toString(),
          p['kind'] == 'shell'
              ? Offset(r.left + 6, r.top + 6)
              : Offset(r.left, r.bottom + 4),
          size: p['kind'] == 'shell' ? 10 : 12);
      final dims = p['dimensions'] as Map;
      if (layout.detail != null && r.width > 140 &&
          r.height > 60 &&
          (dims['length_mm'] != null || dims['diameter_mm'] != null)) {
        text(
            c,
            '${p['kind'] == 'shell' ? 'L ${dims['length_mm'] ?? '?'} · ' : ''}D ${dims['diameter_mm'] ?? '?'} мм',
            Offset(r.left + 6, r.top + 22),
            size: 12);
      }
      if (p['kind'] == 'shell') {
        final horizontal = m.data['orientation'] == 'horizontal';
        if (layout.detail != null || entry.key == m.shells.first['id']) for (var i = 0; i < 4; i++) {
          final at = horizontal
              ? Offset(r.left - 34, r.top + r.height * i / 4)
              : Offset(r.left + r.width * i / 4, r.top - 31);
          text(c, '${(m.cut + i * 90) % 360}°', at, size: 10);
        }
        for (final section in (m.data['sections'] as List? ?? [])
            .where((s) => s['kind'] == 'ovality' && s['owner_id'] == p['id'])) {
          final length = (p['dimensions']['length_mm'] as num?)?.toDouble();
          if (length == null) continue;
          final q = (section['z_local_mm'] as num) / length;
          final a = horizontal
              ? Offset(r.left + r.width * q, r.top)
              : Offset(r.left, r.top + r.height * q);
          final b = horizontal ? Offset(a.dx, r.bottom) : Offset(r.right, a.dy);
          for (var j = 0; j < 24; j += 2) {
            c.drawLine(Offset.lerp(a, b, j / 24)!,
                Offset.lerp(a, b, (j + 1) / 24)!, Paint()..color = Colors.grey);
          }
          text(c, section['designation'], a + const Offset(3, 14), size: 12);
        }
        for (final w in m.welds.where((w) =>
            w['kind'] == 'longitudinal' &&
            (w['connected_part_ids'] as List).contains(p['id']))) {
          final q = (((w['geometry']['theta_deg'] as num) - m.cut) % 360) / 360;
          final a = horizontal
              ? Offset(r.left, r.top + r.height * q)
              : Offset(r.left + r.width * q, r.top);
          final b = horizontal ? Offset(r.right, a.dy) : Offset(a.dx, r.bottom);
          c.drawLine(
              a,
              b,
              Paint()
                ..color = Colors.grey
                ..strokeWidth = 1.5);
          text(c, w['designation'], horizontal ? Offset((a.dx+b.dx)/2-10, q>.65 ? a.dy+4 : a.dy-18) : Offset(a.dx+4,(a.dy+b.dy)/2), size: 11);
          var offset = 0.0;
          for (final z in m.zones.where((z) => z['weld_id'] == w['id'])) {
            final methods = (z['planned_methods'] as List).join('/');
            if (layer != 'Все' && !methods.contains(layer)) continue;
            final coverage = z['coverage'] as Map;
            final start = coverage['kind'] == 'whole'
                ? 0.0
                : (coverage['start'] as num).toDouble();
            final end = coverage['kind'] == 'whole'
                ? 1.0
                : (coverage['end'] as num).toDouble();
            final shift = Offset(4 + offset, 4 + offset);
            for (var i = 0; i <= 40; i++) {
              final f = i / 40;
              if (f < start || f > end) continue;
              final point = Offset.lerp(a, b, f)! + shift;
              c.drawCircle(point, 1.5, Paint()..color = Colors.black);
            }
            text(c, methods, Offset.lerp(a, b, (start + end) / 2)! + shift,
                size: 11);
            offset += 12;
          }
        }
      }
    }
    for (final w in m.welds.where((w) => w['kind'] == 'head_joint')) {
      final owner = m.entity((w['connected_part_ids'] as List).first)!;
      final r = layout.parts[owner['id']];
      if (r == null) continue;
      final offset = (w['geometry']['offset_mm'] as num).toDouble() /
          (owner['dimensions']['diameter_mm'] as num) * r.height;
      final half = math.sqrt(math.max(0, r.width * r.width / 4 - offset * offset));
      final at = Offset(r.center.dx, r.center.dy + offset);
      c.drawLine(at - Offset(half, 0), at + Offset(half, 0), Paint()..color = Colors.black..strokeWidth = 2);
      text(c, w['designation'], at + const Offset(8, 3), size: 11);
    }
    for (final w in m.welds.where((w) => w['kind'] == 'circumferential')) {
      final owners = (w['connected_part_ids'] as List)
          .where((id) =>
              m.entity(id)?['kind'] == 'shell' && layout.parts.containsKey(id))
          .toList();
      if (owners.isEmpty) continue;
      final r = layout.parts[owners.first];
      if (r == null) continue;
      final first = owners.first == (w['connected_part_ids'] as List).last;
      final horizontal = m.data['orientation'] == 'horizontal';
      final a = horizontal
          ? Offset(first ? r.left : r.right, r.top)
          : Offset(r.left, first ? r.top : r.bottom);
      final b = horizontal ? Offset(a.dx, r.bottom) : Offset(r.right, a.dy);
      c.drawLine(
          a,
          b,
          Paint()
            ..color = Colors.black
            ..strokeWidth = 2);
      text(c, w['designation'], a + const Offset(2, -17), size: 11);
      var zoneOffset = 0.0;
      for (final z in m.zones.where((z) => z['weld_id'] == w['id'])) {
        final methods = (z['planned_methods'] as List).join('/');
        if (layer != 'Все' && !methods.contains(layer)) continue;
        final coverage = z['coverage'] as Map;
        final whole = coverage['kind'] == 'whole';
        final start =
            whole ? 0.0 : (((coverage['start'] as num) - m.cut) % 360) / 360;
        final span = whole
            ? 1.0
            : VesselGeometry.coverageDegrees(
                    (coverage['start'] as num).toDouble(),
                    (coverage['end'] as num).toDouble()) /
                360;
        text(
            c,
            '$methods ${whole ? '100%' : '${coverage['start']}–${coverage['end']}°'}',
            Offset.lerp(a,b,(start+span/2)%1)! + Offset(10+zoneOffset,0),
            size: 11);
        for (var i = 0; i < 40; i++) {
          if (i / 40 > span) break;
          final f = (start + i / 40) % 1;
          final mark = Offset.lerp(a, b, f)! + Offset(zoneOffset, zoneOffset);
          c.drawLine(
              mark - const Offset(3, 3),
              mark + const Offset(3, 3),
              Paint()
                ..color = Colors.deepOrange
                ..strokeWidth = 2);
        }
        zoneOffset += 10;
      }
    }
    final occupied = <Rect>[];
    for (final mark in layout.marks.entries) {
      final e = m.entity(mark.key)!;
      final point = e.containsKey('owner_id');
      if (point && layer != 'Все' && layer != e['method']) continue;
      if (point) {
        final ink = Paint()..color = Colors.black..strokeWidth = 1.7;
        c.drawLine(mark.value - const Offset(3, 3), mark.value + const Offset(3, 3), ink);
        c.drawLine(mark.value + const Offset(-3, 3), mark.value + const Offset(3, -3), ink);
      } else {
        final r = layout.parts[e['parent_id']];
        paintVesselElement(c, mark.value, e['kind'],
            radius: r == null ? 10 : layout.symbolRadius(e, r), engineering: true);
        if (r != null) for (final w in m.welds.where((w) => w['kind']=='attachment' && w['geometry']['element_id']==e['id'])) {
          for (final z in m.zones.where((z) => z['weld_id']==w['id'])) {
            if (layer!='Все' && !(z['planned_methods'] as List).contains(layer)) continue;
            final radius=layout.symbolRadius(e,r)+3;
            for (var i=0;i<72;i++) {
              final angle=i*5.0,cov=z['coverage'];
              if (cov['kind']=='sector' && (angle-cov['start'])%360>(cov['end']-cov['start'])%360) continue;
              final a=angle*math.pi/180;
              c.drawLine(mark.value+Offset(radius*math.sin(a),-radius*math.cos(a)),mark.value+Offset((radius+4)*math.sin(a+.03),-(radius+4)*math.cos(a+.03)),Paint()..color=Colors.black);
            }
            text(c,z['designation'],mark.value+Offset(radius+8,radius),size:10);
          }
        }
      }
      if (selection == e['id']) {
        c.drawCircle(
            mark.value,
            16,
            Paint()
              ..color = Colors.blue
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
      final label = point
          ? '${e['body_number'] ?? e['local_number']}'
          : '${e['designation']}';
      final override = m.labels[e['id']] as Map?;
      var pos = mark.value +
          Offset((override?['dx'] as num? ?? (point ? -3 : -20)).toDouble(),
              (override?['dy'] as num? ?? (point ? -16 : -30)).toDouble());
      if (point && !['shell', 'head', 'cover'].contains(m.entity(e['owner_id'])?['kind']) && override == null) {
        pos = mark.value + (<int, Offset>{1: const Offset(-12,-5), 2: const Offset(5,-5), 3: const Offset(-3,-16), 4: const Offset(-3,6)}[e['local_number']] ?? const Offset(5,-12));
      }
      if (override == null && !point) {
        for (var i = 0;
            i < 8 &&
                occupied.any(
                    (r) => r.overlaps(Rect.fromLTWH(pos.dx, pos.dy, label.length * 7.0 + 2, 15)));
            i++) {
          pos += const Offset(0, 16);
        }
      }
      pos = Offset(
          pos.dx.clamp(5, size.width - 55), pos.dy.clamp(60, size.height - 45));
      occupied.add(Rect.fromLTWH(pos.dx, pos.dy, label.length * 7.0 + 2, 15));
      if (!point || override != null) c.drawLine(
          mark.value,
          pos,
          Paint()
            ..color = Colors.grey
            ..strokeWidth = .6);
      text(c, label, pos,
          size: point ? 10 : 13, color: Colors.black);
    }
    if (layout.detail == null) {
      for (final section in (m.data['sections'] as List? ?? []).where((s) => s['kind']=='weld_profile')) {
        final x=size.width*.83,y=110.0;
        text(c,'${section['designation']} · профиль шва',Offset(x,y-24),size:11);
        c.drawRect(Rect.fromLTWH(x+60,y+8,30,20),Paint()..color=Colors.grey.shade300);
        c.drawLine(Offset(x,y+18),Offset(x+155,y+18),Paint()..color=Colors.black);
        for(var i=0;i<5;i++) {final px=x+15+i*30;c.drawCircle(Offset(px,y+18),2,Paint()..color=Colors.black);text(c,'${i+1}',Offset(px-3,y-5),size:9);}
        text(c,'Металл · ЗТВ · шов · ЗТВ · металл',Offset(x,y+36),size:9);
        break;
      }
      text(c, '×  Точка УЗТ      К — кольцевой шов      П — продольный / шов днища', Offset(size.width * .20, size.height - 72), size: 12);
      text(c, 'Штриховка — участок НК      I–III — сечения овальности      Крышка Т — отдельная деталь', Offset(size.width * .20, size.height - 52), size: 12);
    }
    text(
        c,
        'Размеры без источника не подтверждены. Точки — план контроля, не результаты.',
        Offset(20, size.height - 24),
        size: 11);
  }

  @override
  bool shouldRepaint(covariant VesselDrawingPainter oldDelegate) => true;
}

void paintVesselSection(
    Canvas canvas, Size size, VesselGeometry model, Map section) {
  final painter = VesselDrawingPainter(VesselDrawingLayout(model, size));
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  painter.text(
      canvas,
      '${section['designation']} • ${model.entity(section['owner_id'])?['designation']} • рев. ${model.data['revision']}',
      const Offset(40, 35),
      size: 24);
  painter.text(
      canvas,
      'План расположения позиций. Метод: ${section['method'] ?? 'не задан'}',
      const Offset(40, 75),
      size: 18);
  final middle = size.height / 2;
  canvas.drawRect(
      Rect.fromLTWH(size.width * .46, middle - 65, size.width * .08, 130),
      Paint()..color = Colors.grey.shade300);
  canvas.drawLine(
      Offset(70, middle),
      Offset(size.width - 70, middle),
      Paint()
        ..color = Colors.black
        ..strokeWidth = 2);
  final names = section['positions'] as List? ??
      ['Основной металл', 'ЗТВ', 'Металл шва', 'ЗТВ', 'Основной металл'];
  for (var i = 0; i < 5; i++) {
    final x = size.width * (.16 + i * .17);
    canvas.drawCircle(Offset(x, middle), 7, Paint()..color = Colors.black);
    painter.text(canvas, '${i + 1}. ${names[i]}', Offset(x - 65, middle + 25),
        size: 18);
  }
  painter.text(
      canvas, section['note']?.toString() ?? '', Offset(40, size.height - 110),
      size: 18);
  painter.text(
      canvas,
      'Значения и единицы измерения заполняются в таблице выбранного метода.',
      Offset(40, size.height - 70),
      size: 18);
}
