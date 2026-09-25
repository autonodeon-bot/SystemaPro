import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/data/report_field_schema.dart';
import '../../lib/models/vessel_checklist.dart';
import '../../lib/widgets/inspection/inspection_profile_measurements.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('removing a measurement preserves remaining row values', (tester) async {
    await ReportFieldSchema.ensureLoaded();
    final checklist = VesselChecklist()..reportFormId = 'to-5'..additionalData = {'profile_measurements': [
      {'point': 'Первая', 'ground': '1,5'}, {'point': 'Вторая', 'ground': '0'}
    ]};
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: InspectionProfileMeasurements(checklist: checklist, onChanged: () {})))));
    await tester.tap(find.byTooltip('Удалить измерение 1'));
    await tester.pump();
    expect(find.text('Вторая'), findsOneWidget);
    expect(find.text('Первая'), findsNothing);
    expect((checklist.additionalData!['profile_measurements'] as List).single['ground'], '0');
    expect(tester.takeException(), isNull);
  });
}
