import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';
import 'package:es_td_ngo_mobile/screens/thickness_measurement_screen.dart';

void main() {
  testWidgets('large image and touch markers share fitted phone coordinates', (tester) async {
    final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File('C:/Windows/Fonts/arial.ttf').readAsBytesSync())));
    await loader.load();
    tester.view.physicalSize = const Size(360, 772);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('uzt-layout-');
    final file = File('${dir.path}/scheme.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width:1785,height:1263)));
    final points = [
      ThicknessMeasurement(location:'shell',sectionNumber:'1')..xPercent=25..yPercent=25..thickness=10.7,
      ThicknessMeasurement(location:'shell',sectionNumber:'2')..xPercent=75..yPercent=75,
    ];
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home:ThicknessMeasurementScreen(schemeImage:file,existingMeasurements:points)));
      await Future<void>.delayed(const Duration(seconds:1));
    });
    await tester.pumpAndSettle();
    final viewer = find.byType(InteractiveViewer);
    final image = find.descendant(of:viewer,matching:find.byType(Image));
    final first = find.descendant(of:viewer,matching:find.text('1'));
    final second = find.descendant(of:viewer,matching:find.text('2'));
    final imageRect = tester.getRect(image);
    expect(imageRect.contains(tester.getCenter(first)),isTrue);
    expect(imageRect.contains(tester.getCenter(second)),isTrue);
    expect((tester.getCenter(second)-tester.getCenter(first)).distance,greaterThan(50));
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text('Параметры точки замера'),findsOneWidget);
    expect(points.length,2);
    expect(points.first.thickness,10.7);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
