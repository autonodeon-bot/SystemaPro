import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/models/vessel_geometry.dart';
import 'package:es_td_ngo_mobile/widgets/vessel_drawing.dart';
import 'package:es_td_ngo_mobile/services/vessel_svg_export.dart';
import 'package:flutter/widgets.dart';
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';

void main() {
  test('fresh and empty-view documents accept generated detail views before reload', () {
    final fresh = VesselGeometry.create();
    final emptyViews = VesselGeometry.copy(fresh.data)..['views'] = [];
    for (final model in [fresh, VesselGeometry.load(emptyViews)]) {
      final views = model.data['views'] as List;
      views.add(<String, dynamic>{'id': 'detail', 'kind': 'part_detail',
        'part_ids': [model.shells.first['id']], 'revision': 1,
        'image_path': '/test/detail.png'});
      expect(VesselGeometry.load(model.data).data['views'].length, 2);
    }
  });
  test('plan rows preserve IDs and never fabricate results', () {
    final w = WeldInspection(weldNumber: 'К2')
      ..schemeZoneId = 'zone'
      ..weldId = 'weld'
      ..controlMethod = 'MPK'
      ..modelRevision = 3;
    expect(w.toJson()['result_status'], 'planned');
    final restored = WeldInspection.fromJson(w.toJson());
    expect(restored.schemeZoneId, 'zone');
    expect(restored.weldId, 'weld');
    restored.pvkDefect = 'Не обнаружены';
    expect(restored.toJson()['result_status'], 'recorded');
    expect(restored.controlMethod, 'MPK');
    expect(restored.uzkDefect, isNull);
    final h = HardnessTest(weldNumber: 'К2')
      ..sectionProfileId = 'profile'
      ..weldId = 'weld';
    expect(h.toJson()['result_status'], 'planned');
    expect(HardnessTest.fromJson(h.toJson()).sectionProfileId, 'profile');
  });
  test(
      'B exterior mirrors projection, cut does not rotate heads, labels do not move points',
      () {
    final g = VesselGeometry.create();
    final b = g.parts.firstWhere((p) => p['side'] == 'B');
    b['dimensions'] = {'diameter_mm': 2000};
    final e = g.addElement(b['id'], 'nozzle');
    e['placement'] = {
      'mode': 'physical',
      'radius_projection_mm': 500,
      'theta_deg': 90
    };
    final normal =
        VesselDrawingLayout(g, const Size(1190, 842), detail: b['id']);
    final mirrored = VesselDrawingLayout(g, const Size(1190, 842),
        detail: b['id'], exteriorB: true);
    expect(normal.marks[e['id']]!.dx,
        greaterThan(normal.parts[b['id']]!.center.dx));
    expect(mirrored.marks[e['id']]!.dx,
        lessThan(mirrored.parts[b['id']]!.center.dx));
    final before = VesselGeometry.copy(e['placement']);
    g.labels[e['id']] = {'dx': 70, 'dy': 30};
    (g.data['views'] as List).first['cut_angle_deg'] = 90;
    expect(e['placement'], before);
    expect(g.position(e).x, .75);
    final svg = exportVesselSvg(g, detail: b['id']);
    expect(svg, contains('<svg'));
    expect(svg, contains('рев. 0'));
    Directory('../artifacts/vessel-constructor-v2').createSync(recursive: true);
    File('../artifacts/vessel-constructor-v2/detail.svg')
        .writeAsStringSync(svg);
  });
  test('archive and restore template uses the same IDs', () {
    final g = VesselGeometry.create();
    final owner = g.shells.first['id'];
    g.setPointTemplate(owner, 12);
    final ids = g.points.map((p) => p['id']).toList();
    g.setPointTemplate(owner, 4);
    g.setPointTemplate(owner, 12);
    expect(g.points.length, 12);
    expect(g.points.map((p) => p['id']).toList(), ids);
    expect(g.points.any((p) => p['archived'] == true), false);
  });
  test('shared weld with coverage prevents destructive topology change', () {
    final g = VesselGeometry.create();
    (g.data['control_zones'] as List)
        .add({'id': VesselGeometry.id(), 'weld_id': g.welds.last['id']});
    expect(() => g.addShell(), throwsStateError);
    expect(g.shells.length, 1);
  });
  test('invalid physical geometry is not applied', () {
    final g = VesselGeometry.create();
    final e = g.addElement(g.shells.first['id'], 'nozzle');
    e['placement'] = {'mode': 'physical', 'z_local_mm': 350, 'theta_deg': 90};
    expect(g.validateForSave, throwsStateError);
    g.shells.first['dimensions'] = {'length_mm': 1000};
    expect(g.validateForSave, returnsNormally);
    g.shells.first['dimensions'] = {'length_mm': 200};
    expect(g.validateForSave, throwsStateError);
  });
  test('six unequal shells, seven unique shared rings and 72 body points', () {
    final g = VesselGeometry.create(orientation: 'horizontal');
    for (var i = 1; i < 6; i++) {
      g.addShell();
    }
    for (var i = 0; i < 6; i++) {
      g.shells[i]['dimensions'] = {
        'length_mm': i == 5 ? 1000 : 2000,
        'diameter_mm': 2000
      };
      g.setPointTemplate(g.shells[i]['id'], 12);
    }
    expect(g.welds.length, 7);
    expect(g.welds.map((w) => w['id']).toSet().length, 7);
    expect(g.points.length, 72);
    expect(
        g.points.map((p) => p['body_number']), List.generate(72, (i) => i + 1));
    final e = g.addElement(g.shells[1]['id'], 'nozzle');
    e['placement'] = {
      'mode': 'physical',
      'z_local_mm': 350.0,
      'theta_deg': 90.0
    };
    expect(g.position(e).x, .175);
    expect(g.position(e).y, .25);
    (g.data['views'] as List).first['cut_angle_deg'] = 90;
    expect(g.position(e).y, 0);
    expect(e['placement']['theta_deg'], 90);
    final manway = g.addElement(g.shells.first['id'], 'manway');
    final cover = g.addCover(manway['id']);
    g.setPointTemplate(cover['id'], 6);
    g.addElement(cover['id'], 'nozzle');
    g.addElement(cover['id'], 'nozzle');
    expect(g.points.where((p) => p['body_number'] != null).length, 72);
    expect(g.addCover(manway['id'])['id'], cover['id']);
    (g.data['control_zones'] as List).add({
      'id': VesselGeometry.id(),
      'weld_id': g.welds[1]['id'],
      'designation': 'К2 МК',
      'planned_methods': ['МК'],
      'coverage': {'kind': 'sector', 'unit': 'deg', 'start': 350, 'end': 10}
    });
    expect(VesselGeometry.coverageDegrees(350, 10), 20);
    final dir = Directory('../artifacts/vessel-constructor-v2')
      ..createSync(recursive: true);
    File('${dir.path}/fixture.json').writeAsStringSync(jsonEncode(g.data));
  });
  test(
      'legacy data preserved without inventing dimensions or deduplicating names',
      () {
    final raw = {
      'shell_count': 2,
      'shell': {'length': 1.0, 'diameter': .5},
      'elements': [
        {
          'id': 'old',
          'part_id': 'shell_1',
          'kind': 'nozzle',
          'label': 'A',
          'x': .2,
          'y': .3
        }
      ],
      'nozzles': [
        {'label': 'A', 'position': .5}
      ],
      'private_extension': {'result': 11.8}
    };
    final g = VesselGeometry.load(raw);
    expect(g.elements.length, 2);
    expect(g.shells.first['dimensions'], isEmpty);
    expect(g.data['raw_v1'], raw);
    expect(raw.containsKey('schema_version'), false);
    final restored = VesselGeometry.load(g.data);
    expect(restored.data, g.data);
  });
  test('shrinking template archives points and retains IDs', () {
    final g = VesselGeometry.create();
    final id = g.shells.first['id'];
    g.setPointTemplate(id, 12);
    final ids = g.points.map((p) => p['id']).toList();
    g.setPointTemplate(id, 4);
    expect(g.points.length, 12);
    expect(g.points.where((p) => p['archived'] == true).length, 8);
    expect(g.points.map((p) => p['id']).toList(), ids);
  });
  for (final count in [8, 9]) {
    test('$count shells body numbering', () {
      final g = VesselGeometry.create();
      while (g.shells.length < count) {
        g.addShell();
      }
      for (final s in g.shells) {
        g.setPointTemplate(s['id'], 12);
      }
      expect(g.points.last['body_number'], count * 12);
    });
  }
}
