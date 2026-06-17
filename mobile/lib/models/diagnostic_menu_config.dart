import 'package:flutter/material.dart';
import 'diagnostic_menu_structure.dart';

/// Пункт верхнего меню «создать» (новый протокол, опытная база, …).
class DiagnosticCreateMenuAction {
  final String id;
  final DiagnosticMenuAction action;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const DiagnosticCreateMenuAction({
    required this.id,
    required this.action,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  factory DiagnosticCreateMenuAction.fromJson(Map<String, dynamic> json) {
    return DiagnosticCreateMenuAction(
      id: json['id']?.toString() ?? '',
      action: DiagnosticMenuConfig.actionFromCode(json['action']?.toString()) ??
          DiagnosticMenuAction.customTemplate,
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      icon: DiagnosticMenuConfig.iconFromCode(json['icon']?.toString()),
      color: _colorFromHex(json['color']?.toString()),
    );
  }
}

Color _colorFromHex(String? hex) {
  if (hex == null || hex.isEmpty) return Colors.blueAccent;
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  if (v == null) return Colors.blueAccent;
  return Color(v);
}

/// Конфигурация меню диагностики (сервер или встроенная).
class DiagnosticMenuConfig {
  final int version;
  final String newProtocolDescription;
  final List<DiagnosticQuickControlNode> quickControlTree;
  final List<DiagnosticObjectCategory> objectCategories;
  final List<DiagnosticCreateMenuAction> createMenuActions;

  const DiagnosticMenuConfig({
    this.version = 1,
    required this.newProtocolDescription,
    required this.quickControlTree,
    required this.objectCategories,
    this.createMenuActions = const [],
  });

  factory DiagnosticMenuConfig.builtin() {
    return DiagnosticMenuConfig(
      newProtocolDescription: DiagnosticMenuStructure.newProtocolDescription,
      quickControlTree: DiagnosticMenuStructure.quickControlTree,
      objectCategories: DiagnosticMenuStructure.objectCategories,
      createMenuActions: const [
        DiagnosticCreateMenuAction(
          id: 'new_protocol',
          action: DiagnosticMenuAction.newProtocolWizard,
          title: 'Новый протокол',
          subtitle: 'Тип объекта → направление / тип обследования',
          icon: Icons.account_tree_outlined,
          color: Colors.deepPurpleAccent,
        ),
        DiagnosticCreateMenuAction(
          id: 'experience_base',
          action: DiagnosticMenuAction.experienceBase,
          title: 'Опытная база',
          subtitle: 'Справочник марок и записи сообщества',
          icon: Icons.menu_book_outlined,
          color: Color(0xFF4FC3F7),
        ),
        DiagnosticCreateMenuAction(
          id: 'custom_template',
          action: DiagnosticMenuAction.customTemplate,
          title: 'Конструктор протокола',
          subtitle: 'Протокол из пользовательского шаблона',
          icon: Icons.layers_outlined,
          color: Color(0xFF4DB6AC),
        ),
      ],
    );
  }

  factory DiagnosticMenuConfig.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] is Map
        ? Map<String, dynamic>.from(json['payload'] as Map)
        : json;

    final qcRaw = payload['quick_control_tree'];
    final catRaw = payload['object_categories'];
    final actRaw = payload['create_menu_actions'];

    return DiagnosticMenuConfig(
      version: payload['version'] is int
          ? payload['version'] as int
          : int.tryParse(payload['version']?.toString() ?? '1') ?? 1,
      newProtocolDescription: payload['new_protocol_description']?.toString() ??
          DiagnosticMenuStructure.newProtocolDescription,
      quickControlTree: qcRaw is List
          ? qcRaw
              .whereType<Map>()
              .map((m) => _parseQuickNode(Map<String, dynamic>.from(m)))
              .toList()
          : DiagnosticMenuStructure.quickControlTree,
      objectCategories: catRaw is List
          ? catRaw
              .whereType<Map>()
              .map((m) => _parseCategory(Map<String, dynamic>.from(m)))
              .toList()
          : DiagnosticMenuStructure.objectCategories,
      createMenuActions: actRaw is List
          ? actRaw
              .whereType<Map>()
              .map((m) => DiagnosticCreateMenuAction.fromJson(
                    Map<String, dynamic>.from(m),
                  ))
              .toList()
          : DiagnosticMenuConfig.builtin().createMenuActions,
    );
  }

  static DiagnosticMenuAction? actionFromCode(String? code) {
    if (code == null || code.isEmpty) return null;
    switch (code) {
      case 'emergencyInspection':
        return DiagnosticMenuAction.emergencyInspection;
      case 'expressNdtVik':
        return DiagnosticMenuAction.expressNdtVik;
      case 'expressNdtUzt':
        return DiagnosticMenuAction.expressNdtUzt;
      case 'expressNdtUzk':
        return DiagnosticMenuAction.expressNdtUzk;
      case 'expressNdtPvk':
        return DiagnosticMenuAction.expressNdtPvk;
      case 'pressureGi':
        return DiagnosticMenuAction.pressureGi;
      case 'pressurePi':
        return DiagnosticMenuAction.pressurePi;
      case 'pressurePsGpm':
        return DiagnosticMenuAction.pressurePsGpm;
      case 'newProtocolWizard':
        return DiagnosticMenuAction.newProtocolWizard;
      case 'experienceBase':
        return DiagnosticMenuAction.experienceBase;
      case 'customTemplate':
        return DiagnosticMenuAction.customTemplate;
      default:
        return null;
    }
  }

  static IconData iconFromCode(String? code) {
    const map = <String, IconData>{
      'emergency_share_outlined': Icons.emergency_share_outlined,
      'speed_outlined': Icons.speed_outlined,
      'visibility_outlined': Icons.visibility_outlined,
      'straighten_outlined': Icons.straighten_outlined,
      'graphic_eq': Icons.graphic_eq,
      'blur_circular_outlined': Icons.blur_circular_outlined,
      'plumbing_outlined': Icons.plumbing_outlined,
      'water_drop_outlined': Icons.water_drop_outlined,
      'compress_outlined': Icons.compress_outlined,
      'precision_manufacturing_outlined': Icons.precision_manufacturing_outlined,
      'propane_tank_outlined': Icons.propane_tank_outlined,
      'architecture': Icons.architecture,
      'local_fire_department_outlined': Icons.local_fire_department_outlined,
      'build_circle_outlined': Icons.build_circle_outlined,
      'air_outlined': Icons.air_outlined,
      'account_tree_outlined': Icons.account_tree_outlined,
      'menu_book_outlined': Icons.menu_book_outlined,
      'layers_outlined': Icons.layers_outlined,
      'description_outlined': Icons.description_outlined,
    };
    return map[code] ?? Icons.description_outlined;
  }

  static DiagnosticQuickControlNode _parseQuickNode(Map<String, dynamic> json) {
    final childrenRaw = json['children'];
    final children = childrenRaw is List
        ? childrenRaw
            .whereType<Map>()
            .map((c) => _parseQuickNode(Map<String, dynamic>.from(c)))
            .toList()
        : <DiagnosticQuickControlNode>[];

    return DiagnosticQuickControlNode(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      protocolHint: json['protocol_hint']?.toString(),
      action: actionFromCode(json['action']?.toString()),
      icon: iconFromCode(json['icon']?.toString()),
      children: children,
    );
  }

  static DiagnosticObjectCategory _parseCategory(Map<String, dynamic> json) {
    final archRaw = json['archetypes'];
    final archetypes = archRaw is List
        ? archRaw
            .whereType<Map>()
            .map(
              (a) => DiagnosticEquipmentArchetype(
                kind: a['kind']?.toString() ?? '',
                exampleMark: a['example_mark']?.toString() ?? '',
              ),
            )
            .toList()
        : <DiagnosticEquipmentArchetype>[];

    final labelsRaw = json['inspection_type_labels'];
    final labels = labelsRaw is List
        ? labelsRaw.map((e) => e.toString()).toList()
        : <String>[];

    return DiagnosticObjectCategory(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      icon: iconFromCode(json['icon']?.toString()),
      equipmentPreset: json['equipment_preset']?.toString() ?? 'other',
      inspectionTypeLabels: labels,
      archetypes: archetypes,
    );
  }

  List<({DiagnosticObjectCategory category, DiagnosticEquipmentArchetype archetype})>
      allArchetypes() {
    final out =
        <({DiagnosticObjectCategory category, DiagnosticEquipmentArchetype archetype})>[];
    for (final c in objectCategories) {
      for (final a in c.archetypes) {
        out.add((category: c, archetype: a));
      }
    }
    return out;
  }
}
