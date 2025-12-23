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
  });

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
          ? DateTime.parse(json['due_date'] as String)
          : null,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      enterpriseId: json['enterprise_id'] as String?,
      enterpriseName: json['enterprise_name'] as String?,
      branchId: json['branch_id'] as String?,
      branchName: json['branch_name'] as String?,
      workshopId: json['workshop_id'] as String?,
      workshopName: json['workshop_name'] as String?,
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
      default:
        return assignmentType;
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
        return status;
    }
  }
}











