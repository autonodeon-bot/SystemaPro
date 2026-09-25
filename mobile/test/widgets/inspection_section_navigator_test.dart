import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/widgets/inspection/inspection_section_navigator.dart';

void main() {
  testWidgets('search preserves original page index on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: InspectionSectionNavigator(
      labels: const ['Сведения', 'Документы', 'Паспорт', 'Заключение'], currentPage: 0,
      missingByPage: const {3: 1}, onSelected: (index) => selected = index,
    ))));
    await tester.enterText(find.byType(TextField), 'Заключ');
    await tester.pump();
    await tester.tap(find.text('Заключение'));
    expect(selected, 3);
    expect(tester.takeException(), isNull);
  });
}
