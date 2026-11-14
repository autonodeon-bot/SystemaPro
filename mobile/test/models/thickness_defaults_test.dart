import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';

void main() {
  test(
      'passport nominal thickness and shared limit fill old and new points without measured values',
      () {
    final checklist = VesselChecklist()..wallThickness = '12,5';
    final first = ThicknessMeasurement(location: 'Обечайка', sectionNumber: '1')
      ..thickness = 11.8;
    checklist.thicknessMeasurements.add(first);
    checklist.setThicknessDefaults(const ThicknessDefaults(
        nominalThickness: 12.5, minAllowedThickness: 8, basis: 'Расчёт Р-1'));
    checklist.thicknessMeasurements
        .add(ThicknessMeasurement(location: 'Обечайка', sectionNumber: '2'));
    final restored =
        VesselChecklist.fromJson(jsonDecode(jsonEncode(checklist.toJson())));
    expect(restored.thicknessDefaults.basis, 'Расчёт Р-1');
    expect(restored.thicknessMeasurements.map((p) => p.nominalThickness),
        [12.5, 12.5]);
    expect(restored.thicknessMeasurements.map((p) => p.minAllowedThickness),
        [8, 8]);
    expect(
        restored.thicknessMeasurements.map((p) => p.thickness), [11.8, null]);
  });
  test(
      'changing shared values preserves individual element values and measurements',
      () {
    final checklist = VesselChecklist()..wallThickness = '10';
    checklist.thicknessMeasurements.addAll([
      ThicknessMeasurement(location: 'Обечайка', sectionNumber: '1')
        ..nominalThickness = 10
        ..minAllowedThickness = 6
        ..thickness = 9.4,
      ThicknessMeasurement(location: 'Днище', sectionNumber: '2')
        ..nominalThickness = 14
        ..minAllowedThickness = 9
        ..thickness = 13.1,
    ]);
    checklist.setThicknessDefaults(
        const ThicknessDefaults(nominalThickness: 10, minAllowedThickness: 6));
    checklist.setThicknessDefaults(
        const ThicknessDefaults(nominalThickness: 12, minAllowedThickness: 7));
    expect(checklist.thicknessMeasurements.map((p) => p.nominalThickness),
        [12, 14]);
    expect(checklist.thicknessMeasurements.map((p) => p.minAllowedThickness),
        [7, 9]);
    expect(
        checklist.thicknessMeasurements.map((p) => p.thickness), [9.4, 13.1]);
  });
  test('missing engineering limit is not guessed from nominal thickness', () {
    final checklist = VesselChecklist()..wallThickness = '10';
    expect(checklist.thicknessDefaults.minAllowedThickness, isNull);
    expect(ThicknessDefaults.parse('NaN'), isNull);
    expect(ThicknessDefaults.parse('-1'), isNull);
  });
  test(
      'numeric passport fields and additional entered values survive reopening',
      () {
    final checklist = VesselChecklist.fromJson({
      'manufacture_year': 2020,
      'wall_thickness': 12.5,
      'working_pressure': 1.6,
      'diameter': 1200,
      'serial_number': 147,
      'additional_data': {
        'profile_values': {'material': '09Г2С'},
        'report_fields': [
          {'value': 'Данные инженера'}
        ]
      }
    });
    final restored =
        VesselChecklist.fromJson(jsonDecode(jsonEncode(checklist.toJson())));
    expect(restored.wallThickness, '12.5');
    expect(restored.manufactureYear, '2020');
    expect(restored.serialNumber, '147');
    expect(restored.additionalData?['profile_values']['material'], '09Г2С');
    expect(restored.additionalData?['report_fields'][0]['value'],
        'Данные инженера');
  });
}
