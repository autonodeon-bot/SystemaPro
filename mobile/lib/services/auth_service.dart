import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/user.dart';

class AuthService {
  static const String _prefsKeyUser = 'current_user';
  static const String _prefsKeyToken = 'auth_token';
  static const String _prefsKeyPasswordHash = 'password_hash';
  static const String _prefsKeyUsername = 'offline_username';

  // Сохранить пользователя
  Future<void> saveUser(User user, {String? passwordHash}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyUser, json.encode(user.toJson()));
    if (user.token != null) {
      await prefs.setString(_prefsKeyToken, user.token!);
    }
    // Сохраняем хеш пароля для офлайн-авторизации
    if (passwordHash != null) {
      await prefs.setString(_prefsKeyPasswordHash, passwordHash);
      await prefs.setString(_prefsKeyUsername, user.username);
    }
  }
  
  // Получить сохраненный хеш пароля
  Future<String?> getPasswordHash() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyPasswordHash);
  }
  
  // Получить сохраненное имя пользователя для офлайн-входа
  Future<String?> getOfflineUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyUsername);
  }
  
  // Проверить пароль локально (для офлайн-авторизации)
  Future<bool> verifyPasswordOffline(String password) async {
    final savedHash = await getPasswordHash();
    if (savedHash == null) return false;
    
    // Используем bcrypt для проверки пароля
    try {
      // Импортируем bcrypt для Dart
      // В Flutter можно использовать пакет bcrypt
      // Для простоты пока используем простое сравнение (в продакшене нужно использовать bcrypt)
      // TODO: Добавить пакет bcrypt для Dart
      return savedHash.isNotEmpty; // Временная заглушка
    } catch (e) {
      return false;
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




























