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
    String role = 'engineer'; // Значение по умолчанию - НИКОГДА не admin!

    if (json['role'] != null) {
      final rawRole = json['role'].toString().toLowerCase().trim();
      // Проверяем, что роль валидна
      final validRoles = ['admin', 'chief_operator', 'operator', 'engineer'];
      if (validRoles.contains(rawRole)) {
        role = rawRole;
      } else {
        print('⚠️ Неизвестная роль: "$rawRole", устанавливаем engineer');
        role = 'engineer';
      }
    } else {
      print('⚠️ Роль не указана в JSON, устанавливаем engineer по умолчанию');
      role = 'engineer';
    }

    // ДОПОЛНИТЕЛЬНАЯ ЗАЩИТА: если роль все еще пустая или невалидна - принудительно engineer
    if (role.isEmpty ||
        (role != 'admin' &&
            role != 'chief_operator' &&
            role != 'operator' &&
            role != 'engineer')) {
      print(
          '⚠️ КРИТИЧЕСКАЯ ЗАЩИТА: принудительно устанавливаем engineer вместо "$role"');
      role = 'engineer';
    }

    print(
        'User.fromJson: username=${json['username']}, role=$role (финальная)');

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

  String getRoleLabel() {
    switch (role) {
      case 'admin':
        return 'Администратор';
      case 'chief_operator':
        return 'Главный оператор';
      case 'operator':
        return 'Оператор';
      case 'engineer':
        return 'Инженер';
      default:
        return 'Неизвестная роль';
    }
  }
}
