class User {
  final String id;
  final String username;
  final String? email;
  final String? fullName;
  final String? role;
  final String? token;

  User({
    required this.id,
    required this.username,
    this.email,
    this.fullName,
    this.role,
    this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      username: json['username'] ?? json['user_name'] ?? '',
      email: json['email'],
      fullName: json['full_name'] ?? json['fullName'],
      role: json['role'],
      token: json['token'] ?? json['access_token'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'full_name': fullName,
      'role': role,
      'token': token,
    };
  }
}
