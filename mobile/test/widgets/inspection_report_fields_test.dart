import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';
import 'package:es_td_ngo_mobile/widgets/inspection/inspection_report_fields_section.dart';

void main() {
  testWidgets('supplement remains editable on a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final checklist = VesselChecklist();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(320, 700), textScaler: TextScaler.linear(1.5)),
        child: Scaffold(body: SafeArea(child: ListView(
          padding: const EdgeInsets.all(16),
          children: [InspectionReportFieldsSection(checklist: checklist, onChanged: () {})],
        ))),
      ),
    ));
    await tester.ensureVisible(find.text('Добавить показатель'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить показатель'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final valueField = find.byType(TextFormField).at(2);
    await tester.ensureVisible(valueField);
    await tester.pumpAndSettle();
    await tester.enterText(valueField, '0');
    expect((checklist.additionalData!['report_fields'] as List).first['value'], '0');
    expect(tester.takeException(), isNull);
  });
}
