import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../database/app_database.dart';
import 'api_service.dart';
import 'secure_storage_service.dart';
import 'auth_service.dart';

/// Провайдер для синхронизации данных с сервером
class SyncProvider {
  final ApiService _apiService = ApiService();
  final SecureStorageService _secureStorage = SecureStorageService();
  final AppDatabase _database;

  SyncProvider(this._database);

  /// Синхронизировать все несинхронизированные инспекции
  /// ВАЖНО: Только для инженеров!
  Future<SyncResult> syncInspections({required String offlinePin}) async {
    final result = SyncResult();

    try {
      // Проверяем подключение
      final isConnected = await _apiService.checkConnection();
      if (!isConnected) {
        result.error = 'Нет подключения к серверу';
        return result;
      }

      // Получаем текущего пользователя и проверяем роль
      final authService = AuthService();
      final currentUser = await authService.getCurrentUser();
      if (currentUser == null) {
        result.error = 'Пользователь не авторизован. Требуется вход в систему.';
        return result;
      }
      
      // КРИТИЧНО: Только инженеры могут синхронизировать
      if (currentUser.role != 'engineer') {
        result.error = 'Синхронизация доступна только инженерам. Ваша роль: ${currentUser.role}';
        return result;
      }

      // Получаем несинхронизированные инспекции
      final unsyncedInspections = await _database.getUnsyncedInspections();
      if (unsyncedInspections.isEmpty) {
        result.success = true;
        result.message = 'Нет данных для синхронизации';
        return result;
      }

      // Получаем токен
      final token = await _apiService.getToken();
      if (token == null) {
        result.error = 'Токен авторизации не найден. Требуется повторный вход.';
        return result;
      }

      // Формируем список инспекций для синхронизации
      final inspectionsData = unsyncedInspections.map((insp) {
        return {
          'client_id': insp.clientId,
          'equipment_id': insp.equipmentId,
          'data': json.decode(insp.data),
          'conclusion': insp.conclusion,
          'date_performed': insp.datePerformed?.toIso8601String(),
          'status': insp.status,
          'offline_task_id': insp.offlineTaskId,
        };
      }).toList();

      // Отправляем на сервер
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/v1/offline/sync'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'inspections': inspectionsData,
          'offline_pin': offlinePin,
        }),
      );

      if (response.statusCode != 200) {
        final errorData = json.decode(response.body);
        result.error = errorData['detail'] ?? 'Ошибка при синхронизации';
        return result;
      }

      final syncData = json.decode(response.body);
      final syncedIds = List<String>.from(syncData['synced_ids'] ?? []);
      final failedClientIds = List<String>.from(syncData['failed_client_ids'] ?? []);

      // Обновляем статус синхронизированных инспекций
      for (final inspection in unsyncedInspections) {
        if (syncedIds.contains(inspection.serverId)) {
          await _database.markInspectionAsSynced(
            inspection.clientId,
            inspection.serverId ?? inspection.clientId,
            DateTime.now(),
          );
          result.syncedCount++;
        } else if (failedClientIds.contains(inspection.clientId)) {
          result.failedCount++;
        }
      }

      result.success = true;
      result.message =
          'Синхронизировано: ${result.syncedCount}, ошибок: ${result.failedCount}';

      return result;
    } catch (e) {
      result.error = 'Ошибка синхронизации: $e';
      return result;
    }
  }

  /// Синхронизировать файлы (фото) для инспекции
  Future<void> syncInspectionFiles(String inspectionClientId) async {
    try {
      // Получаем несинхронизированные файлы
      final unsyncedFiles = await _database.getUnsyncedFiles(inspectionClientId);
      if (unsyncedFiles.isEmpty) return;

      // Получаем токен
      final token = await _apiService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      // Загружаем каждый файл на сервер через MinIO presigned URL
      for (final file in unsyncedFiles) {
        try {
          // Получаем presigned URL для загрузки
          final presignedUrl = await _getPresignedUploadUrl(
            fileName: file.fileName,
            mimeType: file.mimeType,
            token: token,
          );

          // Загружаем файл
          final fileData = await File(file.filePath).readAsBytes();
          final uploadResponse = await http.put(
            Uri.parse(presignedUrl),
            headers: {
              'Content-Type': file.mimeType,
            },
            body: fileData,
          );

          if (uploadResponse.statusCode == 200) {
            // Получаем URL файла на сервере
            final serverUrl = presignedUrl.split('?').first;
            await _database.markFileAsSynced(file.id, serverUrl);
          }
        } catch (e) {
          // Продолжаем с другими файлами при ошибке
          print('Ошибка при загрузке файла ${file.fileName}: $e');
        }
      }
    } catch (e) {
      throw Exception('Ошибка при синхронизации файлов: $e');
    }
  }

  /// Получить presigned URL для загрузки файла в MinIO
  Future<String> _getPresignedUploadUrl({
    required String fileName,
    required String mimeType,
    required String token,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/api/files/presigned-url'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'file_name': fileName,
        'content_type': mimeType,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Не удалось получить presigned URL');
    }

    final data = json.decode(response.body);
    return data['url'] as String;
  }
}

class SyncResult {
  bool success = false;
  int syncedCount = 0;
  int failedCount = 0;
  String? message;
  String? error;
}

