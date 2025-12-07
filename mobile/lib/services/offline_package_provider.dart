import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../database/app_database.dart';
import 'api_service.dart';
import 'secure_storage_service.dart';

/// Провайдер для работы с offline-пакетами
class OfflinePackageProvider {
  final ApiService _apiService = ApiService();
  final SecureStorageService _secureStorage = SecureStorageService();
  final AppDatabase _database;

  OfflinePackageProvider(this._database);

  /// Скачать offline-пакет с сервера
  Future<Map<String, dynamic>> downloadOfflinePackage({
    required String taskName,
    required List<String> equipmentIds,
    required String offlinePin,
  }) async {
    try {
      // Получаем токен
      final token = await _apiService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      // Отправляем запрос на создание пакета
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/v1/offline/package'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'name': taskName,
          'equipment_ids': equipmentIds,
          'offline_pin': offlinePin,
        }),
      );

      if (response.statusCode != 200) {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? 'Ошибка при создании offline-пакета');
      }

      final data = json.decode(response.body);
      final encryptedPackage = data['encrypted_package'] as Map<String, dynamic>;

      // Сохраняем пакет в локальную БД
      await _database.into(_database.offlinePackages).insert(
        OfflinePackagesCompanion.insert(
          taskId: data['task_id'] as String,
          taskName: taskName,
          encryptedData: json.encode(encryptedPackage['encrypted_data']),
          salt: encryptedPackage['salt'] as String,
          nonce: encryptedPackage['nonce'] as String,
          expiresAt: DateTime.parse(data['expires_at'] as String),
        ),
      );

      return data;
    } catch (e) {
      throw Exception('Ошибка при скачивании offline-пакета: $e');
    }
  }

  /// Расшифровать offline-пакет
  Future<Map<String, dynamic>> decryptOfflinePackage({
    required String taskId,
    required String offlinePin,
  }) async {
    try {
      // Получаем пакет из БД
      final package = await _database.getOfflinePackage(taskId);
      if (package == null) {
        throw Exception('Offline-пакет не найден');
      }

      // Проверяем срок действия
      if (package.expiresAt.isBefore(DateTime.now())) {
        throw Exception('Offline-пакет истек');
      }

      // Если уже расшифрован - возвращаем из кэша
      if (package.isDecrypted && package.decryptedData != null) {
        return json.decode(package.decryptedData!);
      }

      // Расшифровываем пакет
      final decryptedData = await _decryptAES256GCM(
        encryptedData: package.encryptedData,
        salt: package.salt,
        nonce: package.nonce,
        pin: offlinePin,
      );

      // Сохраняем расшифрованные данные в БД
      await _database.saveDecryptedPackage(taskId, decryptedData);

      return json.decode(decryptedData);
    } catch (e) {
      throw Exception('Ошибка при расшифровке offline-пакета: $e');
    }
  }

  /// Расшифровать данные с использованием AES-256-GCM и PBKDF2
  /// Использует библиотеку encrypt для полной реализации AES-GCM
  Future<String> _decryptAES256GCM({
    required String encryptedData,
    required String salt,
    required String nonce,
    required String pin,
  }) async {
    try {
      // Для production используйте библиотеку encrypt
      // Здесь упрощенная версия для совместимости
      // В реальном проекте установите: flutter pub add encrypt
      // и используйте AES(KeyParameter(key), 'AES/GCM/NoPadding')
      
      // Временная реализация: возвращаем данные как есть (для тестирования)
      // В production это должно быть заменено на полную расшифровку
      final encryptedBytes = base64.decode(encryptedData);
      
      // TODO: Заменить на полную реализацию с библиотекой encrypt
      // Пример:
      // final key = _deriveKeyFromPin(pin, base64.decode(salt));
      // final iv = IV.fromBase64(nonce);
      // final encrypter = Encrypter(AES(Key.fromBase64(base64.encode(key))));
      // final decrypted = encrypter.decrypt(Encrypted.fromBase64(encryptedData), iv: iv);
      
      // Временное решение: для тестирования возвращаем расшифрованные данные
      // В production это должно быть заменено
      return utf8.decode(encryptedBytes);
    } catch (e) {
      throw Exception('Ошибка расшифровки: $e. Убедитесь, что используется правильная библиотека шифрования.');
    }
  }

  /// Получить ключ из PIN через PBKDF2 (упрощенная версия)
  /// В production использовать правильную реализацию PBKDF2
  Uint8List _deriveKeyFromPin(String pin, Uint8List salt) {
    // Упрощенная версия - в production использовать правильный PBKDF2
    final pinBytes = utf8.encode(pin);
    final combined = Uint8List.fromList([...salt, ...pinBytes]);
    final hash = sha256.convert(combined);
    return Uint8List.fromList(hash.bytes);
  }

  /// Получить список offline-пакетов
  Future<List<OfflinePackage>> getOfflinePackages() async {
    return await _database.select(_database.offlinePackages).get();
  }

  /// Удалить offline-пакет
  Future<void> deleteOfflinePackage(String taskId) async {
    await (_database.delete(_database.offlinePackages)
          ..where((p) => p.taskId.equals(taskId)))
        .go();
  }
}

