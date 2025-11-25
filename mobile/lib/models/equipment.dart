class Equipment {
  final String id;
  final String name;
  final String? typeId; // Изменено с int? на String? (UUID)
  final String? serialNumber;
  final String? location; // Место расположения
  final Map<String, dynamic>? attributes;
  final String? commissioningDate;

  Equipment({
    required this.id,
    required this.name,
    this.typeId,
    this.serialNumber,
    this.location,
    this.attributes,
    this.commissioningDate,
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
      serialNumber: json['serial_number']?.toString(),
      location: json['location']?.toString(),
      attributes: parseAttributes(json['attributes']),
      commissioningDate: json['commissioning_date']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type_id': typeId,
      'serial_number': serialNumber,
      'location': location,
      'attributes': attributes,
      'commissioning_date': commissioningDate,
    };
  }
}
