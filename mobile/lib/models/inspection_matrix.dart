import 'package:flutter/material.dart';

/// Направление обследования из xlsx (НиВО / ГИ+ПИ+АЭ / ТД / ЭПБ).
class InspectionMatrixDirection {
  final String id;
  final String title;
  final IconData icon;

  const InspectionMatrixDirection({
    required this.id,
    required this.title,
    required this.icon,
  });
}

/// Тип чек-листа / акта для [SelectEquipmentForActScreen].
String inspectionTypeForDirection(String directionId) {
  switch (directionId) {
    case 'external':
      return 'VISUAL';
    case 'internal':
      return 'EXPERTISE';
    case 'technical':
      return 'NDT';
    default:
      return 'NDT';
  }
}

/// Разбор подписей «ТИП ОБСЛЕДОВАНИЯ» категории в пункты мастера.
List<InspectionMatrixDirection> directionsFromLabels(List<String> labels) {
  final out = <InspectionMatrixDirection>[];
  final used = <String>{};

  void add(String id, String title, IconData icon) {
    if (used.add(id)) {
      out.add(InspectionMatrixDirection(id: id, title: title, icon: icon));
    }
  }

  for (final raw in labels) {
    final u = raw.toUpperCase().replaceAll('\n', ' ');

    if (u.contains('НИВО') || (u.contains('ОСМОТР') && !u.contains('ЭПБ'))) {
      add(
        'external',
        raw.contains('НиВО') ? raw.trim() : 'Наружный / внутренний осмотр (НиВО)',
        Icons.visibility_outlined,
      );
    } else if (u.contains('ГИ') && (u.contains('ПИ') || u.contains('АЭ'))) {
      add(
        'gi_pi_ae',
        raw.trim().isEmpty ? 'ГИ (ПИ + АЭ)' : raw.trim(),
        Icons.plumbing_outlined,
      );
    } else if (u.contains('ИСПЫТАН') || u.contains('ТАРИРОВ')) {
      add(
        'valve_tests',
        raw.trim().isEmpty ? 'Испытания (тарировка, опрессовка)' : raw.trim(),
        Icons.precision_manufacturing_outlined,
      );
    } else if (u.contains('ТД') && u.contains('ЭПБ')) {
      add(
        'internal',
        raw.trim().isEmpty ? 'ТД (ЭПБ)' : raw.trim(),
        Icons.fact_check_outlined,
      );
    } else if (u.contains('ЭПБ')) {
      add('internal', raw.trim().isEmpty ? 'ЭПБ' : raw.trim(), Icons.fact_check_outlined);
    } else if (u.contains('ТД')) {
      add('technical', raw.trim().isEmpty ? 'ТД' : raw.trim(), Icons.biotech_outlined);
    } else if (u == 'ГИ' || u.startsWith('ГИ ')) {
      add('hydraulic', raw.trim(), Icons.water_drop_outlined);
    } else if (u == 'ПИ' || u.startsWith('ПИ ')) {
      add('pneumatic', raw.trim(), Icons.compress_outlined);
    } else if (u.contains('АЭ') || u.contains('АКУСТИК')) {
      add('ae', raw.trim().isEmpty ? 'Акустико-эмиссионный контроль (АЭ)' : raw.trim(), Icons.graphic_eq);
    }
  }

  if (out.isEmpty) {
    add('external', 'Наружный осмотр (НиВО)', Icons.visibility_outlined);
    add('gi_pi_ae', 'ГИ (ПИ + АЭ)', Icons.plumbing_outlined);
    add('technical', 'Техническая диагностика (ТД)', Icons.biotech_outlined);
    add('internal', 'Экспертиза (ЭПБ)', Icons.fact_check_outlined);
  }

  add('custom_template', 'Свой протокол из шаблона', Icons.layers_outlined);
  return out;
}
