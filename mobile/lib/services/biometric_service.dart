import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

/// Сервис для биометрической аутентификации (отпечаток пальца/PIN)
class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Проверить, доступна ли биометрическая аутентификация
  Future<bool> isBiometricAvailable() async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return isAvailable && isDeviceSupported;
    } catch (e) {
      print('Ошибка проверки биометрии: $e');
      return false;
    }
  }

  /// Получить список доступных типов биометрии
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      print('Ошибка получения типов биометрии: $e');
      return [];
    }
  }

  /// Аутентификация по отпечатку пальца/PIN
  Future<bool> authenticate({
    String reason = 'Подтвердите вход в приложение',
    bool useErrorDialogs = true,
    bool stickyAuth = true,
  }) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return false;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          useErrorDialogs: useErrorDialogs,
          stickyAuth: stickyAuth,
          biometricOnly: false, // Разрешаем использовать PIN/пароль как fallback
        ),
      );

      return didAuthenticate;
    } on PlatformException catch (e) {
      print('Ошибка биометрической аутентификации: $e');
      return false;
    } catch (e) {
      print('Неизвестная ошибка биометрической аутентификации: $e');
      return false;
    }
  }

  /// Получить уникальный ID устройства
  Future<String> getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // Используем Android ID или ID устройства
        return androidInfo.id; // Android ID (уникален для устройства)
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'unknown-ios-device';
      }
      
      return 'unknown-device';
    } catch (e) {
      print('Ошибка получения ID устройства: $e');
      return 'unknown-device';
    }
  }

  /// Получить информацию об устройстве
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final deviceId = await getDeviceId();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return {
          'device_id': deviceId,
          'platform': 'android',
          'manufacturer': androidInfo.manufacturer,
          'model': androidInfo.model,
          'brand': androidInfo.brand,
          'device': androidInfo.device,
          'android_version': androidInfo.version.release,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return {
          'device_id': deviceId,
          'platform': 'ios',
          'name': iosInfo.name,
          'model': iosInfo.model,
          'system_version': iosInfo.systemVersion,
          'identifier_for_vendor': iosInfo.identifierForVendor,
        };
      }
      
      return {
        'device_id': deviceId,
        'platform': 'unknown',
      };
    } catch (e) {
      print('Ошибка получения информации об устройстве: $e');
      return {
        'device_id': await getDeviceId(),
        'platform': 'unknown',
        'error': e.toString(),
      };
    }
  }

  /// Отменить аутентификацию (если она в процессе)
  Future<void> stopAuthentication() async {
    try {
      await _localAuth.stopAuthentication();
    } catch (e) {
      print('Ошибка отмены аутентификации: $e');
    }
  }
}
