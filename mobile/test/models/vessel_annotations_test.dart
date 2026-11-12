import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/models/vessel_geometry.dart';
import 'package:es_td_ngo_mobile/models/vessel_annotations.dart';
import 'package:es_td_ngo_mobile/services/vessel_svg_export.dart';

void main() {
  VesselGeometry fixture()=>VesselGeometry.load(jsonDecode(File('../public/examples/visio-vessel.json').readAsStringSync()));
  test('physical reference, angle and immutability',(){
    final g=fixture(),e=fixture().elements.first;
    final owner=g.entity(e['parent_id'])!;
    e['placement']={'mode':'physical','z_local_mm':350.5,'theta_deg':450};
    expect(coordinateCallout(g,e,owner,detail:owner['id']),['350,5 мм от начала детали','θ=90°']);
    final w=g.welds.firstWhere((w)=>w['kind']=='circumferential'&&w['connected_part_ids'][0]==owner['id']);
    e['placement']['reference_weld_id']=w['id'];
    final before=jsonEncode(g.data);
    expect(coordinateCallout(g,e,owner,detail:owner['id']).first,contains('от ${w['designation']}'));
    expect(jsonEncode(g.data),before);
  });
  test('schematic positions and detail point scope',(){
    final g=fixture();final owner=g.parts.first;
    expect(coordinateCallout(g,{'placement':{'mode':'schematic'}},owner,detail:owner['id']),['Положение условное']);
    final e={'owner_id':owner['id'],'placement':{'mode':'physical','radius_projection_mm':120.25,'theta_deg':90,'angle_convention':'visio-head-2026'}};
    expect(coordinateCallout(g,e,owner),isEmpty);
    expect(coordinateCallout(g,e,owner,detail:owner['id']),['Rпр=120,25 мм от центра','θ=90° · Visio']);
  });
  test('legend omits unused methods and SVG changes only presentation',(){
    final g=fixture();g.data['control_zones']=[];g.data['control_points']=[];g.data['sections']=[];
    final before=jsonEncode(g.data);
    final svg=exportVesselSvg(g,detail:g.shells.first['id']);
    expect(svg,contains('Обозначения:'));expect(svg,contains('от начала детали'));
    expect(svg, isNot(contains('/ УЗК')));expect(svg,isNot(contains('× ПВК')));
    expect(jsonEncode(g.data),before);
    g.data['print_settings']={'show_dimensions':false};
    expect(exportVesselSvg(g,detail:g.shells.first['id']),isNot(contains('от начала детали')));
  });
}
