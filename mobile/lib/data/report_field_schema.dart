import 'dart:convert';
import 'package:flutter/services.dart';

class ReportFieldSchema {
  static Map<String, dynamic>? _schema;
  static Future<void> ensureLoaded() async {
    _schema ??= json.decode(await rootBundle.loadString('assets/data/report_fields.json')) as Map<String, dynamic>;
  }
  static List<Map<String, dynamic>> fieldsFor(String formId) {
    final profile = (_schema?['forms'] as Map?)?[formId];
    final fields = (_schema?['profiles'] as Map?)?[profile];
    return fields is List ? fields.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
  }
  static List<String> validate(String formId, Map values) {
    if (values.isNotEmpty && _schema == null) return ['Справочник характеристик ещё не загружен'];
    final errors = <String>[];
    for (final field in fieldsFor(formId)) {
      final raw = values[field['key']]?.toString().trim() ?? '';
      if (raw.isEmpty || field['type'] != 'number') continue;
      final number = num.tryParse(raw.replaceAll(',', '.'));
      if (number == null || !number.isFinite || (field['min'] != null && number < (field['min'] as num))) {
        errors.add('${field['label']}: укажите корректное число (${field['unit']})');
      }
    }
    return errors;
  }

  static List<Map<String, dynamic>> measurementColumns(String formId) {
    final profile = (_schema?['forms'] as Map?)?[formId];
    final fields = (_schema?['measurements'] as Map?)?[profile];
    return fields is List ? fields.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
  }

  static List<String> validateMeasurements(String formId, List rows) {
    final errors = <String>[];
    for (var i = 0; i < rows.length; i++) {
      if (rows[i] is! Map) { errors.add('Измерение ${i + 1}: неверный формат'); continue; }
      for (final field in measurementColumns(formId)) {
        final raw = rows[i][field['key']]?.toString().trim() ?? '';
        if (raw.isEmpty || field['type'] != 'number') continue;
        final value = num.tryParse(raw.replaceAll(',', '.'));
        if (value == null || !value.isFinite || (field['min'] != null && value < field['min'])) {
          errors.add('Измерение ${i + 1}, ${field['label']}: укажите корректное число');
        }
      }
    }
    return errors;
  }
}
