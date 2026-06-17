import 'package:flutter/material.dart';

/// Действие пункта меню «создать» (по файлу «структура диагностических данных.xlsx»).
enum DiagnosticMenuAction {
  emergencyInspection,
  expressNdtVik,
  expressNdtUzt,
  expressNdtUzk,
  expressNdtPvk,
  pressureGi,
  pressurePi,
  pressurePsGpm,
  newProtocolWizard,
  experienceBase,
  customTemplate,
}

/// Пункт дерева «Быстрый контроль» / вложенные методы НК, ГИ/ПИ.
class DiagnosticQuickControlNode {
  final String id;
  final String title;
  final String? subtitle;
  final String? protocolHint;
  final DiagnosticMenuAction? action;
  final List<DiagnosticQuickControlNode> children;
  final IconData icon;

  const DiagnosticQuickControlNode({
    required this.id,
    required this.title,
    this.subtitle,
    this.protocolHint,
    this.action,
    this.children = const [],
    this.icon = Icons.description_outlined,
  });

  bool get isLeaf => action != null;
}

/// Архетип оборудования в опытной базе (колонка «ДАННЫЕ/ОПЫТНАЯ БАЗА»).
class DiagnosticEquipmentArchetype {
  final String kind;
  final String exampleMark;

  const DiagnosticEquipmentArchetype({
    required this.kind,
    this.exampleMark = '',
  });

  String get displayLabel {
    if (kind.isEmpty) return exampleMark;
    if (exampleMark.isEmpty) return kind;
    return '$kind\n$exampleMark';
  }
}

/// Категория «Новый протокол» (колонка «РАЗДЕЛ»).
class DiagnosticObjectCategory {
  final String id;
  final String title;
  final IconData icon;
  /// Код для SelectEquipmentForActScreen / фильтра типов.
  final String equipmentPreset;
  final List<DiagnosticEquipmentArchetype> archetypes;
  final List<String> inspectionTypeLabels;

  const DiagnosticObjectCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.equipmentPreset,
    this.archetypes = const [],
    this.inspectionTypeLabels = const [],
  });
}

/// Статическая структура меню и справочника (источник — xlsx, лист «Лист1»).
class DiagnosticMenuStructure {
  DiagnosticMenuStructure._();

  static const String newProtocolDescription =
      'Протоколы на все типы обследования; пополняемая опытная база по маркам и модификациям '
      'оборудования. Данные привязываются к паре «Задание» — «Объект».';

  static const List<DiagnosticQuickControlNode> quickControlTree = [
    DiagnosticQuickControlNode(
      id: 'emergency',
      title: 'Аварийный, внеплановый контроль (осмотр)',
      subtitle: 'Минимум полей, фиксация аварийной ситуации',
      protocolHint: 'Протокол аварийной ситуации',
      action: DiagnosticMenuAction.emergencyInspection,
      icon: Icons.emergency_share_outlined,
    ),
    DiagnosticQuickControlNode(
      id: 'express_ndt',
      title: 'Экспресс-диагностика НК',
      subtitle: 'ВИК, УЗТ, УЗК, ПВК',
      protocolHint: 'Протоколы НК (шаблоны по методам)',
      icon: Icons.speed_outlined,
      children: [
        DiagnosticQuickControlNode(
          id: 'vik',
          title: 'ВИК',
          action: DiagnosticMenuAction.expressNdtVik,
          icon: Icons.visibility_outlined,
        ),
        DiagnosticQuickControlNode(
          id: 'uzt',
          title: 'УЗТ',
          action: DiagnosticMenuAction.expressNdtUzt,
          icon: Icons.straighten_outlined,
        ),
        DiagnosticQuickControlNode(
          id: 'uzk',
          title: 'УЗК',
          action: DiagnosticMenuAction.expressNdtUzk,
          icon: Icons.graphic_eq,
        ),
        DiagnosticQuickControlNode(
          id: 'pvk',
          title: 'ПВК',
          action: DiagnosticMenuAction.expressNdtPvk,
          icon: Icons.blur_circular_outlined,
        ),
      ],
    ),
    DiagnosticQuickControlNode(
      id: 'pressure',
      title: 'Опрессовка',
      subtitle: 'ГИ, ПИ, испытания ПС и ГПМ',
      protocolHint: 'Протоколы опрессовки / испытаний',
      icon: Icons.plumbing_outlined,
      children: [
        DiagnosticQuickControlNode(
          id: 'gi',
          title: 'ГИ',
          subtitle: 'Гидравлические испытания',
          action: DiagnosticMenuAction.pressureGi,
          icon: Icons.water_drop_outlined,
        ),
        DiagnosticQuickControlNode(
          id: 'pi',
          title: 'ПИ',
          subtitle: 'Пневматические испытания',
          action: DiagnosticMenuAction.pressurePi,
          icon: Icons.compress_outlined,
        ),
        DiagnosticQuickControlNode(
          id: 'ps_gpm',
          title: 'Испытание ПС и ГПМ',
          subtitle: 'Статика и динамика',
          action: DiagnosticMenuAction.pressurePsGpm,
          icon: Icons.precision_manufacturing_outlined,
        ),
      ],
    ),
  ];

  static const List<DiagnosticObjectCategory> objectCategories = [
    DiagnosticObjectCategory(
      id: 'srpd',
      title: 'СРпД (сосуды, аппараты, ёмкости)',
      icon: Icons.propane_tank_outlined,
      equipmentPreset: 'vessel',
      inspectionTypeLabels: ['НиВО', 'ГИ (ПИ + АЭ)', 'ТД', 'ЭПБ'],
      archetypes: [
        DiagnosticEquipmentArchetype(kind: 'Сепаратор', exampleMark: 'М-103А'),
        DiagnosticEquipmentArchetype(kind: 'Ресивер', exampleMark: ''),
        DiagnosticEquipmentArchetype(
          kind: 'Ёмкость подземная',
          exampleMark: 'ЕП-12,5-2000-1300-2',
        ),
        DiagnosticEquipmentArchetype(
          kind: 'Нефтегазосепаратор',
          exampleMark: 'НГС1-1,0-3000-2',
        ),
        DiagnosticEquipmentArchetype(
          kind: 'Нефтегазосепаратор',
          exampleMark: 'НГС-1-10-2600-0,9Г2С',
        ),
        DiagnosticEquipmentArchetype(kind: 'Сепаратор факельный', exampleMark: 'СФ'),
        DiagnosticEquipmentArchetype(kind: 'Отстойник', exampleMark: 'ОГ-200'),
        DiagnosticEquipmentArchetype(
          kind: 'Воздухосборник',
          exampleMark: 'V-2,7 м³',
        ),
      ],
    ),
    DiagnosticObjectCategory(
      id: 'bu',
      title: 'БУ (буровая установка)',
      icon: Icons.architecture,
      equipmentPreset: 'drilling',
      inspectionTypeLabels: ['ТД (ЭПБ)'],
      archetypes: [
        DiagnosticEquipmentArchetype(
          kind: 'Буровая установка',
          exampleMark: 'БУ 3000 ЭУК-1М',
        ),
        DiagnosticEquipmentArchetype(
          kind: 'Буровая установка',
          exampleMark: 'БУ 3900/225 ЭК-БМ',
        ),
        DiagnosticEquipmentArchetype(
          kind: 'Буровая установка',
          exampleMark: 'БУ 2900/175 ДЭП-11',
        ),
        DiagnosticEquipmentArchetype(
          kind: 'Буровая установка',
          exampleMark: 'БУ 2900/175 ЭПК БМ',
        ),
      ],
    ),
    DiagnosticObjectCategory(
      id: 'boiler',
      title: 'Котёл',
      icon: Icons.local_fire_department_outlined,
      equipmentPreset: 'boiler',
      inspectionTypeLabels: ['НиВО', 'ГИ (ПИ + АЭ)', 'ТД', 'ЭПБ'],
      archetypes: [
        DiagnosticEquipmentArchetype(kind: 'Котёл паровой', exampleMark: 'Е 1,0-0,9М'),
        DiagnosticEquipmentArchetype(kind: 'Котёл паровой', exampleMark: 'КПН-1,0-9М'),
        DiagnosticEquipmentArchetype(kind: 'Котёл паровой', exampleMark: 'ПКН-2М'),
        DiagnosticEquipmentArchetype(kind: 'Горелка', exampleMark: 'PN-65'),
        DiagnosticEquipmentArchetype(kind: 'Горелка', exampleMark: 'PN-70'),
      ],
    ),
    DiagnosticObjectCategory(
      id: 'bo',
      title: 'БО (буровое оборудование)',
      icon: Icons.build_circle_outlined,
      equipmentPreset: 'other',
      inspectionTypeLabels: ['ТД (ЭПБ)'],
      archetypes: [
        DiagnosticEquipmentArchetype(
          kind: 'Насос буровой трехпоршневой',
          exampleMark: 'УНБ-600',
        ),
        DiagnosticEquipmentArchetype(
          kind: 'Насос буровой трехпоршневой',
          exampleMark: 'УНБТ-1180',
        ),
        DiagnosticEquipmentArchetype(kind: 'Ротор буровой', exampleMark: 'Р-700'),
        DiagnosticEquipmentArchetype(
          kind: 'Лебедка буровая',
          exampleMark: 'ЛБУ-750Э-СНГ',
        ),
        DiagnosticEquipmentArchetype(
          kind: 'Лебедка вспомогательная',
          exampleMark: 'ЛВ-44-1',
        ),
      ],
    ),
    DiagnosticObjectCategory(
      id: 'valve_ps',
      title: 'Клапан предохранительный',
      icon: Icons.air_outlined,
      equipmentPreset: 'valve_ps',
      inspectionTypeLabels: [
        'ТД (ЭПБ)',
        'Испытания (тарировка, опрессовка и т.д.)',
      ],
      archetypes: [
        DiagnosticEquipmentArchetype(
          kind: 'СППК',
          exampleMark: '4P 80-40',
        ),
        DiagnosticEquipmentArchetype(
          kind: 'СППК',
          exampleMark: '4 50х16 УХЛ1',
        ),
        DiagnosticEquipmentArchetype(
          kind: 'Клапан предохранительно-сбросной',
          exampleMark: 'ПСК 535 DN20 PN40',
        ),
        DiagnosticEquipmentArchetype(
          kind: 'СППК',
          exampleMark: '5 100х16 УХЛ1',
        ),
      ],
    ),
  ];

}
