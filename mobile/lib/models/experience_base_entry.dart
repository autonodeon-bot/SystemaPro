/// Запись опытной базы (сервер experience_base_entries).
class ExperienceBaseEntry {
  final String id;
  final String categoryCode;
  final String equipmentKind;
  final String equipmentMark;
  final String entryType;
  final String? title;
  final String body;
  final String? equipmentId;
  final String? assignmentId;
  final bool isArchetype;
  final String? createdAt;

  const ExperienceBaseEntry({
    required this.id,
    required this.categoryCode,
    required this.equipmentKind,
    this.equipmentMark = '',
    required this.entryType,
    this.title,
    required this.body,
    this.equipmentId,
    this.assignmentId,
    this.isArchetype = false,
    this.createdAt,
  });

  factory ExperienceBaseEntry.fromJson(Map<String, dynamic> json) {
    return ExperienceBaseEntry(
      id: json['id']?.toString() ?? '',
      categoryCode: json['category_code']?.toString() ?? '',
      equipmentKind: json['equipment_kind']?.toString() ?? '',
      equipmentMark: json['equipment_mark']?.toString() ?? '',
      entryType: json['entry_type']?.toString() ?? 'note',
      title: json['title']?.toString(),
      body: json['body']?.toString() ?? '',
      equipmentId: json['equipment_id']?.toString(),
      assignmentId: json['assignment_id']?.toString(),
      isArchetype: json['is_archetype'] == true,
      createdAt: json['created_at']?.toString(),
    );
  }

  String get entryTypeLabel {
    switch (entryType) {
      case 'recommendation':
        return 'Рекомендация';
      case 'operator_feedback':
        return 'Отзыв эксплуатации';
      default:
        return 'Заметка';
    }
  }

  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    return '$equipmentKind $equipmentMark'.trim();
  }
}
