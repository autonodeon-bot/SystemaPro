import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/models/vessel_geometry.dart';
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';
import 'package:es_td_ngo_mobile/widgets/vessel_drawing.dart';
import 'package:es_td_ngo_mobile/services/vessel_svg_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final raw = jsonDecode(File('assets/data/visio_vessel_example.json').readAsStringSync()) as Map<String,dynamic>;
  test('Visio example contains selectable shells, heads, cover and every measurement', () {
    expect(VesselChecklist.fromJson({'test_data':true}).toJson()['test_data'],isTrue);
    final g=VesselGeometry.fromExample(raw);
    final other=VesselGeometry.fromExample(raw);
    expect(g.data['model_id'],isNot(other.data['model_id']));
    expect(g.parts.map((p)=>p['id']).toSet().intersection(other.parts.map((p)=>p['id']).toSet()),isEmpty);
    g.validateForSave();
    expect(g.shells.length,6);expect(g.elements.length,25);expect(g.points.length,138);
    for (final orientation in ['horizontal','vertical']) {
      g.data['orientation']=orientation;
      final layout=VesselDrawingLayout(g,const Size(1190,842));
      expect(layout.parts.length,9);
      expect(layout.marks.length,163);
      for (final p in g.points) {
        final at=layout.marks[p['id']]!;
        expect((Offset.zero & const Size(1190,842)).contains(at),isTrue);
        expect(layout.hit(at),contains(p['id']));
      }
      final cover=g.parts.firstWhere((p)=>p['kind']=='cover');
      final rect=layout.parts[cover['id']]!;
      for (final e in g.elements.where((e)=>e['parent_id']==cover['id'])) {
        expect(rect.contains(layout.marks[e['id']]!),isTrue);
      }
      expect(exportVesselSvg(g),contains('Крышка люка Т'));
    }
  });
  test('native reference render with all parts', () async {
    final loader=FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync())));
    await loader.load();
    final g=VesselGeometry.load(raw);
    final recorder=ui.PictureRecorder();
    final canvas=Canvas(recorder)..scale(1.5);
    VesselDrawingPainter(VesselDrawingLayout(g,const Size(1190,842))).paint(canvas,const Size(1190,842));
    final picture=recorder.endRecording();
    final image=await picture.toImage(1785,1263);
    final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    File('../artifacts/vessel-constructor-v2/visio-native.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();picture.dispose();
  });
}
