import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';
import 'package:es_td_ngo_mobile/screens/vessel_pressure_calculation_screen.dart';
import 'package:es_td_ngo_mobile/widgets/inspection/thickness_defaults_editor.dart';

void main() {
  testWidgets(
      'calculation is saved with the inspection and shared by all measuring points',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final checklist = VesselChecklist()
      ..wallThickness = '12'
      ..additionalData = {
        'strength_calculation_draft': {
          'element': 'cylinder',
          'material_group': 'manual',
          'load_case': 'internal_pressure',
          'fields': {
            'name': 'Обечайка',
            'pressure_mpa': '1,6',
            'diameter_mm': '1000',
            'nominal_mm': '12',
            'temperature_c': '20',
            'material': '09Г2С',
            'weld_factor': '1',
            'c1_mm': '1',
            'c2_mm': '0',
            'c3_mm': '0',
            'manual_stress_mpa': '150',
            'stress_basis': 'Расчёт Р-1'
          }
        }
      };
    checklist.thicknessMeasurements.add(
        ThicknessMeasurement(location: 'Обечайка', sectionNumber: '1')
          ..thickness = 11.5);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: VesselPressureCalculationScreen(
            checklist: checklist, onChanged: () {})));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('calculate-pressure')), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('calculate-pressure')));
    await tester.pump();
    await tester.scrollUntilVisible(
        find.text('Сохранить расчёт и применить порог'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const ValueKey('save-pressure')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-pressure')));
    await tester.pump();
    expect(checklist.thicknessMeasurements.single.minAllowedThickness, 6.37);
    expect(checklist.thicknessMeasurements.single.thickness, 11.5);
    final restored =
        VesselChecklist.fromJson(jsonDecode(jsonEncode(checklist.toJson())));
    expect(restored.thicknessDefaults.minAllowedThickness, 6.37);
    expect(
        (restored.additionalData?['strength_calculations'] as List)
            .single['inputs']['pressure_mpa'],
        1.6);
    expect(restored.calculationData?['min_thickness'], 6.37);
  });
  testWidgets(
      'shared fields reflect a computed limit without resetting decimal input',
      (tester) async {
    var settings =
        const ThicknessDefaults(nominalThickness: 12, minAllowedThickness: 6);
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return ThicknessDefaultsEditor(
          settings: settings,
          onChanged: (value) => setState(() => settings = value));
    }))));
    await tester.enterText(
        find.byKey(const ValueKey('shared-nominal-thickness')), '12,5');
    await tester.pump();
    update(() => settings = const ThicknessDefaults(
        nominalThickness: 12.5, minAllowedThickness: 8));
    await tester.pump();
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('shared-nominal-thickness')))
            .controller!
            .text,
        '12,5');
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('shared-min-allowed-thickness')))
            .controller!
            .text,
        '8.0');
  });
}
