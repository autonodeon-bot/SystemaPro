import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Сервис для безопасного хранения данных (refresh-токены, права, PIN)
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Ключи для хранения
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserRights = 'user_rights';
  static const String _keyOfflinePinHash = 'offline_pin_hash';
  static const String _keyOfflinePinAttempts = 'offline_pin_attempts';
  static const String _keyOfflinePinLockedUntil = 'offline_pin_locked_until';

  /// Сохранить refresh-токен
  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _keyRefreshToken, value: token);
  }

  /// Получить refresh-токен
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _keyRefreshToken);
  }

  /// Удалить refresh-токен
  Future<void> deleteRefreshToken() async {
    await _storage.delete(key: _keyRefreshToken);
  }

  /// Сохранить права пользователя (JSON)
  Future<void> saveUserRights(Map<String, dynamic> rights) async {
    final jsonString = json.encode(rights);
    await _storage.write(key: _keyUserRights, value: jsonString);
  }

  /// Получить права пользователя
  Future<Map<String, dynamic>?> getUserRights() async {
    final jsonString = await _storage.read(key: _keyUserRights);
    if (jsonString == null) return null;
    return json.decode(jsonString) as Map<String, dynamic>;
  }

  /// Сохранить хеш офлайн-PIN
  Future<void> saveOfflinePinHash(String pinHash) async {
    await _storage.write(key: _keyOfflinePinHash, value: pinHash);
  }

  /// Получить хеш офлайн-PIN
  Future<String?> getOfflinePinHash() async {
    return await _storage.read(key: _keyOfflinePinHash);
  }

  /// Проверить офлайн-PIN
  Future<bool> verifyOfflinePin(String pin) async {
    final storedHash = await getOfflinePinHash();
    if (storedHash == null) return false;

    // Хешируем введенный PIN
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    final pinHash = digest.toString();

    return pinHash == storedHash;
  }

  /// Увеличить счетчик попыток ввода PIN
  Future<int> incrementPinAttempts() async {
    final attemptsStr = await _storage.read(key: _keyOfflinePinAttempts);
    final attempts = attemptsStr != null ? int.parse(attemptsStr) : 0;
    final newAttempts = attempts + 1;
    await _storage.write(
      key: _keyOfflinePinAttempts,
      value: newAttempts.toString(),
    );

    // Если 5 неудачных попыток - блокируем на 1 час
    if (newAttempts >= 5) {
      final lockUntil = DateTime.now().add(const Duration(hours: 1));
      await _storage.write(
        key: _keyOfflinePinLockedUntil,
        value: lockUntil.toIso8601String(),
      );
    }

    return newAttempts;
  }

  /// Сбросить счетчик попыток PIN
  Future<void> resetPinAttempts() async {
    await _storage.delete(key: _keyOfflinePinAttempts);
    await _storage.delete(key: _keyOfflinePinLockedUntil);
  }

  /// Проверить, заблокирован ли доступ из-за неверных попыток PIN
  Future<bool> isPinLocked() async {
    final lockedUntilStr = await _storage.read(key: _keyOfflinePinLockedUntil);
    if (lockedUntilStr == null) return false;

    final lockedUntil = DateTime.parse(lockedUntilStr);
    if (DateTime.now().isAfter(lockedUntil)) {
      // Блокировка истекла
      await resetPinAttempts();
      return false;
    }

    return true;
  }

  /// Получить время до разблокировки
  Future<DateTime?> getLockedUntil() async {
    final lockedUntilStr = await _storage.read(key: _keyOfflinePinLockedUntil);
    if (lockedUntilStr == null) return null;
    return DateTime.parse(lockedUntilStr);
  }

  /// Очистить все данные (при 5 неудачных попытках PIN)
  Future<void> clearAllData() async {
    await _storage.deleteAll();
  }

  /// Получить количество неудачных попыток
  Future<int> getPinAttempts() async {
    final attemptsStr = await _storage.read(key: _keyOfflinePinAttempts);
    return attemptsStr != null ? int.parse(attemptsStr) : 0;
  }
}

