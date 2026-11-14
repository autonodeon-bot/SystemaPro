import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';
import 'package:es_td_ngo_mobile/screens/thickness_measurement_screen.dart';

void main() {
  testWidgets(
      'back from the measuring map returns points and shared thicknesses',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original =
        ThicknessMeasurement(location: 'Обечайка', sectionNumber: '1')
          ..thickness = 11.5;
    Map<String, dynamic>? result;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
              body: TextButton(
                  onPressed: () async {
                    result = await context.push<Map<String, dynamic>>('/map');
                  },
                  child: const Text('Карта')))),
      GoRoute(
          path: '/map',
          builder: (context, state) => ThicknessMeasurementScreen(
              existingMeasurements: [original],
              thicknessDefaults: const ThicknessDefaults(
                  nominalThickness: 12, minAllowedThickness: 6.37)))
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Карта'));
    await tester.pumpAndSettle();
    expect(original.minAllowedThickness, isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final point =
        (result!['measurements'] as List<ThicknessMeasurement>).single;
    expect(point.thickness, 11.5);
    expect(point.nominalThickness, 12);
    expect(point.minAllowedThickness, 6.37);
    expect(
        (result!['thicknessDefaults'] as ThicknessDefaults).minAllowedThickness,
        6.37);
    expect(original.minAllowedThickness, isNull);
  });
}
