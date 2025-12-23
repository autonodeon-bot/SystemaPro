class Equipment {
  final String id;
  final String name;
  final String? typeId; // Изменено с int? на String? (UUID)
  final String? typeName; // Название типа оборудования
  final String? typeCode; // Код типа оборудования
  final String? serialNumber;
  final String? location; // Место расположения
  final Map<String, dynamic>? attributes;
  final String? commissioningDate;
  final String? workshopId; // ID цеха
  final String? workshopName; // Название цеха
  final String? workshopCode; // Код цеха
  final String? branchId; // ID филиала
  final String? branchName; // Название филиала
  final String? branchCode; // Код филиала
  final String? enterpriseId; // ID предприятия
  final String? enterpriseName; // Название предприятия
  final String? enterpriseCode; // Код предприятия

  Equipment({
    required this.id,
    required this.name,
    this.typeId,
    this.typeName,
    this.typeCode,
    this.serialNumber,
    this.location,
    this.attributes,
    this.commissioningDate,
    this.workshopId,
    this.workshopName,
    this.workshopCode,
    this.branchId,
    this.branchName,
    this.branchCode,
    this.enterpriseId,
    this.enterpriseName,
    this.enterpriseCode,
  });

  factory Equipment.fromJson(Map<String, dynamic> json) {
    // Безопасный парсинг type_id (может быть String или int)
    String? parseTypeId(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      if (value is int) return value.toString();
      return null;
    }

    // Безопасный парсинг attributes
    Map<String, dynamic>? parseAttributes(dynamic value) {
      if (value == null) return null;
      if (value is Map<String, dynamic>) return value;
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      return null;
    }

    return Equipment(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      typeId: parseTypeId(json['type_id']),
      typeName: json['type_name']?.toString(),
      typeCode: json['type_code']?.toString(),
      serialNumber: json['serial_number']?.toString(),
      location: json['location']?.toString(),
      attributes: parseAttributes(json['attributes']),
      commissioningDate: json['commissioning_date']?.toString(),
      workshopId: json['workshop_id']?.toString(),
      workshopName: json['workshop_name']?.toString(),
      workshopCode: json['workshop_code']?.toString(),
      branchId: json['branch_id']?.toString(),
      branchName: json['branch_name']?.toString(),
      branchCode: json['branch_code']?.toString(),
      enterpriseId: json['enterprise_id']?.toString(),
      enterpriseName: json['enterprise_name']?.toString(),
      enterpriseCode: json['enterprise_code']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type_id': typeId,
      'type_name': typeName,
      'type_code': typeCode,
      'serial_number': serialNumber,
      'location': location,
      'attributes': attributes,
      'commissioning_date': commissioningDate,
      'workshop_id': workshopId,
      'workshop_name': workshopName,
      'workshop_code': workshopCode,
      'branch_id': branchId,
      'branch_name': branchName,
      'branch_code': branchCode,
      'enterprise_id': enterpriseId,
      'enterprise_name': enterpriseName,
      'enterprise_code': enterpriseCode,
    };
  }
}
