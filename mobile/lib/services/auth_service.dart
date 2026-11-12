import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import '../models/user.dart';
import 'biometric_service.dart';

// Run the deliberately slow KDF outside the UI isolate.
Future<List<int>> _deriveOfflineKey((String, List<int>) input) async {
  final key = await cryptography.Pbkdf2(
    macAlgorithm: cryptography.Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  ).deriveKey(secretKey: cryptography.SecretKey(utf8.encode(input.$1)), nonce: input.$2);
  return key.extractBytes();
}

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
  static const String _prefsKeyOfflineSession = 'offline_session_active';
  static const String _secureKeyPassword = 'stored_password';
  static const String _secureOfflineVerifier = 'offline_verifier_v1';

  final _secureStorage = const FlutterSecureStorage();
  final _biometricService = BiometricService();
  final _rng = Random.secure();

  /// Сессия без JWT (офлайн, PIN, биометрия) — доступ к экранам без API.
  Future<void> activateOfflineSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyOfflineSession, true);
  }

  Future<void> deactivateOfflineSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyOfflineSession);
  }

  Future<bool> hasOfflineSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyOfflineSession) ?? false;
  }

  // Сохранить пользователя
  Future<void> saveUser(User user) async {
    await deactivateOfflineSession();
    final prefs = await SharedPreferences.getInstance();
    await _clearLegacyPasswordHashes();
    // Never carry an offline verifier across online accounts or password changes.
    await _secureStorage.delete(key: _secureOfflineVerifier);
    await prefs.setString(_prefsKeyUser, json.encode(user.toJson()));
    if (user.token != null) {
      // Сохраняем токен в безопасном хранилище
      await _secureStorage.write(key: _prefsKeyToken, value: user.token!);
    }
    await prefs.setString(_prefsKeyUsername, user.username);
    
    // Сохраняем ID устройства для привязки пользователя к устройству
    final deviceId = await _biometricService.getDeviceId();
    await prefs.setString(_prefsKeyDeviceId, deviceId);
    
    // Сохраняем время последнего входа
    await prefs.setString(_prefsKeyLastLoginTime, DateTime.now().toIso8601String());
  }

  /// Сохранить логин и пароль для автоматического входа при синхронизации (офлайн→онлайн).
  /// Офлайн-проверка: PBKDF2 с солью, только в защищённом хранилище.
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

  Future<void> _clearLegacyPasswordHashes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_password_hash');
    await prefs.remove(_prefsKeyPasswordHash);
    await _secureStorage.delete(key: _prefsKeyPasswordHash);
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
    await _clearLegacyPasswordHashes();
    final prefs = await SharedPreferences.getInstance();
    final salt = _makeSalt();
    final key = await compute(_deriveOfflineKey, (password, salt));
    await _secureStorage.write(key: _secureOfflineVerifier, value: json.encode({
      'version': 1,
      'username': prefs.getString(_prefsKeyUsername),
      'salt': base64.encode(salt),
      'hash': base64.encode(key),
    }));
  }

  // Проверить пароль локально (для офлайн-авторизации)
  Future<bool> verifyPasswordOffline(String password) async {
    try {
      await _clearLegacyPasswordHashes();
      final prefs = await SharedPreferences.getInstance();
      final raw = await _secureStorage.read(key: _secureOfflineVerifier);
      // Never promote an untrusted legacy SHA-256 verifier. Sign in online once.
      if (raw == null) return false;
      final data = json.decode(raw) as Map<String, dynamic>;
      if (data['version'] != 1 || data['username'] != prefs.getString(_prefsKeyUsername)) return false;
      final salt = base64.decode(data['salt'] as String);
      final expected = base64.decode(data['hash'] as String);
      if (salt.length != 16 || expected.length != 32) return false;
      final actual = await compute(_deriveOfflineKey, (password, salt));
      var difference = 0;
      for (var i = 0; i < expected.length; i++) {
        difference |= expected[i] ^ actual[i];
      }
      return difference == 0;
    } catch (e) {
      debugPrint('Error verifying offline password: $e');
      return false;
    }
  }

  // Получить текущего пользователя
  Future<User?> getCurrentUser() async {
    await _clearLegacyPasswordHashes();
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
    await _clearLegacyPasswordHashes();
    await _secureStorage.delete(key: _secureOfflineVerifier);
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
    await prefs.remove(_prefsKeyOfflineSession);
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

  // Проверить авторизован ли пользователь (онлайн JWT или офлайн-сессия)
  Future<bool> isAuthenticated() async {
    final user = await getCurrentUser();
    if (user == null) return false;
    final token = await getToken();
    if (token != null && token.isNotEmpty) return true;
    return hasOfflineSession();
  }
}
























