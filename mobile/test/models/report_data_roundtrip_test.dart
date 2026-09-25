import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/models/compressor_checklist.dart';
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';
import 'package:es_td_ngo_mobile/models/equipment.dart';
import 'package:es_td_ngo_mobile/data/technical_report_form_registry.dart';

void main() {
  test('compressor restores every common field without losing report data', () {
    final source = VesselChecklist()
      ..equipmentTypeCode = 'COMPRESSOR'
      ..documents = {'1': true}
      ..reportFormId = 'to-12'
      ..inspectionType = 'NDT'
      ..vesselName = 'Компрессор К-1'
      ..serialNumber = '123'
      ..workingPressure = '1,6'
      ..wallThickness = '8'
      ..diameter = '300'
      ..additionalData = {'report_fields': [{'label': 'Вибрация', 'value': '0', 'unit': 'мм/с'}]}
      ..documentsInfo = {'1': {'number': 'П-1', 'date': '2026-09-18', 'pages': '24'}};
    final input = source.toJson();
    final restored = CompressorChecklist.fromJson({...input, 'power_rating': '250'}).toJson();
    for (final key in input.keys) {
      expect(restored[key], input[key], reason: 'Lost common field: $key');
    }
    expect(restored['power_rating'], '250');
  });

  test('mobile chooses specific equipment forms', () {
    for (final row in [
      ['CRANE_RUNWAY', 'Подкрановые пути', 'to-2'],
      ['PIPELINE', 'Подземный трубопровод', 'to-33'],
      ['PIPELINE_VALVE', 'Кран шаровой', 'to-24'],
      ['', 'Фонтанная арматура', 'to-27'],
    ]) {
      expect(TechnicalReportFormRegistry.suggestFormId(
        Equipment(id: '1', typeCode: row[0], name: row[1]),
      ), row[2]);
    }
  });
}
