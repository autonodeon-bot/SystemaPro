import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:es_td_ngo_mobile/models/vessel_geometry.dart';
import 'package:es_td_ngo_mobile/screens/vessel_constructor_v2_screen.dart';
import 'package:es_td_ngo_mobile/theme/app_theme.dart';
import 'package:es_td_ngo_mobile/widgets/vessel_drawing.dart';
import 'package:es_td_ngo_mobile/widgets/vessel_editor_canvas.dart';
import 'package:es_td_ngo_mobile/services/database_service.dart';
import 'package:es_td_ngo_mobile/services/vessel_constructor_store.dart';

Finder get _drawing => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is VesselDrawingPainter);
VesselDrawingPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_drawing).painter! as VesselDrawingPainter;
Future<void> _open(WidgetTester tester, VesselGeometry geometry, String key,
    {bool dark = false, Set<String> measured = const {}}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: VesselConstructorV2Screen(
          measuredPointIds: measured,
          initialGeometry: geometry.data,
          draftKey: key)));
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _select(WidgetTester tester, String id) async {
  final at = _painter(tester).layout.marks[id]!;
  await tester
      .tapAt(tester.renderObject<RenderBox>(_drawing).localToGlobal(at));
  await tester.pumpAndSettle();
  expect(_painter(tester).selection, id);
}

Future<void> _close(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(VesselConstructorV2Screen));
  var saved = false;
  (state.store as VesselConstructorStore).flush().then((_) => saved = true);
  for (var n = 0; n < 100 && !saved; n++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  expect(saved, isTrue);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Части сосуда'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), label);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _tool(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.scrollUntilVisible(button, 200,
      scrollable: find
          .descendant(
              of: find.byType(Dialog), matching: find.byType(Scrollable))
          .first,
      maxScrolls: 80);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('constructor-actions-').path);
  });
  tearDownAll(DatabaseService.resetForTest);
  for (final dark in [false, true]) {
    testWidgets(
        'properties opens for a part and a fitting in ${dark ? 'dark' : 'light'} theme',
        (tester) async {
      final g = VesselGeometry.create();
      final nozzle = g.addElement(g.shells.first['id'], 'nozzle');
      await _open(tester, g, 'properties-$dark', dark: dark);
      await tester.tap(find.text('Свойства'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Размеры и источник'), findsOneWidget);
      Navigator.of(tester.element(find.text('Размеры и источник'))).pop();
      await tester.pumpAndSettle();
      await _select(tester, nozzle['id']);
      await tester.tap(find.text('Свойства'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Свойства элемента'), findsOneWidget);
      expect(find.text('Переместить: нажать место'), findsOneWidget);
      await _close(tester);
    });
  }
  testWidgets('a fitting can be dragged to another place on its part',
      (tester) async {
    final g = VesselGeometry.create();
    final nozzle = g.addElement(g.shells.first['id'], 'nozzle');
    await _open(tester, g, 'drag-fitting');
    await _select(tester, nozzle['id']);
    final before = _painter(tester).layout;
    final rect = before.parts[g.shells.first['id']]!;
    final target =
        Offset(rect.left + rect.width * .73, rect.top + rect.height * .31);
    final box = tester.renderObject<RenderBox>(_drawing);
    await tester.dragFrom(
        box.localToGlobal(before.marks[nozzle['id']]!),
        box.localToGlobal(target) -
            box.localToGlobal(before.marks[nozzle['id']]!));
    await tester.pumpAndSettle();
    final changed = _painter(tester).layout;
    expect((changed.marks[nozzle['id']]! - target).distance, lessThan(3));
    expect(changed.model.elements.single['id'], nozzle['id']);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });
  testWidgets(
      'adding a longitudinal weld asks for its angle instead of silently using zero',
      (tester) async {
    await _open(tester, VesselGeometry.create(), 'new-weld-angle');
    await tester.tap(find.text('Элемент'));
    await tester.pumpAndSettle();
    final entry = find.text('Продольный шов / шов днища');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    final angle = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Угол, °');
    await tester.enterText(angle, '135,5');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    final weld = _painter(tester)
        .layout
        .model
        .welds
        .singleWhere((w) => w['kind'] == 'longitudinal');
    expect(weld['geometry']['theta_deg'], 135.5);
    expect(_painter(tester).selection, weld['id']);
    await _close(tester);
  });

  for (final kind in ['valve', 'elbow']) {
    testWidgets(
        '$kind supports dragging, undo and properties without a blank screen',
        (tester) async {
      final g = VesselGeometry.create();
      final element = g.addElement(g.shells.first['id'], kind);
      await _open(tester, g, 'fitting-$kind');
      await _select(tester, element['id']);
      final layout = _painter(tester).layout,
          rect = _painter(tester).layout.parts[g.shells.first['id']]!;
      final target =
          Offset(rect.left + rect.width * .65, rect.top + rect.height * .25);
      final box = tester.renderObject<RenderBox>(_drawing);
      final origin = box.localToGlobal(layout.marks[element['id']]!);
      await tester.dragFrom(origin, box.localToGlobal(target) - origin);
      await tester.pumpAndSettle();
      expect((_painter(tester).layout.marks[element['id']]! - target).distance,
          lessThan(3));
      await tester.tap(find.byTooltip('Отменить'));
      await tester.pumpAndSettle();
      expect(_painter(tester).layout.model.entity(element['id'])!['placement'],
          element['placement']);
      await tester.tap(find.text('Свойства'));
      await tester.pumpAndSettle();
      expect(find.text('Свойства элемента'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester);
    });
  }
  testWidgets(
      'existing weld angle edits preserve its ID and assigned control zone',
      (tester) async {
    final g = VesselGeometry.create();
    g.addLongWeld(g.shells.first['id'], 90);
    final weld = g.welds.last;
    (g.data['control_zones'] as List).add({
      'id': 'zone-test',
      'weld_id': weld['id'],
      'designation': 'УЗК 1',
      'planned_methods': ['УЗК'],
      'coverage': {'kind': 'whole'}
    });
    await _open(tester, g, 'edit-weld');
    await _choose(tester, weld['designation']);
    await tester.tap(find.text('Свойства'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить положение шва'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Угол, °'),
        '270,5');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Закрыть свойства'));
    await tester.pumpAndSettle();
    expect(
        _painter(tester).layout.model.entity(weld['id'])!['geometry']
            ['theta_deg'],
        270.5);
    expect(_painter(tester).layout.model.zones.single['id'], 'zone-test');
    expect(_painter(tester).layout.model.zones.single['weld_id'], weld['id']);
    await _close(tester);
  });
  testWidgets(
      'grid, snapping, layers and ruler settings are reachable and applied',
      (tester) async {
    final g = VesselGeometry.create();
    final e = g.addElement(g.shells.first['id'], 'valve');
    await _open(tester, g, 'grid-tools');
    await _select(tester, e['id']);
    await tester.tap(find.byTooltip('Инструменты чертежа'));
    await tester.pumpAndSettle();
    for (final label in ['Сетка', 'Привязка к сетке', 'Привязка к швам']) {
      await _tool(tester, label);
    }
    final canvas =
        tester.widget<VesselEditorCanvas>(find.byType(VesselEditorCanvas));
    expect(canvas.grid, isTrue);
    expect(canvas.snap, isTrue);
    expect(canvas.snapWelds, isTrue);
    await _tool(tester, 'Точки');
    expect(
        tester
            .widget<VesselEditorCanvas>(find.byType(VesselEditorCanvas))
            .hiddenLayers,
        contains('Точки'));
    await _tool(tester, 'Линейка');
    expect(
        tester
            .widget<VesselEditorCanvas>(find.byType(VesselEditorCanvas))
            .ruler,
        isTrue);
    await tester.tap(find.byTooltip('Инструменты чертежа'));
    await tester.pumpAndSettle();
    await _tool(tester, 'Выключить линейку');
    final layout = _painter(tester).layout,
        rect = _painter(tester).layout.parts[g.shells.first['id']]!;
    final box = tester.renderObject<RenderBox>(_drawing);
    final start = box.localToGlobal(layout.marks[e['id']]!);
    await tester.dragFrom(
        start,
        box.localToGlobal(Offset(
                rect.left + rect.width * .73, rect.top + rect.height * .31)) -
            start);
    await tester.pumpAndSettle();
    final p = _painter(tester)
        .layout
        .model
        .position(_painter(tester).layout.model.entity(e['id'])!);
    expect(p.x, closeTo(.3, .001));
    expect(p.y, closeTo(.75, .001));
    await _close(tester);
  });
  testWidgets(
      'duplicate, metadata, archive and restore work through the real tools UI',
      (tester) async {
    final g = VesselGeometry.create();
    final e = g.addElement(g.shells.first['id'], 'valve');
    await _open(tester, g, 'metadata-tools');
    await _select(tester, e['id']);
    await tester.tap(find.byTooltip('Инструменты чертежа'));
    await tester.pumpAndSettle();
    await _tool(tester, 'Дублировать элемент');
    expect(_painter(tester).layout.model.elements.length, 2);
    await _tool(tester, 'Переименовать');
    await tester.enterText(find.byType(TextFormField), 'Кран К-101');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(
        _painter(tester)
            .layout
            .model
            .entity(_painter(tester).selection)!['designation'],
        'Кран К-101');
    await _tool(tester, 'Заметка');
    await tester.enterText(find.byType(TextFormField), 'Осмотреть приварку');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    await _tool(tester, 'Заблокировать');
    final copyId = _painter(tester).selection!;
    expect(_painter(tester).layout.model.entity(copyId)!['locked'], true);
    await _tool(tester, 'Разблокировать');
    await tester.tap(find.byTooltip('Закрыть инструменты'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Свойства'));
    await tester.pumpAndSettle();
    await _tool(tester, 'Архивировать элемент');
    await tester.tap(find.byTooltip('Закрыть свойства'));
    await tester.pumpAndSettle();
    expect(_painter(tester).layout.marks.containsKey(copyId), false);
    await tester.tap(find.byTooltip('Инструменты чертежа'));
    await tester.pumpAndSettle();
    await _tool(tester, 'Восстановить');
    expect(_painter(tester).layout.model.entity(copyId)!['editor_note'],
        'Осмотреть приварку');
    expect(_painter(tester).layout.model.entity(copyId)!['archived'], false);
    await tester.tap(find.byTooltip('Закрыть инструменты'));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VesselConstructorV2Screen));
    var saved = false;
    (state.store as VesselConstructorStore).flush().then((_) => saved = true);
    for (var n = 0; n < 100 && !saved; n++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(saved, isTrue,
        reason: 'Очередь реальных записей SQLite должна завершиться');
    final draft =
        await tester.runAsync(() => DatabaseService.getDraft('metadata-tools'));
    expect(
        (draft!['geometry']['elements'] as List)
            .where((x) => x['id'] == copyId)
            .single['designation'],
        'Кран К-101');
    expect(tester.takeException(), isNull);
    await _close(tester);
  });
  testWidgets(
      'keyboard shortcuts duplicate and undo without changing the original element',
      (tester) async {
    final g = VesselGeometry.create(), eKind = 'elbow';
    final e = g.addElement(g.shells.first['id'], eKind);
    await _open(tester, g, 'keyboard-tools');
    await _select(tester, e['id']);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(_painter(tester).layout.model.elements.length, 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(_painter(tester).layout.model.elements.single['id'], e['id']);
    await _close(tester);
  });

  testWidgets(
      'dragging a physical fitting through zoom retains mm, angle and reference weld',
      (tester) async {
    final g = VesselGeometry.create(orientation: 'horizontal');
    g.shells.first['dimensions'] = {'length_mm': 2000, 'diameter_mm': 1000};
    final e = g.addElement(g.shells.first['id'], 'elbow');
    e['placement'] = {
      'mode': 'physical',
      'z_local_mm': 600.0,
      'theta_deg': 90.0,
      'reference_weld_id': g.welds.first['id']
    };
    await _open(tester, g, 'physical-zoom');
    await _select(tester, e['id']);
    tester
        .widget<VesselEditorCanvas>(find.byType(VesselEditorCanvas))
        .transform
        .value = Matrix4.identity()..scale(1.2);
    await tester.pumpAndSettle();
    final layout = _painter(tester).layout,
        r = _painter(tester).layout.parts[g.shells.first['id']]!;
    final box = tester.renderObject<RenderBox>(_drawing),
        target = Offset(r.left + r.width * .5, r.top + r.height * .55);
    final start = box.localToGlobal(layout.marks[e['id']]!);
    await tester.dragFrom(start, box.localToGlobal(target) - start);
    await tester.pumpAndSettle();
    final p = _painter(tester).layout.model.entity(e['id'])!['placement'];
    expect(p['mode'], 'physical');
    expect(p['z_local_mm'], closeTo(1000, .01));
    expect(p['theta_deg'], closeTo(198, .01));
    expect(p['reference_weld_id'], e['placement']['reference_weld_id']);
    await _close(tester);
  });
  testWidgets(
      'moving a measured point asks for a reason and keeps the same point ID',
      (tester) async {
    final g = VesselGeometry.create();
    g.setPointTemplate(g.shells.first['id'], 1);
    final point = g.points.single;
    await _open(tester, g, 'measured-point', measured: {point['id']});
    await _select(tester, point['id']);
    final layout = _painter(tester).layout,
        r = _painter(tester).layout.parts[g.shells.first['id']]!;
    final box = tester.renderObject<RenderBox>(_drawing),
        target = Offset(r.left + r.width * .55, r.top + r.height * .35);
    final start = box.localToGlobal(layout.marks[point['id']]!);
    await tester.dragFrom(start, box.localToGlobal(target) - start);
    await tester.pumpAndSettle();
    expect(find.text('У точки уже есть результат'), findsOneWidget);
    expect(_painter(tester).layout.model.entity(point['id'])!['placement'],
        point['placement']);
    await tester.enterText(
        find.byType(TextFormField), 'Уточнение координаты по чертежу');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    final model = _painter(tester).layout.model;
    expect(model.points.single['id'], point['id']);
    expect(model.data['revision_history'].single['reason'],
        'Уточнение координаты по чертежу');
    expect((model.position(model.points.single).x - .35).abs(), lessThan(.001));
    await _close(tester);
  });
  testWidgets('ruler displays physical distance on a dimensioned development',
      (tester) async {
    final g = VesselGeometry.create();
    g.shells.first['dimensions'] = {'length_mm': 2000, 'diameter_mm': 1000};
    await _open(tester, g, 'ruler-mm');
    await tester.tap(find.byTooltip('Инструменты чертежа'));
    await tester.pumpAndSettle();
    await _tool(tester, 'Линейка');
    final r = _painter(tester).layout.parts[g.shells.first['id']]!,
        box = tester.renderObject<RenderBox>(_drawing);
    for (final y in [.1, .6]) {
      await tester.tapAt(box
          .localToGlobal(Offset(r.left + r.width * .3, r.top + r.height * y)));
      await tester.pumpAndSettle();
    }
    expect(find.text('По развёртке: 1000.0 мм'), findsOneWidget);
    await _close(tester);
  });
}
