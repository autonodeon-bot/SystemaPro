import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/models/vessel_editor_tools.dart';
import 'package:es_td_ngo_mobile/models/vessel_geometry.dart';

void main() {
  late VesselGeometry g;
  late VesselEntity e;
  setUp(() {
    g = VesselGeometry.create();
    g.shells.first['dimensions'] = {'length_mm': 2000, 'diameter_mm': 1000};
    e = g.addElement(g.shells.first['id'], 'valve');
    e['placement'] = {
      'mode': 'physical',
      'z_local_mm': 600.0,
      'theta_deg': 90.0,
      'reference_weld_id': g.welds.first['id']
    };
  });
  test(
      'nudge, alignment, mirroring and rotation preserve physical mode and identity',
      () {
    final id = e['id'], reference = e['placement']['reference_weld_id'];
    VesselEditorTools.shift(g, id, .1, .1);
    expect(e['placement']['z_local_mm'], closeTo(800, 1e-9));
    expect(e['placement']['theta_deg'], closeTo(126, 1e-9));
    VesselEditorTools.align(g, id);
    expect(e['placement']['z_local_mm'], 1000);
    VesselEditorTools.mirror(g, id, axial: false);
    expect(e['placement']['theta_deg'], 234);
    VesselEditorTools.rotate(g, id, 150);
    expect(e['placement']['theta_deg'], closeTo(24, 1e-8));
    expect(e['placement']['reference_weld_id'], reference);
    expect(e['id'], id);
  });
  test('physical head placement roundtrips modern angular conventions', () {
    final head = g.parts.firstWhere((p) => p['side'] == 'A');
    head['dimensions'] = {'diameter_mm': 1000};
    final elbow = g.addElement(head['id'], 'elbow');
    elbow['placement'] = {
      'mode': 'physical',
      'radius_projection_mm': 200,
      'theta_deg': 90,
      'angle_convention': 'visio-head-2026'
    };
    final p = g.position(elbow);
    final restored = VesselEditorTools.unitPlacement(g, elbow, p.x, p.y);
    expect(restored['theta_deg'], closeTo(90, 1e-9));
    expect(restored['radius_projection_mm'], closeTo(200, 1e-9));
    VesselEditorTools.rotate(g, elbow['id'], 90);
    expect(g.position(elbow).x, closeTo(.7, 1e-9));
  });
  test(
      'duplicate creates new IDs and planned points without results or legacy bindings',
      () {
    g.setPointTemplate(e['id'], 2);
    e['legacy_id'] = 'legacy-1';
    e['result'] = {'thickness': 8.7};
    g.points.first.addAll({'status': 'measured', 'result': 8.7});
    final originalIds = g.points.map((p) => p['id']).toSet();
    final id = VesselEditorTools.duplicate(g, e['id']);
    expect(id, isNot(e['id']));
    expect(g.entity(id)!['result'], isNull);
    expect(g.entity(id)!['legacy_id'], isNull);
    final copies = g.points.where((p) => p['owner_id'] == id);
    expect(copies.length, 2);
    expect(
        copies.every((p) =>
            !originalIds.contains(p['id']) &&
            p['status'] == 'planned' &&
            !p.containsKey('result')),
        isTrue);
    expect(g.points.first['result'], 8.7);
  });
  test('locked objects reject placement and property changes', () {
    e['locked'] = true;
    expect(() => VesselEditorTools.shift(g, e['id'], .1, 0), throwsStateError);
    expect(
        () => VesselEditorTools.pasteProperties(
            g, e['id'], {'nominal_dn_mm': 100}),
        throwsStateError);
    expect(e['placement']['z_local_mm'], 600);
  });
  test('copying properties cannot overwrite identity, placement or results',
      () {
    e.addAll({
      'nominal_dn_mm': 150,
      'purpose': 'Дренаж',
      'results': [8.7]
    });
    final values = VesselEditorTools.copyProperties(e);
    final target = g.addElement(g.shells.first['id'], 'elbow');
    final placement = VesselGeometry.copy(target['placement']);
    VesselEditorTools.pasteProperties(g, target['id'], values);
    expect(target['nominal_dn_mm'], 150);
    expect(target['purpose'], 'Дренаж');
    expect(target['placement'], placement);
    expect(target['id'], isNot(e['id']));
    expect(target['results'], isNull);
  });
  test(
      'archive and restoration retain IDs and do not restore separately archived points',
      () {
    g.setPointTemplate(e['id'], 2);
    g.points.last['archived'] = true;
    final first = g.points.first['id'];
    VesselEditorTools.archive(g, e['id'], true);
    expect(g.points.every((p) => p['archived'] == true), isTrue);
    VesselEditorTools.archive(g, e['id'], false);
    expect(g.points.first['id'], first);
    expect(g.points.first['archived'], false);
    expect(g.points.last['archived'], true);
  });
  test('ruler uses declared dimensions and returns no assumed millimetres', () {
    expect(
        VesselEditorTools.distance(g, g.shells.first, const math.Point(.1, .2),
            const math.Point(.6, .2)),
        closeTo(1000, 1e-9));
    expect(
        VesselEditorTools.distance(g, g.shells.first, const math.Point(.1, .2),
            const math.Point(.1, .7)),
        closeTo(500 * math.pi, 1e-9));
    g.shells.first['dimensions'] = {};
    expect(
        VesselEditorTools.distance(g, g.shells.first, const math.Point(.1, .2),
            const math.Point(.6, .2)),
        isNull);
  });
  test('invalid numeric placement never silently clamps the object to an edge',
      () {
    expect(
        () => VesselEditorTools.shift(g, e['id'], 2, 0), throwsFormatException);
    expect(e['placement']['z_local_mm'], 600);
  });
  test(
      'a longitudinal weld can be rotated while preserving control zone bindings',
      () {
    g.addLongWeld(g.shells.first['id'], 30);
    final w = g.welds.last;
    (g.data['control_zones'] as List).add({
      'id': 'zone-1',
      'weld_id': w['id'],
      'coverage': {'kind': 'whole'}
    });
    VesselEditorTools.rotate(g, w['id'], 90);
    expect(w['geometry']['theta_deg'], 120);
    expect(g.zones.single['weld_id'], w['id']);
  });
}
