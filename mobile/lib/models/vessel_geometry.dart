import 'dart:convert';
import 'dart:math' as math;
import 'package:uuid/uuid.dart';

typedef VesselEntity = Map<String, dynamic>;

/// Lossless document: unknown fields survive edits and legacy input is retained.
class VesselGeometry {
  final VesselEntity data;
  Map<String, VesselEntity>? _index;
  int _indexedCount = -1;
  VesselGeometry(this.data) { orientHeadNames(); }
  void orientHeadNames() {
    const defaults={'левое днище','правое днище','верхнее днище','нижнее днище','днище a','днище b','днище а','днище в'};
    for (final p in (data['parts'] as List? ?? [])) {
      if(p['kind']=='head' && defaults.contains('${p['designation']}'.trim().toLowerCase())) {
        p['designation']=data['orientation']=='vertical' ? (p['side']=='A'?'Верхнее днище':'Нижнее днище') : (p['side']=='A'?'Левое днище':'Правое днище');
      }
    }
  }
  static String id() => const Uuid().v4();
  static VesselEntity copy(Map value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  /// A reusable example is a new document, never a shared inspection identity.
  factory VesselGeometry.fromExample(Map<String, dynamic> raw) {
    final ids = <String, String>{};
    void collect(dynamic v) {
      if (v is Map) {
        if (v['id'] is String) ids[v['id']] = id();
        v.values.forEach(collect);
      } else if (v is List) { v.forEach(collect); }
    }
    collect(raw);
    dynamic remap(dynamic v) {
      if (v is Map) return <String, dynamic>{for (final e in v.entries) ids[e.key] ?? e.key: remap(e.value)};
      if (v is List) return v.map(remap).toList();
      return v is String ? ids[v] ?? v : v;
    }
    final next = remap(raw) as Map<String, dynamic>;
    next['model_id'] = id(); next['revision'] = 0;
    return VesselGeometry.load(next);
  }
  List<VesselEntity> list(String key) =>
      (data[key] as List).map((e) => e as VesselEntity).toList();
  List<VesselEntity> get parts => list('parts');
  List<VesselEntity> get shells =>
      parts.where((p) => p['kind'] == 'shell').toList();
  List<VesselEntity> get elements => list('elements');
  List<VesselEntity> get welds => list('welds');
  List<VesselEntity> get points => list('control_points');
  List<VesselEntity> get zones => list('control_zones');
  VesselEntity? entity(String? id) {
    final count = (data['parts'] as List).length +
        (data['elements'] as List).length +
        (data['welds'] as List).length +
        (data['control_points'] as List).length +
        (data['control_zones'] as List).length;
    if (_index == null || _indexedCount != count) {
      _index = {
        for (final e in [...parts, ...elements, ...welds, ...points, ...zones])
          e['id'] as String: e
      };
      _indexedCount = count;
    }
    return _index![id];
  }

  static VesselGeometry create({String orientation = 'vertical'}) {
    final g = VesselGeometry({
      'schema_version': 2,
      'model_id': id(),
      'revision': 0,
      'units': 'mm',
      'equipment_kind': 'vessel',
      'orientation': orientation,
      'print_settings': {'paper':'auto'},
      'coordinate_frame': {
        'axis': 'A_to_B',
        'view_from': 'A',
        'clockwise': true,
        'zero_description': '',
        'confirmed': false
      },
      'parts': <VesselEntity>[],
      'elements': <VesselEntity>[],
      'welds': <VesselEntity>[],
      'control_points': <VesselEntity>[],
      'control_zones': <VesselEntity>[],
      'control_templates': <VesselEntity>[],
      'views': <VesselEntity>[
        {
          'id': id(),
          'kind': 'development',
          'cut_angle_deg': 0,
          'label_overrides': <String, dynamic>{}
        }
      ],
      'source_documents': <VesselEntity>[],
    });
    for (final side in ['A', 'B']) {
      (g.data['parts'] as List).add({
        'id': id(),
        'kind': 'head',
        'designation': 'Днище $side',
        'side': side,
        'head_type': 'elliptical',
        'dimensions': <String, dynamic>{},
        'confidence': 'unknown'
      });
    }
    g.addShell();
    g.orientHeadNames();
    return g;
  }

  factory VesselGeometry.load(Map<String, dynamic>? raw,
      {String orientation = 'vertical'}) {
    if (raw == null) return create(orientation: orientation);
    if (raw['schema_version'] == 2) {
      final d = copy(raw);
      for (final key in [
        'parts',
        'elements',
        'welds',
        'control_points',
        'control_zones',
        'control_templates',
        'views',
        'source_documents'
      ]) {
        d.putIfAbsent(key, () => <VesselEntity>[]);
      }
      if ((d['views'] as List).isEmpty) {
        d['views'] = <VesselEntity>[
          {
            'id': id(),
            'kind': 'development',
            'cut_angle_deg': 0,
            'label_overrides': <String, dynamic>{}
          }
        ];
      }
      return VesselGeometry(d);
    }
    final g =
        create(orientation: raw['orientation']?.toString() ?? orientation);
    g.data['raw_v1'] = copy(raw);
    g.data['migration_notes'] = [
      'Размеры v1 не считаются подтверждёнными. Координаты условные.',
      'Старые швы и результаты сохранены в raw_v1; требуется сверка привязок.'
    ];
    final count =
        ((raw['shell_count'] ?? (raw['shell'] as Map?)?['count'] ?? 1) as num)
            .toInt()
            .clamp(1, 20);
    while (g.shells.length < count) {
      g.addShell();
    }
    final mapping = <String, String>{
      'head_top': g.parts.firstWhere((p) => p['side'] == 'A')['id'],
      'head_bottom': g.parts.firstWhere((p) => p['side'] == 'B')['id'],
    };
    for (var i = 0; i < g.shells.length; i++) {
      mapping['shell_${i + 1}'] = g.shells[i]['id'];
    }
    g.data['legacy_id_map'] = mapping;
    for (final old in (raw['elements'] as List? ?? [])) {
      final p = mapping[old['part_id']];
      if (p == null) continue;
      final e = g.addElement(p, old['kind'] ?? 'nozzle');
      e['legacy_id'] = old['id'];
      e['designation'] = old['label'] ?? e['designation'];
      e['nominal_dn_mm'] = old['dn'];
      final head = g.entity(p)?['kind'] != 'shell';
      final x = (old['x'] as num? ?? .5).toDouble();
      final y = (old['y'] as num? ?? .5).toDouble();
      e['placement'] = {
        'mode': 'schematic',
        'u': head || g.data['orientation'] == 'horizontal' ? x : y,
        'v': head || g.data['orientation'] == 'horizontal' ? y : x
      };
      if ((old['control_points'] as num? ?? 0) > 0) {
        g.setPointTemplate(e['id'], (old['control_points'] as num).toInt());
      }
    }
    // Do not deduplicate by labels: equal labels can refer to distinct fittings.
    for (final n in (raw['nozzles'] as List? ?? [])) {
      final place = n['place']?.toString() ?? 'shell';
      final axial = (n['axial'] as num? ?? n['position'] as num? ?? .5)
          .toDouble()
          .clamp(0.0, 1.0);
      final si = (axial * count).floor().clamp(0, count - 1);
      final owner = place.contains('top') || place.contains('left')
          ? mapping['head_top']!
          : place.contains('bottom') || place.contains('right')
              ? mapping['head_bottom']!
              : g.shells[si]['id'] as String;
      final e = g.addElement(owner, 'nozzle');
      e['designation'] = n['label'] ?? n['id'] ?? e['designation'];
      e['legacy_nozzle'] = copy(n as Map);
      e['nominal_dn_mm'] = n['dn'];
      e['placement'] = {
        'mode': 'schematic',
        'u': (axial * count - si).clamp(0.0, 1.0),
        'v': (n['circ'] as num? ?? .5).toDouble().clamp(0.0, 1.0)
      };
    }
    return g;
  }
  VesselEntity addShell() {
    if (shells.length >= 20) throw StateError('Не более 20 обечаек');
    final endRings = welds
        .where((w) =>
            w['kind'] == 'circumferential' &&
            (w['connected_part_ids'] as List)
                .contains(parts.firstWhere((p) => p['side'] == 'B')['id']))
        .toList();
    if (endRings.any((w) => zones.any((z) => z['weld_id'] == w['id']))) {
      throw StateError(
          'У последнего шва есть зоны контроля. Уточните состав до назначения контроля или отмените его назначение.');
    }
    final p = <String, dynamic>{
      'id': id(),
      'kind': 'shell',
      'order': shells.length,
      'designation': 'Обечайка ${shells.length + 1}',
      'dimensions': <String, dynamic>{},
      'confidence': 'unknown'
    };
    (data['parts'] as List).add(p);
    rebuildRings();
    return p;
  }

  void removeEmptyShell(String partId) {
    if (shells.length <= 1) throw StateError('Нужна хотя бы одна обечайка');
    if (elements.any((e) => e['parent_id'] == partId) ||
        points.any((p) => p['owner_id'] == partId)) {
      throw StateError(
          'В части есть элементы или точки. Удаление заблокировано для сохранности данных.');
    }
    final attached = welds
        .where((w) => (w['connected_part_ids'] as List).contains(partId))
        .toList();
    if (attached.any((w) => zones.any((z) => z['weld_id'] == w['id']))) {
      throw StateError('У шва есть зоны контроля');
    }
    (data['parts'] as List).removeWhere((p) => p['id'] == partId);
    (data['welds'] as List)
        .removeWhere((w) => (w['connected_part_ids'] as List).contains(partId));
    rebuildRings();
    renumber();
  }

  void moveShell(String partId, int delta) {
    if (zones.isNotEmpty) {
      throw StateError(
          'Сначала согласуйте изменение состава: уже заданы зоны контроля швов.');
    }
    final ordered = shells;
    final index = ordered.indexWhere((s) => s['id'] == partId);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= ordered.length) return;
    final p = ordered.removeAt(index);
    ordered.insert(target, p);
    for (var i = 0; i < ordered.length; i++) {
      ordered[i]['order'] = i;
    }
    data['parts'] = [...parts.where((p) => p['kind'] != 'shell'), ...ordered];
    rebuildRings();
    renumber();
  }

  void rebuildRings() {
    _index = null;
    final chain = [
      parts.firstWhere((p) => p['side'] == 'A'),
      ...shells,
      parts.firstWhere((p) => p['side'] == 'B')
    ];
    final old = welds.where((w) => w['kind'] == 'circumferential').toList();
    final rings = <VesselEntity>[];
    for (var i = 0; i < chain.length - 1; i++) {
      final ids = [chain[i]['id'], chain[i + 1]['id']];
      final existing = old
          .where((w) => jsonEncode(w['connected_part_ids']) == jsonEncode(ids));
      rings.add(existing.isNotEmpty
          ? existing.first
          : {
              'id': id(),
              'kind': 'circumferential',
              'designation': 'К${i + 1}',
              'connected_part_ids': ids,
              'geometry': {'boundary_index': i}
            });
      rings.last['geometry'] = {'boundary_index': i};
      rings.last['designation'] = 'К${i + 1}';
    }
    data['welds'] = [
      ...rings,
      ...welds.where((w) => w['kind'] != 'circumferential')
    ];
  }

  VesselEntity addElement(String parentId, String kind) {
    if (elements.length >= 250) throw StateError('Не более 250 элементов');
    final e = <String, dynamic>{
      'id': id(),
      'parent_id': parentId,
      'kind': kind,
      'designation': '${kind == 'manway' ? 'Л' : 'Э'}${elements.length + 1}',
      'placement': {'mode': 'schematic', 'u': .5, 'v': .5},
      'attachment_to_vessel': 'unknown',
      'end_connection': 'unknown'
    };
    (data['elements'] as List).add(e);
    return e;
  }

  static int? recommendedNozzlePoints(num? dn) => dn == null || dn <= 0 ? null : dn < 150 ? 2 : 4;

  String applyLibrary(String preset, String ownerId) {
    final owner=entity(ownerId)!;
    if (preset.startsWith('nozzle_') || preset=='support') {
      final e=addElement(ownerId,preset=='support'?'support':'nozzle');
      e['library_preset']=preset;
      if (preset!='support' && preset!='nozzle_none') {
        final small=preset.contains('small');e['nominal_dn_mm']=small?100:150;
        setPointTemplate(e['id'],small?2:4);
        final w={'id':id(),'kind':'attachment','designation':'Шов ${e['designation']}','connected_part_ids':[ownerId],'geometry':{'element_id':e['id']}};
        (data['welds'] as List).add(w);
        (data['control_zones'] as List).add({'id':id(),'kind':'weld_zone','designation':'${zones.length+1} уч.','weld_id':w['id'],'planned_methods':[if(preset.endsWith('combined')) 'УЗК','ПВК'],'coverage':{'kind':'whole'}});
      }
      return e['id'];
    }
    if (preset=='cover') {
      final man=owner['kind']=='manway'?owner:addElement(ownerId,'manway');
      final cover=addCover(man['id']);setPointTemplate(cover['id'],6);
      if(!elements.any((e)=>e['parent_id']==cover['id'])) {for(var i=0;i<2;i++){final n=applyLibrary(i==0?'nozzle_large':'nozzle_large_combined',cover['id']);entity(n)!['placement']={'mode':'schematic','u':.5,'v':i==0 ? .3 : .7};}}
      return cover['id'];
    }
    if(preset=='point') {
      final n=points.where((p)=>p['owner_id']==ownerId).length+1;
      final point={'id':id(),'owner_id':ownerId,'local_number':n,'method':'УЗТ','status':'planned','placement':{'mode':'schematic','u':.5,'v':.5}};
      (data['control_points'] as List).add(point);renumber();return point['id'] as String;
    }
    if(preset=='longitudinal') {
      if(owner['kind']=='shell'){addLongWeld(ownerId,0);return welds.last['id'];}
      final w={'id':id(),'kind':'head_joint','designation':'П${welds.where((w)=>w['kind']!='circumferential').length+1}','connected_part_ids':[ownerId],'geometry':{'offset_mm':0}};
      (data['welds'] as List).add(w);return w['id'] as String;
    }
    final candidates=welds.where((w)=>(w['connected_part_ids'] as List).contains(ownerId));
    final w=welds.contains(owner)?owner:candidates.where((w)=>preset.contains('ring')?w['kind']=='circumferential':w['kind']!='circumferential').firstOrNull;
    if(w==null) throw StateError('Сначала выберите соответствующий шов');
    if(preset=='ring') return w['id'];
    if(preset=='profile') {
      final section={'id':id(),'kind':'weld_profile','owner_id':w['id'],'designation':'А–А','method':'ТВ','positions':['Основной металл','ЗТВ','Шов','ЗТВ','Основной металл']};
      (data.putIfAbsent('sections',()=>[]) as List).add(section);return w['id'];
    }
    final z={'id':id(),'kind':'weld_zone','designation':'${zones.length+1} уч.','weld_id':w['id'],'planned_methods':['УЗК','ПВК'],'coverage':w['kind']=='circumferential'?{'kind':'sector','start':270,'end':300}:{'kind':'interval','start':.2,'end':.4}};
    (data['control_zones'] as List).add(z);return z['id'] as String;
  }

  VesselEntity addCover(String manwayId) {
    final existing = parts.where((p) => p['parent_id'] == manwayId);
    if (existing.isNotEmpty) return existing.first;
    final p = <String, dynamic>{
      'id': id(),
      'kind': 'cover',
      'parent_id': manwayId,
      'designation': 'Крышка ${entity(manwayId)?['designation']}',
      'dimensions': <String, dynamic>{}
    };
    (data['parts'] as List).add(p);
    return p;
  }

  void addLongWeld(String partId, double angle) {
    (data['welds'] as List).add({
      'id': id(),
      'kind': 'longitudinal',
      'designation':
          'П${welds.where((w) => w['kind'] == 'longitudinal').length + 1}',
      'connected_part_ids': [partId],
      'geometry': {'theta_deg': angle % 360}
    });
  }

  void setPointTemplate(String ownerId, int count) {
    final existing = points.where((p) => p['owner_id'] == ownerId).toList();
    if (points.length + math.max(0, count - existing.length) > 500) {
      throw StateError('Не более 500 точек');
    }
    for (var i = 0; i < existing.length; i++) {
      existing[i]['archived'] = i >= count;
    }
    final shell = entity(ownerId)?['kind'] == 'shell';
    final nozzle = ['nozzle','manway'].contains(entity(ownerId)?['kind']);
    const cardinal = [[.18,.5],[.82,.5],[.5,.18],[.5,.82]];
    for (var i = existing.length; i < count; i++) {
      (data['control_points'] as List).add({
        'id': id(),
        'owner_id': ownerId,
        'local_number': i + 1,
        'method': 'УЗТ',
        'status': 'planned',
        'template_id': shell ? 'shell_manual_12' : 'manual',
        'placement': {
          'mode': 'schematic',
          'u': shell
              ? (i ~/ 4 + 1) / ((count / 4).ceil() + 1)
              : nozzle && count <= 4 ? cardinal[i][0] : .5 + .3 * math.sin(i * 2 * math.pi / count),
          'v': shell
              ? (i % 4 + .5) / 4
              : nozzle && count <= 4 ? cardinal[i][1] : .5 - .3 * math.cos(i * 2 * math.pi / count)
        }
      });
    }
    renumber();
  }

  void renumber() {
    var n = 1;
    for (final s in shells) {
      for (final p in points
          .where((p) => p['owner_id'] == s['id'] && p['archived'] != true)) {
        p['body_number'] = n++;
      }
    }
  }

  static double coverageDegrees(double start, double end) =>
      (end - start) % 360;
  double get cut =>
      ((data['views'] as List).first['cut_angle_deg'] as num? ?? 0).toDouble();
  VesselEntity get labels => (data['views'] as List).first.putIfAbsent(
      'label_overrides', () => <String, dynamic>{}) as VesselEntity;

  /// Canonical shell u is axial, v is circumference; disk u/v is viewed from A.
  math.Point<double> position(VesselEntity e) {
    final p = e['placement'] as Map? ?? {};
    final owner = entity(e['parent_id'] ?? e['owner_id']);
    final a = ((p['theta_deg'] as num? ?? 0).toDouble() -
            (owner?['kind'] == 'shell' ? cut : 0)) %
        360;
    if (p['mode'] != 'physical') {
      return math.Point(
          (p['u'] as num? ?? .5).toDouble(), (p['v'] as num? ?? .5).toDouble());
    }
    if (owner?['kind'] == 'shell') {
      final length = (owner?['dimensions']?['length_mm'] as num?)?.toDouble();
      return math.Point(
          length == null ? .5 : (p['z_local_mm'] as num).toDouble() / length,
          a / 360);
    }
    final diameter = (owner?['dimensions']?['diameter_mm'] as num?)?.toDouble();
    final r = diameter == null
        ? 0
        : (p['radius_projection_mm'] as num).toDouble() / diameter;
    if (p['angle_convention']=='visio-head-2026') {
      final sign=owner?['side']=='A' ? -1 : 1;
      return math.Point(.5+sign*r*math.cos(a*math.pi/180),.5-r*math.sin(a*math.pi/180));
    }
    return math.Point(.5 + r * math.sin(a * math.pi / 180),
        .5 - r * math.cos(a * math.pi / 180));
  }

  List<String> diagnostics() {
    final out = <String>[];
    if (data['coordinate_frame']?['confirmed'] != true) {
      out.add('Уточните ноль и подтвердите направление отсчёта A → B.');
    }
    for (final s in shells) {
      if (s['dimensions']?['length_mm'] == null) {
        out.add('${s['designation']}: длина неизвестна; схема условная.');
      }
      if (!welds.any((w) =>
          w['kind'] == 'longitudinal' &&
          (w['connected_part_ids'] as List).contains(s['id']))) {
        out.add('${s['designation']}: продольные швы не заданы.');
      }
    }
    for (final e in elements) {
      final p = position(e);
      if (p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1) {
        out.add('${e['designation']}: координаты вне части.');
      }
      if ((elements.where((other) =>
          other['id'] != e['id'] &&
          other['parent_id'] == e['parent_id'] &&
          position(other).distanceTo(p) < .05)).isNotEmpty) {
        out.add(
            '${e['designation']}: близко к другому элементу — проверьте размещение.');
      }
      if (p.x < .025 ||
          p.x > .975 ||
          welds.any((w) =>
              w['kind'] == 'longitudinal' &&
              (w['connected_part_ids'] as List).contains(e['parent_id']) &&
              ((((w['geometry']['theta_deg'] as num) - cut) % 360 / 360) - p.y)
                      .abs() <
                  .02)) {
        out.add(
            '${e['designation']}: рядом со швом; размещение разрешено, нужна проверка.');
      }
    }
    if (data['raw_v1'] != null) {
      out.add(
          'Импорт v1: исходник сохранён. Сверьте старые швы и привязки результатов.');
    }
    return out;
  }

  void validateForSave() {
    for (final e in [...elements, ...points]) {
      final p = e['placement'] as Map;
      if (p['mode'] != 'physical') continue;
      final owner = entity(e['parent_id'] ?? e['owner_id']);
      final shell = owner?['kind'] == 'shell';
      final length =
          (owner?['dimensions']?[shell ? 'length_mm' : 'diameter_mm'] as num?)
              ?.toDouble();
      final distance =
          (p[shell ? 'z_local_mm' : 'radius_projection_mm'] as num?)
              ?.toDouble();
      if (length == null ||
          distance == null ||
          !distance.isFinite ||
          distance < 0 ||
          distance > length / (shell ? 1 : 2)) {
        throw StateError(
            '${e['designation'] ?? 'Точка ${e['local_number']}'}: проверьте размер части и координату.');
      }
    }
  }
}
