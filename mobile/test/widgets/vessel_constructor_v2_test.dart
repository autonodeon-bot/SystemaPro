import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:es_td_ngo_mobile/screens/vessel_constructor_v2_screen.dart';
import 'package:es_td_ngo_mobile/models/vessel_geometry.dart';
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';
import 'package:es_td_ngo_mobile/widgets/vessel_drawing.dart';
import 'package:es_td_ngo_mobile/services/vessel_constructor_store.dart';

void main() {
  test('UZT overview projection separates points and preserves measured values', () {
    final g = VesselGeometry.create();
    // Use existing template generation to exercise the actual constructor layout.
    g.setPointTemplate(g.shells.first['id'], 12);
    final checklist = VesselChecklist()
      ..baseVesselScheme = (BaseVesselScheme()..geometry = g.data);
    for (final p in g.points) {
      checklist.thicknessMeasurements.add(ThicknessMeasurement(location: 'shell', sectionNumber: '${p['local_number']}')
        ..schemePointId = p['id']..thickness = 10.7);
    }
    syncVesselMeasurementProjection(checklist);
    expect(checklist.thicknessMeasurements.map((p) => '${p.xPercent},${p.yPercent}').toSet().length, 12);
    expect(checklist.thicknessMeasurements.every((p) => p.xPercent! > 0 && p.yPercent! > 0 && p.thickness == 10.7), isTrue);
  });
  test('draft retains revision, selection and independent original snapshot',
      () async {
    final original = VesselGeometry.create();
    final input = VesselGeometry.copy(original.data);
    final store =
        VesselConstructorStore(VesselGeometry.load(input), 'store-test');
    store.command((g) {
      store.selection = g.addElement(g.shells.first['id'], 'nozzle')['id'];
    });
    await store.flush();
    expect(store.saveStatus, 'Сохранено на устройстве');
    final restored =
        VesselConstructorStore(VesselGeometry.create(), 'store-test');
    restored.restore((await restored.readDraft())!);
    expect(restored.geometry.elements.length, 1);
    expect(restored.selection, store.selection);
    expect(input['elements'], isEmpty);
    store.undo();
    expect(store.geometry.elements, isEmpty);
    store.redo();
    expect(store.geometry.elements.length, 1);
    await store.discard();
    expect(await restored.readDraft(), isNull);
    store.dispose();
    restored.dispose();
  });
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/arial.ttf');
    if (font.existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('vessel-ui-').path);
  });
  for (final screen in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('constructor layout and actions $screen', (tester) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final g = VesselGeometry.create();
      g.addShell();
      g.addElement(g.shells.first['id'], 'manway');
      final boundary = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          home: RepaintBoundary(
              key: boundary,
              child: VesselConstructorV2Screen(
                  initialGeometry: g.data, draftKey: 'test_${screen.width}'))));
      // sqflite runs on a real isolate outside the fake test clock.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.pumpAndSettle();
      expect(find.text('Конструктор сосуда'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Обечаек: 2'), findsOneWidget);
      await tester.tap(find.textContaining('Обечаек: 2'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Обечаек: 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Обечаек: 2'), findsOneWidget);
      await tester.tap(find.text('Элемент'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Штуцер'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('../artifacts/vessel-constructor-v2')
          ..createSync(recursive: true);
        File('${dir.path}/ui-${screen.width.toInt()}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
