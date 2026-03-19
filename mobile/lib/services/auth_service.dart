import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
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
  static const String _prefsKeyPinHash = 'pin_hash';
  static const String _prefsKeyPinSalt = 'pin_salt';
  static const String _secureKeyPassword = 'stored_password';

  final _secureStorage = const FlutterSecureStorage();
  final _biometricService = BiometricService();
  final _rng = Random.secure();

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

  /// Сохранить логин и пароль для автоматического входа при синхронизации (офлайн→онлайн).
  /// Также сохраняет SHA-256 хеш пароля для офлайн-верификации.
  Future<void> saveCredentials(String username, String password) async {
    if (username.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyUsername, username.trim());
    await _secureStorage.write(key: _secureKeyPassword, value: password);
    await _saveOfflinePasswordHash(password);
  }

  /// Получить сохранённые логин и пароль (для повторного входа при синхронизации).
  Future<({String username, String password})?> getStoredCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_prefsKeyUsername);
    if (username == null || username.isEmpty) return null;
    try {
      final password = await _secureStorage.read(key: _secureKeyPassword);
      if (password == null || password.isEmpty) return null;
      return (username: username, password: password);
    } catch (_) {
      return null;
    }
  }

  /// Есть ли сохранённые учётные данные для авто-входа.
  Future<bool> hasStoredCredentials() async {
    return await getStoredCredentials() != null;
  }

  /// Привязать текущее устройство (сохранить device_id). Вызывать при включении входа по отпечатку.
  Future<void> ensureDeviceBound() async {
    final deviceId = await _biometricService.getDeviceId();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyDeviceId, deviceId);
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

  List<int> _makeSalt([int length = 16]) {
    return List<int>.generate(length, (_) => _rng.nextInt(256));
  }

  String _hashPin(String pin, List<int> salt) {
    final data = <int>[...salt, ...utf8.encode(pin)];
    return base64.encode(sha256.convert(data).bytes);
  }

  Future<bool> hasPin() async {
    try {
      final hash = await _secureStorage.read(key: _prefsKeyPinHash);
      return hash != null && hash.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> setPin(String pin) async {
    final salt = _makeSalt();
    final hash = _hashPin(pin, salt);
    await _secureStorage.write(key: _prefsKeyPinHash, value: hash);
    await _secureStorage.write(
      key: _prefsKeyPinSalt,
      value: base64.encode(salt),
    );
  }

  Future<bool> verifyPin(String pin) async {
    try {
      final hash = await _secureStorage.read(key: _prefsKeyPinHash);
      final saltBase64 = await _secureStorage.read(key: _prefsKeyPinSalt);
      if (hash == null || saltBase64 == null) return false;
      final salt = base64.decode(saltBase64);
      final calc = _hashPin(pin, salt);
      final ok = calc == hash;
      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKeyLastLoginTime, DateTime.now().toIso8601String());
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearPin() async {
    try {
      await _secureStorage.delete(key: _prefsKeyPinHash);
      await _secureStorage.delete(key: _prefsKeyPinSalt);
    } catch (_) {
      // ignore
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
  
  Future<void> _saveOfflinePasswordHash(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    await prefs.setString('offline_password_hash', digest.toString());
  }

  // Проверить пароль локально (для офлайн-авторизации)
  Future<bool> verifyPasswordOffline(String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedHash = prefs.getString('offline_password_hash');
      if (savedHash == null) return false;

      final bytes = utf8.encode(password);
      final digest = sha256.convert(bytes);
      return digest.toString() == savedHash;
    } catch (e) {
      debugPrint('Error verifying offline password: $e');
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

  // Выход (токен и пароль удаляются; пользователь и логин сохраняются для кнопок «Войти офлайн» / PIN)
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Не удаляем _prefsKeyUser и _prefsKeyUsername — чтобы после выхода оставались кнопки «Войти офлайн», «Войти по PIN»
    // await prefs.remove(_prefsKeyUser);
    // await prefs.remove(_prefsKeyUsername);
    // await prefs.remove(_prefsKeyDeviceId);
    // await prefs.remove(_prefsKeyBiometricEnabled);
    // await prefs.remove(_prefsKeyLastLoginTime);

    // Удаляем только токен и пароли — сессия онлайн прекращается
    try {
      await _secureStorage.delete(key: _prefsKeyToken);
      await _secureStorage.delete(key: _prefsKeyPasswordHash);
      await _secureStorage.delete(key: _secureKeyPassword);
      // PIN и биометрию не сбрасываем, чтобы можно было войти локально
      // await _secureStorage.delete(key: _prefsKeyPinHash);
      // await _secureStorage.delete(key: _prefsKeyPinSalt);
    } catch (e) {
      // Игнорируем ошибки при удалении
    }

    await prefs.remove(_prefsKeyToken);
    await prefs.remove(_prefsKeyPasswordHash);
  }
  
  // Аутентификация по биометрии (для офлайн-режима). Возвращает true при успехе.
  Future<bool> authenticateWithBiometric() async {
    try {
      final isBound = await isUserBoundToDevice();
      if (!isBound) {
        return false;
      }
      final biometricEnabled = await isBiometricEnabled();
      if (!biometricEnabled) {
        return false;
      }
      final isAvailable = await _biometricService.isBiometricAvailable();
      if (!isAvailable) {
        return false;
      }

      final authenticated = await _biometricService.authenticate(
        reason: 'Подтвердите вход в приложение',
      );

      if (authenticated) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKeyLastLoginTime, DateTime.now().toIso8601String());
      }
      return authenticated;
    } catch (e) {
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
























