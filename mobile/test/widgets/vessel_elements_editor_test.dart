import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/widgets/vessel_elements_editor.dart';

void main() {
  testWidgets('Elements stay on their part when switching and reopening',
      (tester) async {
    final elements = <Map<String, dynamic>>[];
    Widget editor() => MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: VesselElementsEditor(
                    shellCount: 3,
                    orientation: 'vertical',
                    elements: elements,
                    onChanged: () {}))));
    await tester.pumpWidget(editor());
    await tester.tap(find.text('Добавить: Штуцер'));
    await tester.pump();
    expect(elements.single['part_id'], 'shell_1');
    await tester.tap(find.text('Обечайка 2 (0)'));
    await tester.pump();
    await tester.tap(find.text('Добавить: Штуцер'));
    await tester.pump();
    expect(elements.map((e) => e['part_id']), ['shell_1', 'shell_2']);
    expect(elements.map((e) => e['id']).toSet().length, 2);
    await tester.tap(find.text('Верхнее днище (0)'));
    await tester.pump();
    await tester.tap(find.text('Добавить: Штуцер'));
    await tester.pump();
    expect(elements.last['part_id'], 'head_top');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(editor());
    expect(find.text('Верхнее днище (1)'), findsOneWidget);
    expect(find.text('Обечайка 1 (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
