class Assignment {
  final String id;
  final String equipmentId;
  final String equipmentCode;
  final String equipmentName;
  final String assignmentType; // 'DIAGNOSTICS', 'EXPERTISE', 'INSPECTION'
  final String? assignedBy;
  final String assignedTo;
  final String? assignedToName;
  final String status; // 'PENDING', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'
  final String priority; // 'LOW', 'NORMAL', 'HIGH', 'URGENT'
  final DateTime? dueDate;
  final String? description;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final String? enterpriseId;
  final String? enterpriseName;
  final String? branchId;
  final String? branchName;
  final String? workshopId;
  final String? workshopName;
  final String? opoId;
  final String? opoName;
  final String? opoCode;
  /// Обязательный шаблон протокола (id в конструкторе веба).
  final String? protocolTemplateId;
  final String? protocolTemplateName;
  /// Форма ТО из каталога (to-1, to-13, …).
  final String? reportFormId;
  final String? reportFormTitle;
  final String? contractNumber;
  final String? contractDate;
  final String? workPeriodFrom;
  final String? workPeriodTo;
  final String? workBasis;
  final String? techCardNumber;
  final String? techCardFileName;
  final bool hasTechCardFile;

  Assignment({
    required this.id,
    required this.equipmentId,
    required this.equipmentCode,
    required this.equipmentName,
    required this.assignmentType,
    this.assignedBy,
    required this.assignedTo,
    this.assignedToName,
    required this.status,
    required this.priority,
    this.dueDate,
    this.description,
    required this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.enterpriseId,
    this.enterpriseName,
    this.branchId,
    this.branchName,
    this.workshopId,
    this.workshopName,
    this.opoId,
    this.opoName,
    this.opoCode,
    this.protocolTemplateId,
    this.protocolTemplateName,
    this.reportFormId,
    this.reportFormTitle,
    this.contractNumber,
    this.contractDate,
    this.workPeriodFrom,
    this.workPeriodTo,
    this.workBasis,
    this.techCardNumber,
    this.techCardFileName,
    this.hasTechCardFile = false,
  });

  static DateTime? _parseDateTimeSafe(dynamic value, {DateTime? fallback}) {
    if (value == null) return fallback;
    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') {
      return fallback;
    }
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return fallback;
    }
  }

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id'] as String,
      equipmentId: json['equipment_id'] as String,
      equipmentCode: json['equipment_code'] as String? ?? '',
      equipmentName: json['equipment_name'] as String? ?? '',
      assignmentType: json['assignment_type'] as String,
      assignedBy: json['assigned_by'] as String?,
      assignedTo: json['assigned_to'] as String,
      assignedToName: json['assigned_to_name'] as String?,
      status: json['status'] as String,
      priority: json['priority'] as String,
      dueDate: json['due_date'] != null
          ? _parseDateTimeSafe(json['due_date'], fallback: null)
          : null,
      description: json['description'] as String?,
      createdAt: _parseDateTimeSafe(json['created_at'], fallback: DateTime.now()) ?? DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? _parseDateTimeSafe(json['updated_at'], fallback: null)
          : null,
      completedAt: json['completed_at'] != null
          ? _parseDateTimeSafe(json['completed_at'], fallback: null)
          : null,
      enterpriseId: json['enterprise_id'] as String?,
      enterpriseName: json['enterprise_name'] as String?,
      branchId: json['branch_id'] as String?,
      branchName: json['branch_name'] as String?,
      workshopId: json['workshop_id'] as String?,
      workshopName: json['workshop_name'] as String?,
      opoId: json['opo_id'] as String?,
      opoName: json['opo_name'] as String?,
      opoCode: json['opo_code'] as String?,
      protocolTemplateId: json['protocol_template_id'] as String?,
      protocolTemplateName: json['protocol_template_name'] as String?,
      reportFormId: json['report_form_id'] as String?,
      reportFormTitle: json['report_form_title'] as String?,
      contractNumber: json['contract_number'] as String?,
      contractDate: json['contract_date'] as String?,
      workPeriodFrom: json['work_period_from'] as String?,
      workPeriodTo: json['work_period_to'] as String?,
      workBasis: json['work_basis'] as String?,
      techCardNumber: json['tech_card_number'] as String?,
      techCardFileName: json['tech_card_file_name'] as String?,
      hasTechCardFile: json['has_tech_card_file'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'equipment_id': equipmentId,
      'equipment_code': equipmentCode,
      'equipment_name': equipmentName,
      'assignment_type': assignmentType,
      'assigned_by': assignedBy,
      'assigned_to': assignedTo,
      'assigned_to_name': assignedToName,
      'status': status,
      'priority': priority,
      'due_date': dueDate?.toIso8601String(),
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'enterprise_id': enterpriseId,
      'enterprise_name': enterpriseName,
      'branch_id': branchId,
      'branch_name': branchName,
      'workshop_id': workshopId,
      'workshop_name': workshopName,
      'opo_id': opoId,
      'opo_name': opoName,
      'opo_code': opoCode,
      'protocol_template_id': protocolTemplateId,
      'protocol_template_name': protocolTemplateName,
      'report_form_id': reportFormId,
      'report_form_title': reportFormTitle,
      'contract_number': contractNumber,
      'contract_date': contractDate,
      'work_period_from': workPeriodFrom,
      'work_period_to': workPeriodTo,
      'work_basis': workBasis,
      'tech_card_number': techCardNumber,
      'tech_card_file_name': techCardFileName,
      'has_tech_card_file': hasTechCardFile,
    };
  }

  String get typeLabel {
    switch (assignmentType) {
      case 'DIAGNOSTICS':
        return 'Диагностика';
      case 'EXPERTISE':
        return 'Экспертиза ПБ';
      case 'INSPECTION':
        return 'Обследование';
      case 'CHTO':
        return 'ЧТО';
      case 'PTO':
        return 'ПТО';
      case 'NVO':
        return 'НВО';
      case 'NVO_GI':
        return 'НВО и ГИ';
      default:
        return 'Прочее';
    }
  }

  String get statusLabel {
    switch (status) {
      case 'PENDING':
        return 'Ожидает';
      case 'IN_PROGRESS':
        return 'В работе';
      case 'COMPLETED':
        return 'Завершено';
      case 'CANCELLED':
        return 'Отменено';
      default:
        return 'Неизвестно';
    }
  }
}











