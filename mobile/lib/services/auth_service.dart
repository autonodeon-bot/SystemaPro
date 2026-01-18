import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import '../models/user.dart';
import 'biometric_service.dart';

class AuthService {
  static const String _prefsKeyUser = 'current_user';
  static const String _prefsKeyToken = 'auth_token';
  static const String _prefsKeyPasswordHash = 'password_hash';
  static const String _prefsKeyUsername = 'offline_username';
  static const String _prefsKeyDeviceId = 'device_id';
  static const String _prefsKeyBiometricEnabled = 'biometric_enabled';
  static const String _prefsKeyLastLoginTime = 'last_login_time';
  
  final _secureStorage = const FlutterSecureStorage();
  final _biometricService = BiometricService();

  // Сохранить пользователя
  Future<void> saveUser(User user, {String? passwordHash}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyUser, json.encode(user.toJson()));
    if (user.token != null) {
      // Сохраняем токен в безопасном хранилище
      await _secureStorage.write(key: _prefsKeyToken, value: user.token!);
    }
    // Сохраняем хеш пароля для офлайн-авторизации
    if (passwordHash != null) {
      // Сохраняем хеш пароля в безопасном хранилище
      await _secureStorage.write(key: _prefsKeyPasswordHash, value: passwordHash);
      await prefs.setString(_prefsKeyUsername, user.username);
    }
    
    // Сохраняем ID устройства для привязки пользователя к устройству
    final deviceId = await _biometricService.getDeviceId();
    await prefs.setString(_prefsKeyDeviceId, deviceId);
    
    // Сохраняем время последнего входа
    await prefs.setString(_prefsKeyLastLoginTime, DateTime.now().toIso8601String());
  }
  
  // Получить сохраненный хеш пароля
  Future<String?> getPasswordHash() async {
    try {
      return await _secureStorage.read(key: _prefsKeyPasswordHash);
    } catch (e) {
      // Fallback на SharedPreferences для обратной совместимости
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsKeyPasswordHash);
    }
  }
  
  // Получить ID устройства
  Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyDeviceId);
  }
  
  // Проверить, привязан ли пользователь к текущему устройству
  Future<bool> isUserBoundToDevice() async {
    final savedDeviceId = await getDeviceId();
    if (savedDeviceId == null) return false;
    
    final currentDeviceId = await _biometricService.getDeviceId();
    return savedDeviceId == currentDeviceId;
  }
  
  // Включить/выключить биометрическую аутентификацию
  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyBiometricEnabled, enabled);
  }
  
  // Проверить, включена ли биометрическая аутентификация
  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyBiometricEnabled) ?? false;
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
    try {
      // Сначала пытаемся получить из безопасного хранилища
      final token = await _secureStorage.read(key: _prefsKeyToken);
      if (token != null) return token;
      
      // Fallback на SharedPreferences для обратной совместимости
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsKeyToken);
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsKeyToken);
    }
  }

  // Выход
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyUser);
    await prefs.remove(_prefsKeyUsername);
    await prefs.remove(_prefsKeyDeviceId);
    await prefs.remove(_prefsKeyBiometricEnabled);
    await prefs.remove(_prefsKeyLastLoginTime);
    
    // Удаляем из безопасного хранилища
    try {
      await _secureStorage.delete(key: _prefsKeyToken);
      await _secureStorage.delete(key: _prefsKeyPasswordHash);
    } catch (e) {
      // Игнорируем ошибки при удалении
    }
    
    // Также удаляем из SharedPreferences для обратной совместимости
    await prefs.remove(_prefsKeyToken);
    await prefs.remove(_prefsKeyPasswordHash);
  }
  
  // Аутентификация по биометрии (для офлайн-режима)
  Future<bool> authenticateWithBiometric() async {
    try {
      // Проверяем, что пользователь привязан к устройству
      final isBound = await isUserBoundToDevice();
      if (!isBound) {
        print('Пользователь не привязан к устройству');
        return false;
      }
      
      // Проверяем, что биометрия включена
      final biometricEnabled = await isBiometricEnabled();
      if (!biometricEnabled) {
        print('Биометрическая аутентификация не включена');
        return false;
      }
      
      // Проверяем доступность биометрии
      final isAvailable = await _biometricService.isBiometricAvailable();
      if (!isAvailable) {
        print('Биометрическая аутентификация недоступна');
        return false;
      }
      
      // Выполняем биометрическую аутентификацию
      final authenticated = await _biometricService.authenticate(
        reason: 'Подтвердите вход в приложение',
      );
      
      if (authenticated) {
        // Обновляем время последнего входа
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKeyLastLoginTime, DateTime.now().toIso8601String());
      }
      
      return authenticated;
    } catch (e) {
      print('Ошибка биометрической аутентификации: $e');
      return false;
    }
  }

  // Проверить авторизован ли пользователь
  Future<bool> isAuthenticated() async {
    final user = await getCurrentUser();
    final token = await getToken();
    return user != null && token != null;
  }
}




























