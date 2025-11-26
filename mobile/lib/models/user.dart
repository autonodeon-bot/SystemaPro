class User {
  final String id;
  final String username;
  final String fullName;
  final String? email;
  final String? phone;
  final String role;
  final String? position;
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
    this.qualifications,
    this.certifications,
    this.equipmentTypes,
    this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      username: json['username'] ?? '',
      fullName: json['full_name'] ?? json['fullName'] ?? '',
      email: json['email'],
      phone: json['phone'],
      role: json['role'] ?? 'engineer',
      position: json['position'],
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
      'qualifications': qualifications,
      'certifications': certifications,
      'equipment_types': equipmentTypes,
      'token': token,
    };
  }
}

