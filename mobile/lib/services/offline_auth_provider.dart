import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'secure_storage_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Провайдер для офлайн-аутентификации с PIN/FaceID
class OfflineAuthProvider extends ChangeNotifier {
  final SecureStorageService _secureStorage = SecureStorageService();
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isAuthenticated = false;
  bool _isCheckingSecurity = false;
  bool _isJailbroken = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isCheckingSecurity => _isCheckingSecurity;
  bool get isJailbroken => _isJailbroken;

  OfflineAuthProvider() {
    _checkSecurity();
  }

  /// Проверка безопасности устройства (jailbreak/root detection)
  Future<void> _checkSecurity() async {
    _isCheckingSecurity = true;
    notifyListeners();

    try {
      // Проверяем на jailbreak/root
      final isJailbroken = await FlutterJailbreakDetection.jailbroken;
      final isDeveloperMode = await FlutterJailbreakDetection.developerMode;

      _isJailbroken = isJailbroken || isDeveloperMode;

      if (_isJailbroken) {
        // На взломанном устройстве - очищаем все данные
        await _secureStorage.clearAllData();
      }
    } catch (e) {
      // Игнорируем ошибки проверки
      _isJailbroken = false;
    } finally {
      _isCheckingSecurity = false;
      notifyListeners();
    }
  }

  /// Аутентификация с PIN
  Future<bool> authenticateWithPin(String pin) async {
    if (_isJailbroken) {
      throw Exception('Устройство взломано. Доступ запрещен.');
    }

    // Проверяем, не заблокирован ли доступ
    final isLocked = await _secureStorage.isPinLocked();
    if (isLocked) {
      final lockedUntil = await _secureStorage.getLockedUntil();
      throw Exception(
        'Доступ заблокирован до ${lockedUntil?.toString() ?? 'неизвестно'}. '
        'Слишком много неудачных попыток.',
      );
    }

    // Проверяем PIN
    final isValid = await _secureStorage.verifyOfflinePin(pin);
    
    if (!isValid) {
      // Увеличиваем счетчик попыток
      final attempts = await _secureStorage.incrementPinAttempts();
      final remainingAttempts = 5 - attempts;

      if (remainingAttempts <= 0) {
        // 5 неудачных попыток - очищаем все данные
        await _secureStorage.clearAllData();
        throw Exception(
          'Превышено количество попыток. Все данные удалены в целях безопасности.',
        );
      }

      throw Exception(
        'Неверный PIN. Осталось попыток: $remainingAttempts',
      );
    }

    // PIN верный - сбрасываем счетчик попыток
    await _secureStorage.resetPinAttempts();
    _isAuthenticated = true;
    notifyListeners();

    return true;
  }

  /// Аутентификация с биометрией (FaceID/TouchID)
  Future<bool> authenticateWithBiometrics() async {
    if (_isJailbroken) {
      throw Exception('Устройство взломано. Доступ запрещен.');
    }

    try {
      // Проверяем, доступна ли биометрия
      final isAvailable = await _localAuth.canCheckBiometrics;
      if (!isAvailable) {
        throw Exception('Биометрическая аутентификация недоступна');
      }

      // Проверяем, какие типы биометрии доступны
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      if (availableBiometrics.isEmpty) {
        throw Exception('Биометрические данные не настроены');
      }

      // Запрашиваем аутентификацию (новый API в local_auth 3.0 - убран параметр options)
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Войдите для доступа к офлайн-данным',
      );

      if (didAuthenticate) {
        _isAuthenticated = true;
        notifyListeners();
        return true;
      }

      return false;
    } catch (e) {
      throw Exception('Ошибка биометрической аутентификации: $e');
    }
  }

  /// Выход из офлайн-режима
  void logout() {
    _isAuthenticated = false;
    notifyListeners();
  }

  /// Проверить, установлен ли офлайн-PIN
  Future<bool> hasOfflinePin() async {
    final pinHash = await _secureStorage.getOfflinePinHash();
    return pinHash != null;
  }

  /// Установить офлайн-PIN (при первой настройке)
  Future<void> setOfflinePin(String pin) async {
    if (pin.length < 6 || pin.length > 8) {
      throw Exception('PIN должен содержать от 6 до 8 цифр');
    }

    // Хешируем PIN
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    final pinHash = digest.toString();

    // Сохраняем хеш
    await _secureStorage.saveOfflinePinHash(pinHash);
  }
}

