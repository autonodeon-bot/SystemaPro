import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';
import 'package:es_td_ngo_mobile/screens/thickness_measurement_screen.dart';
import 'package:es_td_ngo_mobile/theme/app_theme.dart';
import 'package:es_td_ngo_mobile/widgets/checklist_progress_indicator.dart';
import 'package:es_td_ngo_mobile/widgets/inspection/thickness_defaults_editor.dart';

void main() {
  for (final dark in [false, true]) {
    for (final size in [const Size(320, 800), const Size(800, 360)]) {
      testWidgets('measurement controls and fullscreen: dark=$dark size=$size',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: const ThicknessMeasurementScreen(
                thicknessDefaults: ThicknessDefaults(
                    nominalThickness: 12, minAllowedThickness: 6.37))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Развернуть схему'));
        await tester.pumpAndSettle();
        expect(find.text('Общие толщины сосуда'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Показать точки и параметры'));
        await tester.pumpAndSettle();
        expect(find.text('Общие толщины сосуда'), findsOneWidget);
      });
    }
    for (final scale in [1.5, 2.0]) {
      testWidgets('required fields wrap at font $scale, dark=$dark',
          (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
                body: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: ChecklistProgressIndicator(
                            completedFields: 1,
                            totalFields: 11,
                            missingRequiredFields: [
                              'Дата обследования',
                              'Исполнители',
                              'Организация'
                            ]))))));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Не заполнены обязательные поля:'), findsOneWidget);
      });
    }
  }
  testWidgets(
      'invalid thickness is explained and never replaces the saved limit',
      (tester) async {
    var saved = const ThicknessDefaults(
        nominalThickness: 12, minAllowedThickness: 6.37);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ThicknessDefaultsEditor(
                settings: saved, onChanged: (v) => saved = v))));
    await tester.enterText(
        find.byKey(const ValueKey('shared-nominal-thickness')), '-5');
    await tester.pump();
    expect(find.text('Введите положительное число, например 12,5'),
        findsOneWidget);
    expect(saved.nominalThickness, 12);
    await tester.enterText(
        find.byKey(const ValueKey('shared-nominal-thickness')), '12,5');
    await tester.pump();
    expect(saved.nominalThickness, 12.5);
    expect(saved.minAllowedThickness, 6.37);
  });
}
