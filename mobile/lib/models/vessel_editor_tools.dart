import 'dart:math' as math;
import 'vessel_geometry.dart';

/// Editing commands keep identities, results and unknown document fields intact.
class VesselEditorTools {
  static bool movable(VesselGeometry g, VesselEntity e) =>
      e['archived'] != true &&
      e['locked'] != true &&
      (e['placement'] is Map || e['kind'] == 'longitudinal');

  static Map<String, dynamic> unitPlacement(
      VesselGeometry g, VesselEntity e, double u, double v) {
    final owner = g.entity(e['parent_id'] ?? e['owner_id']);
    if (owner == null)
      throw StateError('Не найдена часть, которой принадлежит объект');
    if (u < 0 || u > 1 || v < 0 || v > 1) {
      throw const FormatException('Координаты должны оставаться внутри детали');
    }
    final shell = owner['kind'] == 'shell';
    final x = u - .5, y = .5 - v;
    final radius = math.sqrt(x * x + y * y);
    if (!shell && radius > .5 + 1e-9) {
      throw const FormatException(
          'Место должно находиться внутри контура детали');
    }
    final p = Map<String, dynamic>.from(e['placement'] as Map? ?? {});
    if (p['mode'] != 'physical')
      return {...p, 'mode': 'schematic', 'u': u, 'v': v};
    final dimension = owner['dimensions']?[shell ? 'length_mm' : 'diameter_mm'];
    if (dimension is! num || dimension <= 0) {
      throw const FormatException(
          'Сначала задайте размеры части для точного размещения');
    }
    final angle = shell
        ? v * 360 + g.cut
        : radius < 1e-9
            ? (p['theta_deg'] as num? ?? 0).toDouble()
            : (p['angle_convention'] == 'visio-head-2026'
                    ? math.atan2(y, owner['side'] == 'A' ? -x : x)
                    : math.atan2(x, y)) *
                180 /
                math.pi;
    return {
      ...p,
      if (shell)
        'z_local_mm': u * dimension
      else
        'radius_projection_mm': radius * dimension,
      'theta_deg': angle % 360
    };
  }

  static void move(
      VesselGeometry g, String id, Map<String, dynamic> placement) {
    final e = g.entity(id);
    if (e == null || !movable(g, e))
      throw StateError('Объект заблокирован или недоступен');
    if (e['kind'] == 'longitudinal') {
      e['geometry'] = {
        ...Map<String, dynamic>.from(e['geometry'] as Map),
        'theta_deg': (placement['theta_deg'] as num) % 360
      };
    } else {
      e['placement'] = Map<String, dynamic>.from(placement);
    }
  }

  static void shift(VesselGeometry g, String id, double du, double dv) {
    final e = g.entity(id)!;
    if (e['kind'] == 'longitudinal') {
      move(
          g, id, {'theta_deg': (e['geometry']['theta_deg'] as num) + dv * 360});
      return;
    }
    final p = g.position(e);
    move(g, id, unitPlacement(g, e, p.x + du, p.y + dv));
  }

  static void align(VesselGeometry g, String id, {bool axial = true}) {
    final e = g.entity(id)!;
    final p = g.position(e);
    move(g, id, unitPlacement(g, e, axial ? .5 : p.x, axial ? p.y : .5));
  }

  static void mirror(VesselGeometry g, String id, {bool axial = true}) {
    final e = g.entity(id)!;
    final p = g.position(e);
    move(g, id,
        unitPlacement(g, e, axial ? 1 - p.x : p.x, axial ? p.y : 1 - p.y));
  }

  static void rotate(VesselGeometry g, String id, double degrees) {
    final e = g.entity(id)!;
    if (e['kind'] == 'longitudinal') {
      shift(g, id, 0, degrees / 360);
      return;
    }
    final owner = g.entity(e['parent_id'] ?? e['owner_id']);
    final p = g.position(e);
    if (owner?['kind'] == 'shell') {
      move(g, id, unitPlacement(g, e, p.x, (p.y + degrees / 360) % 1));
    } else {
      final a = degrees * math.pi / 180, x = p.x - .5, y = p.y - .5;
      move(
          g,
          id,
          unitPlacement(g, e, .5 + x * math.cos(a) - y * math.sin(a),
              .5 + x * math.sin(a) + y * math.cos(a)));
    }
  }

  static const propertyKeys = [
    'nominal_dn_mm',
    'opening_diameter_mm',
    'attachment_to_vessel',
    'end_connection',
    'purpose',
    'source_ref',
    'dimensions',
    'symbol_rotation_deg'
  ];
  static Map<String, dynamic> copyProperties(VesselEntity e) =>
      VesselGeometry.copy({
        for (final k in propertyKeys)
          if (e.containsKey(k)) k: e[k]
      });
  static void pasteProperties(
      VesselGeometry g, String id, Map<String, dynamic> values) {
    final e = g.entity(id)!;
    if (e['locked'] == true)
      throw StateError('Сначала снимите блокировку объекта');
    e.addAll(VesselGeometry.copy({
      for (final k in propertyKeys)
        if (values.containsKey(k)) k: values[k]
    }));
  }

  static String duplicate(VesselGeometry g, String id) {
    final original = g.entity(id)!;
    if (!g.elements.contains(original))
      throw StateError('Дублировать можно навесной элемент');
    if (g.elements.length >= 250) throw StateError('Не более 250 элементов');
    final points = g.points
        .where((p) => p['owner_id'] == id && p['archived'] != true)
        .toList();
    if (g.points.length + points.length > 500)
      throw StateError('Не более 500 точек');
    final copy = VesselGeometry.copy(original);
    for (final key in [
      'legacy_id',
      'legacy_nozzle',
      'measurements',
      'results',
      'result',
      'revision_history'
    ]) {
      copy.remove(key);
    }
    copy['id'] = VesselGeometry.id();
    copy['locked'] = false;
    copy['archived'] = false;
    var name = '${original['designation']} копия', n = 2;
    while (g.elements.any((e) => e['designation'] == name)) {
      name = '${original['designation']} копия ${n++}';
    }
    copy['designation'] = name;
    (g.data['elements'] as List).add(copy);
    try {
      shift(g, copy['id'], .04, 0);
    } catch (_) {/* Keep valid original coordinates. */}
    for (final point in points) {
      (g.data['control_points'] as List).add(<String, dynamic>{
        'id': VesselGeometry.id(),
        'owner_id': copy['id'],
        'local_number': point['local_number'],
        'method': point['method'] ?? 'УЗТ',
        'status': 'planned',
        'placement': VesselGeometry.copy(point['placement'] as Map),
      });
    }
    g.renumber();
    return copy['id'];
  }

  static void archive(VesselGeometry g, String id, bool archived) {
    final e = g.entity(id)!;
    if (e['locked'] == true)
      throw StateError('Сначала снимите блокировку объекта');
    e['archived'] = archived;
    for (final p in g.points.where((p) => p['owner_id'] == id)) {
      if (archived && p['archived'] != true) {
        p['archived'] = true;
        p['archive_owner_id'] = id;
      } else if (!archived && p['archive_owner_id'] == id) {
        p['archived'] = false;
        p.remove('archive_owner_id');
      }
    }
  }

  /// Distance on a developed shell or head projection, never an assumed scale.
  static double? distance(VesselGeometry g, VesselEntity owner,
      math.Point<double> a, math.Point<double> b) {
    final d = owner['dimensions']?['diameter_mm'];
    if (d is! num || d <= 0) return null;
    final shell = owner['kind'] == 'shell';
    final l = owner['dimensions']?['length_mm'];
    if (shell && (l is! num || l <= 0)) return null;
    final dx = (a.x - b.x) * (shell ? l as num : d);
    final dy = (a.y - b.y) * d * (shell ? math.pi : 1);
    return math.sqrt(dx * dx + dy * dy);
  }
}
