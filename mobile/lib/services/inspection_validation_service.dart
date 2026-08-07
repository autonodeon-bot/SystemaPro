/// Валидация чек-листа обследования перед подписанием / синхронизацией.
library;

import 'dart:io';

import '../models/vessel_checklist.dart';

class InspectionValidationResult {
  final List<String> missingRequired;
  final List<String> warnings;

  const InspectionValidationResult({
    this.missingRequired = const [],
    this.warnings = const [],
  });

  bool get isComplete => missingRequired.isEmpty;
}

/// Проверка обязательных полей для подписания ТО (сосуды и аналоги).
InspectionValidationResult validateInspectionForSign({
  required VesselChecklist checklist,
  required List<String> selectedEquipmentIds,
  List<Map<String, dynamic>> manualVerificationEquipment = const [],
  File? factoryPlatePhoto,
  File? controlSchemeImage,
  bool requireThickness = true,
}) {
  final missing = <String>[];
  final warnings = <String>[];

  if (checklist.inspectionDate == null || checklist.inspectionDate!.trim().isEmpty) {
    missing.add('Дата обследования');
  }
  if (checklist.executors == null || checklist.executors!.trim().isEmpty) {
    if (checklist.inspectionEngineers.isEmpty) {
      missing.add('Исполнители');
    }
  }
  if (checklist.organization == null || checklist.organization!.trim().isEmpty) {
    missing.add('Организация (заказчик)');
  }
  if (selectedEquipmentIds.isEmpty && manualVerificationEquipment.isEmpty) {
    missing.add('Оборудование для поверок');
  }

  final hasPlate = (factoryPlatePhoto != null && factoryPlatePhoto.existsSync()) ||
      (checklist.factoryPlatePhoto != null &&
          checklist.factoryPlatePhoto!.trim().isNotEmpty);
  if (!hasPlate) {
    missing.add('Фото заводской таблички');
  }

  final hasSchemeFromFile =
      controlSchemeImage != null && controlSchemeImage.existsSync();
  final hasSchemeFromChecklist = checklist.controlSchemeImage != null &&
      checklist.controlSchemeImage!.trim().isNotEmpty;
  final hasSchemeFromUzt = checklist.uztSchemes.any(
    (s) => (s.schemeImagePath ?? '').trim().isNotEmpty,
  );
  if (!hasSchemeFromFile && !hasSchemeFromChecklist && !hasSchemeFromUzt) {
    missing.add('Схема контроля');
  }

  if (checklist.conclusion == null || checklist.conclusion!.trim().isEmpty) {
    missing.add('Заключение');
  }

  final hasThickness = checklist.thicknessMeasurements.isNotEmpty ||
      checklist.uztSchemes.any((s) => s.measurements.isNotEmpty);
  final methods = checklist.ndtMethods.map((e) => e.toUpperCase()).toList();
  final needsUzt = methods.isEmpty ||
      methods.any((m) => m.contains('UZT') || m.contains('УЗТ'));
  if (requireThickness && needsUzt && !hasThickness) {
    missing.add('Точки ультразвуковой толщинометрии (УЗТ)');
  }

  for (final eng in checklist.inspectionEngineers) {
    if ((eng.fullName ?? '').trim().isEmpty) {
      warnings.add('Не указано ФИО специалиста для метода ${eng.method}');
    }
  }

  if (checklist.vesselName == null || checklist.vesselName!.trim().isEmpty) {
    warnings.add('Не указано наименование объекта');
  }
  if (checklist.serialNumber == null || checklist.serialNumber!.trim().isEmpty) {
    warnings.add('Не указан заводской номер');
  }

  return InspectionValidationResult(
    missingRequired: missing,
    warnings: warnings,
  );
}
