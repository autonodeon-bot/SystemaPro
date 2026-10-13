import 'dart:ui';
import 'dart:math' as math;
import '../models/vessel_geometry.dart';
import '../widgets/vessel_drawing.dart';

/// Editable vector companion to the PNG snapshots used by existing reports.
String exportVesselSvg(VesselGeometry model,
    {String? detail, String layer = 'Все', bool exteriorB = false}) {
  final size = vesselSheetSize(model);
  final layout =
      VesselDrawingLayout(model, size, detail: detail, exteriorB: exteriorB);
  String escape(Object? s) => '$s'
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  final out = StringBuffer(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${size.width/4}mm" height="${size.height/4}mm" viewBox="0 0 ${size.width} ${size.height}"><rect width="${size.width}" height="${size.height}" fill="white"/><g stroke="black" fill="none" stroke-width="1.5">');
  final labels = StringBuffer();
  void text(String value, double x, double y, {double font = 12}) => labels
      .write('<text x="$x" y="$y" font-size="$font">${escape(value)}</text>');
  void line(Offset a, Offset b, {String extra = ''}) => out.write(
      '<line x1="${a.dx}" y1="${a.dy}" x2="${b.dx}" y2="${b.dy}" $extra/>');
  text(
      'Сосуд • ${detail == null ? 'общий вид' : model.entity(detail)?['designation']} • рев. ${model.data['revision']}',
      20,
      30,
      font: 18);
  text('A → B · угол по часовой стрелке со стороны A · разрез ${model.cut}°',
      20, 53,
      font: 14);
  for (final entry in layout.parts.entries) {
    final p = model.entity(entry.key)!;
    final r = entry.value;
    if (p['kind'] == 'shell') {
      out.write(
          '<rect x="${r.left}" y="${r.top}" width="${r.width}" height="${r.height}"/>');
    } else {
      out.write(
          '<ellipse cx="${r.center.dx}" cy="${r.center.dy}" rx="${r.width / 2}" ry="${r.height / 2}"/>');
    }
    text(p['designation'], r.left + 6,
        p['kind'] == 'shell' ? r.top + 18 : r.bottom + 16);
  }
  for (final w in model.welds) {
    if (w['kind']=='attachment') continue;
    if (w['kind'] == 'head_joint') {
      final owner=model.entity((w['connected_part_ids'] as List).first)!;
      final r=layout.parts[owner['id']];
      if (r != null) {
        final offset=(w['geometry']['offset_mm'] as num)/(owner['dimensions']['diameter_mm'] as num)*r.height;
        final half=math.sqrt(math.max(0,r.width*r.width/4-offset*offset));
        final at=Offset(r.center.dx,r.center.dy+offset);
        line(at-Offset(half,0),at+Offset(half,0));text(w['designation'],at.dx+8,at.dy+14);
      }
      continue;
    }
    final owners = (w['connected_part_ids'] as List).where((id) =>
        layout.parts.containsKey(id) && model.entity(id)?['kind'] == 'shell');
    if (owners.isEmpty) continue;
    final r = layout.parts[owners.first]!;
    final horizontal = model.data['orientation'] == 'horizontal';
    final ring = w['kind'] == 'circumferential';
    late Offset a, b;
    if (ring) {
      final first = owners.first == (w['connected_part_ids'] as List).last;
      a = horizontal
          ? Offset(first ? r.left : r.right, r.top)
          : Offset(r.left, first ? r.top : r.bottom);
      b = horizontal ? Offset(a.dx, r.bottom) : Offset(r.right, a.dy);
    } else {
      final q = (((w['geometry']['theta_deg'] as num) - model.cut) % 360) / 360;
      a = horizontal
          ? Offset(r.left, r.top + r.height * q)
          : Offset(r.left + r.width * q, r.top);
      b = horizontal ? Offset(r.right, a.dy) : Offset(a.dx, r.bottom);
    }
    line(a, b);
    text(w['designation'], a.dx + 3, a.dy - 4);
    for (final z in model.zones.where((z) => z['weld_id'] == w['id'])) {
      final methods = (z['planned_methods'] as List).join('/');
      if (layer != 'Все' && !methods.contains(layer)) continue;
      final cov = z['coverage'] as Map;
      final whole = cov['kind'] == 'whole';
      final start = whole
          ? 0.0
          : ring
              ? (((cov['start'] as num) - model.cut) % 360) / 360
              : (cov['start'] as num).toDouble();
      final span = whole
          ? 1.0
          : ring
              ? VesselGeometry.coverageDegrees((cov['start'] as num).toDouble(),
                      (cov['end'] as num).toDouble()) /
                  360
              : ((cov['end'] as num) - (cov['start'] as num)).toDouble();
      final alongX=(b.dx-a.dx).abs()>(b.dy-a.dy).abs();
      for(final range in [[start,math.min(1.0,start+span)],if(start+span>1)[0.0,start+span-1]]) {
        final lo=Offset.lerp(a,b,range[0])!,hi=Offset.lerp(a,b,range[1])!;
        out.write('<rect x="${lo.dx-(alongX?0:6)}" y="${lo.dy-(alongX?6:0)}" width="${hi.dx-lo.dx+(alongX?0:12)}" height="${hi.dy-lo.dy+(alongX?12:0)}" fill="#eeeeee"/>');
      }
      final step=7/math.max(1,(b-a).distance);
      for(var i=0;i*step<=span;i++) {
        final p=Offset.lerp(a,b,(start+i*step)%1)!;
        line(p-const Offset(5,5),p+const Offset(5,5));
        if(methods.contains('ПВК')||methods.contains('МК'))line(p+const Offset(-5,5),p+const Offset(5,-5));
      }
      final mid=Offset.lerp(a,b,(start+span/2)%1)!;
      final at=mid+(alongX?const Offset(-48,-36):const Offset(14,-20));
      line(mid+(alongX?const Offset(0,-7):Offset.zero),at+const Offset(8,13));
      text('${z['designation']} · $methods',at.dx,at.dy,font:11);

    }
  }
  for (final mark in layout.marks.entries) {
    final e = model.entity(mark.key)!;
    final point = e.containsKey('owner_id');
    if (point && layer != 'Все' && layer != e['method']) continue;
    final p = mark.value;
    final ownerRect = layout.parts[e['parent_id']];
    final r = point ? 3.0 : ownerRect == null ? 10.0 : layout.symbolRadius(e, ownerRect);
    if (point) {
      line(p - const Offset(3,3),p + const Offset(3,3));
      line(p + const Offset(-3,3),p + const Offset(3,-3));
    } else if (e['kind'] == 'manway') {
      out.write('<circle cx="${p.dx}" cy="${p.dy}" r="$r"/><circle cx="${p.dx}" cy="${p.dy}" r="${r*.87}"/>');
    } else if (e['kind'] == 'support') {
      out.write('<rect x="${p.dx - 6}" y="${p.dy - 20}" width="12" height="40" fill="black"/>');
    } else if (e['kind'] == 'pad') {
      out.write(
          '<rect x="${p.dx - 9}" y="${p.dy - 6}" width="18" height="12"/>');
    } else {
      out.write(
          '<circle cx="${p.dx}" cy="${p.dy}" r="$r" ${point ? 'fill="black"' : ''}/>');
    }
    if (e['kind'] == 'nozzle') {
      line(p - Offset(r+4,0),p + Offset(r+4,0));
      line(p - Offset(0,r+4),p + Offset(0,r+4));
    }
    if (!point && ownerRect != null) {
      for (final w in model.welds.where((w) => w['kind']=='attachment' && w['geometry']['element_id']==e['id'])) {
        for (final z in model.zones.where((z) => z['weld_id']==w['id'])) {
          if (layer!='Все' && !(z['planned_methods'] as List).contains(layer)) continue;
          for (var i=0;i<72;i++) {
            final angle=i*5.0,cov=z['coverage'];
            if (cov['kind']=='sector' && (angle-cov['start'])%360>(cov['end']-cov['start'])%360) continue;
            final a=angle*math.pi/180;
            line(p+Offset((r+3)*math.sin(a),-(r+3)*math.cos(a)),p+Offset((r+7)*math.sin(a+.03),-(r+7)*math.cos(a+.03)));
          }
          text(z['designation'],p.dx+r+11,p.dy+r+14,font:10);
        }
      }
    }
    if (e['kind'] == 'instrument') {
      line(p - const Offset(8, 0), p + const Offset(8, 0));
      line(p - const Offset(0, 8), p + const Offset(0, 8));
    }
    if (e['kind'] == 'lug') {
      out.write('<rect x="${p.dx - 8}" y="${p.dy}" width="16" height="12"/>');
    }
    if (e['kind'] == 'drain' || e['kind'] == 'vent') {
      final sign = e['kind'] == 'drain' ? 1.0 : -1.0;
      line(p, p + Offset(0, sign * 14));
      line(p + Offset(-4, sign * 9), p + Offset(0, sign * 14));
      line(p + Offset(4, sign * 9), p + Offset(0, sign * 14));
    }
    final override = model.labels[e['id']] as Map? ?? {};
    var label = p +
        Offset((override['dx'] as num? ?? (point ? -3 : -20)).toDouble(),
            (override['dy'] as num? ?? (point ? -16 : -30)).toDouble());
    if (point && !['shell','head','cover'].contains(model.entity(e['owner_id'])?['kind']) && override.isEmpty) {
      label = p + (<int, Offset>{1: const Offset(-12,-5),2: const Offset(5,-5),3: const Offset(-3,-16),4: const Offset(-3,6)}[e['local_number']] ?? const Offset(5,-12));
    }
    if (!point || override.isNotEmpty) line(p, label, extra: 'stroke-width="0.5"');
    text(point ? '${e['body_number'] ?? e['local_number']}' : e['designation'],
        label.dx, label.dy);
  }
  if(detail==null) {
    for(final section in (model.data['sections'] as List? ?? []).where((s)=>s['kind']=='weld_profile')) {
      final x=size.width*(model.data['orientation']=='horizontal'? 0.82:.70),y=90.0;
      final width=size.width*.18,scale=model.data['orientation']=='horizontal'? 0.75:.85,mid=y+60*scale,cx=x+width*.25;
      text('${section['designation']} · твердометрия',x,y-6,font:11);
      out.write('<rect x="$x" y="${mid-22*scale}" width="${width*.5}" height="${44*scale}" fill="#eeeeee"/><rect x="$x" y="${mid-7*scale}" width="${width*.5}" height="${14*scale}" fill="#aaaaaa"/>');
      for(var i=0;i<5;i++) {final yy=mid+[-45,-17,0,17,45][i]*scale;line(Offset(cx-3,yy-3),Offset(cx+3,yy+3));line(Offset(cx-3,yy+3),Offset(cx+3,yy-3));text('${i+1}',cx+5,yy,font:9);text(['Осн. металл','ЗТВ','Шов','ЗТВ','Осн. металл'][i],x+width*.53,yy,font:8);}
      break;
    }
    text('× Точка УЗТ · К кольцевой шов · П продольный шов',20,size.height-85);
    text('/ УЗК · × ПВК/МК · I–III овальность · А–А твердометрия',20,size.height-63);
  }
  text(
      'План контроля. Результаты измерений не назначены. Размеры сверить с источником.',
      20,
      size.height-24,
      font: 14);
  out.write(
      '</g><g font-family="Arial, sans-serif" fill="black">$labels</g></svg>');
  return out.toString();
}
