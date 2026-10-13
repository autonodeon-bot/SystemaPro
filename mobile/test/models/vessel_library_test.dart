import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/models/vessel_geometry.dart';
import 'package:es_td_ngo_mobile/widgets/vessel_drawing.dart';

void main() {
 test('DN threshold, independent cover ownership and retained point IDs',(){
  for(final dn in [100,110,117,149]) {expect(VesselGeometry.recommendedNozzlePoints(dn),2);}
  for(final dn in [150,219]) {expect(VesselGeometry.recommendedNozzlePoints(dn),4);}
  expect(VesselGeometry.recommendedNozzlePoints(null),isNull);
  final g=VesselGeometry.create();final part=g.shells.first;
  final nozzle=g.applyLibrary('nozzle_large_combined',part['id']);
  final ids=g.points.map((p)=>p['id']).toList();
  expect(g.points.first['placement']['u'],.18);
  g.setPointTemplate(nozzle,2);expect(g.points.map((p)=>p['id']).toList(),ids);
  expect(g.points.where((p)=>p['archived']==true).length,2);
  final cover=g.applyLibrary('cover',part['id']);
  expect(g.elements.where((e)=>e['parent_id']==cover).length,2);
  expect(g.points.where((p)=>p['owner_id']==cover).length,6);
  expect(vesselSheetSize(g).height,greaterThan(vesselSheetSize(g).width));
 });
}
