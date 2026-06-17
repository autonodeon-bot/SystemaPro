/// Шаблон обследования объекта (сервер inspection_object_templates).
class InspectionObjectTemplate {
  final String id;
  final String name;
  final String? description;
  final String categoryCode;
  final String? equipmentPreset;
  final String inspectionDirection;
  final String targetFlow;
  final String? equipmentKind;
  final String? equipmentMark;
  final Map<String, dynamic> defaultData;

  const InspectionObjectTemplate({
    required this.id,
    required this.name,
    this.description,
    required this.categoryCode,
    this.equipmentPreset,
    required this.inspectionDirection,
    this.targetFlow = 'vessel_checklist',
    this.equipmentKind,
    this.equipmentMark,
    this.defaultData = const {},
  });

  factory InspectionObjectTemplate.fromJson(Map<String, dynamic> json) {
    final data = json['default_data'];
    return InspectionObjectTemplate(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      categoryCode: json['category_code']?.toString() ?? '',
      equipmentPreset: json['equipment_preset']?.toString(),
      inspectionDirection: json['inspection_direction']?.toString() ?? '',
      targetFlow: json['target_flow']?.toString() ?? 'vessel_checklist',
      equipmentKind: json['equipment_kind']?.toString(),
      equipmentMark: json['equipment_mark']?.toString(),
      defaultData: data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
    );
  }
}
