import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/user.dart';

class AuthService {
  static const String _prefsKeyUser = 'current_user';
  static const String _prefsKeyToken = 'auth_token';

  // Сохранить пользователя
  Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyUser, json.encode(user.toJson()));
    if (user.token != null) {
      await prefs.setString(_prefsKeyToken, user.token!);
    }
  }

  // Получить текущего пользователя
  Future<User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_prefsKeyUser);
    if (userJson != null) {
      return User.fromJson(json.decode(userJson));
    }
    return null;
  }

  // Получить токен
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyToken);
  }

  // Выход
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyUser);
    await prefs.remove(_prefsKeyToken);
  }

  // Проверить авторизован ли пользователь
  Future<bool> isAuthenticated() async {
    final user = await getCurrentUser();
    final token = await getToken();
    return user != null && token != null;
  }
}












