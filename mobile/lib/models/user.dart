class User {
  final String id;
  final String username;
  final String fullName;
  final String? email;
  final String? phone;
  final String role;
  final String? position;
  final String? engineerId;
  final Map<String, dynamic>? qualifications;
  final List<String>? certifications;
  final List<String>? equipmentTypes;
  final String? token;

  User({
    required this.id,
    required this.username,
    required this.fullName,
    this.email,
    this.phone,
    required this.role,
    this.position,
    this.engineerId,
    this.qualifications,
    this.certifications,
    this.equipmentTypes,
    this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // Явно извлекаем роль и проверяем её
    String role = 'engineer'; // Значение по умолчанию
    if (json['role'] != null) {
      role = json['role'].toString().toLowerCase();
    }
    // Проверяем, что роль валидна
    final validRoles = ['admin', 'chief_operator', 'operator', 'engineer'];
    if (!validRoles.contains(role)) {
      print('⚠️ Неизвестная роль: $role, устанавливаем engineer');
      role = 'engineer';
    }
    print('User.fromJson: username=${json['username']}, role=$role');
    
    return User(
      id: json['id']?.toString() ?? '',
      username: json['username'] ?? '',
      fullName: json['full_name'] ?? json['fullName'] ?? '',
      email: json['email'],
      phone: json['phone'],
      role: role,
      position: json['position'],
      engineerId: json['engineer_id']?.toString(),
      qualifications: json['qualifications'] is Map
          ? Map<String, dynamic>.from(json['qualifications'])
          : null,
      certifications: json['certifications'] is List
          ? List<String>.from(json['certifications'])
          : null,
      equipmentTypes: json['equipment_types'] is List
          ? List<String>.from(json['equipment_types'])
          : null,
      token: json['token'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'role': role,
      'position': position,
      'engineer_id': engineerId,
      'qualifications': qualifications,
      'certifications': certifications,
      'equipment_types': equipmentTypes,
      'token': token,
    };
  }
}








