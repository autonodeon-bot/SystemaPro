import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/vessel_checklist.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Сервис для офлайн-режима и синхронизации данных
class SyncService {
  static const String _fileNamePendingInspections = 'pending_inspections.json';
  static const String _fileNamePendingReports = 'pending_reports.json';
  static const String _fileNameLastSync = 'last_sync.txt';
  static const String _fileNameOfflineMode = 'offline_mode.txt';
  
  final ApiService _apiService = ApiService();
  
  /// Получить файл для хранения данных
  Future<File> _getDataFile(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$fileName');
  }
  
  /// Сохранить диагностику в локальное хранилище для последующей синхронизации
  Future<void> saveInspectionOffline({
    required String equipmentId,
    required VesselChecklist checklist,
    String? conclusion,
    required String inspectionDate,
  }) async {
    try {
      final file = await _getDataFile(_fileNamePendingInspections);
      List<Map<String, dynamic>> pendingInspections = [];
      
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          pendingInspections = List<Map<String, dynamic>>.from(json.decode(content));
        }
      }
      
      final inspectionData = {
        'equipment_id': equipmentId,
        'data': checklist.toJson(),
        'conclusion': conclusion,
        'date_performed': inspectionDate,
        'status': 'DRAFT',
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      pendingInspections.add(inspectionData);
      await file.writeAsString(json.encode(pendingInspections));
    } catch (e) {
      throw Exception('Ошибка сохранения в офлайн-режиме: $e');
    }
  }
  
  /// Получить список ожидающих синхронизации диагностик
  Future<List<Map<String, dynamic>>> getPendingInspections() async {
    try {
      final file = await _getDataFile(_fileNamePendingInspections);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return List<Map<String, dynamic>>.from(json.decode(content));
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }
  
  /// Синхронизировать все ожидающие диагностики
  /// ВАЖНО: Только для инженеров!
  Future<SyncResult> syncPendingInspections() async {
    final result = SyncResult();
    
    try {
      // Проверка подключения
      final isConnected = await _apiService.checkConnection();
      if (!isConnected) {
        result.error = 'Нет подключения к серверу';
        return result;
      }
      
      // Проверка роли - только инженеры могут синхронизировать
      final authService = AuthService();
      final currentUser = await authService.getCurrentUser();
      if (currentUser == null) {
        result.error = 'Пользователь не авторизован. Требуется вход в систему.';
        return result;
      }
      
      if (currentUser.role != 'engineer') {
        result.error = 'Синхронизация доступна только инженерам. Ваша роль: ${currentUser.role}';
        return result;
      }
      
      final pendingInspections = await getPendingInspections();
      if (pendingInspections.isEmpty) {
        result.success = true;
        result.message = 'Нет данных для синхронизации';
        return result;
      }
      
      final file = await _getDataFile(_fileNamePendingInspections);
      final failedInspections = <Map<String, dynamic>>[];
      
      for (final inspectionData in pendingInspections) {
        try {
          final checklist = VesselChecklist.fromJson(inspectionData['data'] as Map<String, dynamic>);
          
          await _apiService.submitInspection(
            equipmentId: inspectionData['equipment_id'] as String,
            checklist: checklist,
            conclusion: inspectionData['conclusion'] as String?,
            datePerformed: inspectionData['date_performed'] != null 
                ? DateTime.parse(inspectionData['date_performed'] as String)
                : null,
          );
          
          result.syncedCount++;
        } catch (e) {
          failedInspections.add(inspectionData);
          result.failedCount++;
        }
      }
      
      // Сохранить неудачные попытки
      if (failedInspections.isEmpty) {
        await file.delete();
      } else {
        await file.writeAsString(json.encode(failedInspections));
      }
    
      // Обновить время последней синхронизации
      final lastSyncFile = await _getDataFile(_fileNameLastSync);
      await lastSyncFile.writeAsString(DateTime.now().toIso8601String());
      
      result.success = true;
      result.message = 'Синхронизация завершена: ${result.syncedCount} успешно, ${result.failedCount} ошибок';
    } catch (e) {
      result.error = 'Ошибка синхронизации: $e';
    }
    
    return result;
  }
  
  /// Получить время последней синхронизации
  Future<DateTime?> getLastSyncTime() async {
    try {
      final file = await _getDataFile(_fileNameLastSync);
      if (await file.exists()) {
        final lastSyncStr = await file.readAsString();
        if (lastSyncStr.isNotEmpty) {
          return DateTime.parse(lastSyncStr);
        }
      }
    } catch (e) {
      // Игнорировать ошибки
    }
    return null;
  }
  
  /// Очистить все ожидающие диагностики
  Future<void> clearPendingInspections() async {
    final file = await _getDataFile(_fileNamePendingInspections);
    if (await file.exists()) {
      await file.delete();
    }
  }
  
  /// Установить режим офлайн
  Future<void> setOfflineMode(bool enabled) async {
    final file = await _getDataFile(_fileNameOfflineMode);
    await file.writeAsString(enabled.toString());
  }
  
  /// Получить режим офлайн
  Future<bool> isOfflineMode() async {
    try {
      final file = await _getDataFile(_fileNameOfflineMode);
      if (await file.exists()) {
        final content = await file.readAsString();
        return content == 'true';
      }
    } catch (e) {
      // Игнорировать ошибки
    }
    return false;
  }

  /// Сохранить отчет в локальное хранилище для последующей синхронизации
  Future<void> saveReportOffline({
    required String inspectionId,
    required String reportType,
    String? title,
  }) async {
    try {
      final file = await _getDataFile(_fileNamePendingReports);
      List<Map<String, dynamic>> pendingReports = [];
      
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          pendingReports = List<Map<String, dynamic>>.from(json.decode(content));
        }
      }
      
      final reportData = {
        'inspection_id': inspectionId,
        'report_type': reportType,
        'title': title ?? 'Отчет по диагностике',
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      pendingReports.add(reportData);
      await file.writeAsString(json.encode(pendingReports));
    } catch (e) {
      throw Exception('Ошибка сохранения отчета в офлайн-режиме: $e');
    }
  }

  /// Получить список ожидающих синхронизации отчетов
  Future<List<Map<String, dynamic>>> getPendingReports() async {
    try {
      final file = await _getDataFile(_fileNamePendingReports);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return List<Map<String, dynamic>>.from(json.decode(content));
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Синхронизировать все ожидающие отчеты
  Future<SyncResult> syncPendingReports() async {
    final result = SyncResult();
    
    try {
      // Проверка подключения
      final isConnected = await _apiService.checkConnection();
      if (!isConnected) {
        result.error = 'Нет подключения к серверу';
        return result;
      }
      
      final pendingReports = await getPendingReports();
      if (pendingReports.isEmpty) {
        result.success = true;
        result.message = 'Нет отчетов для синхронизации';
        return result;
      }
      
      final file = await _getDataFile(_fileNamePendingReports);
      final failedReports = <Map<String, dynamic>>[];
      
      for (final reportData in pendingReports) {
        try {
          await _apiService.createReport(
            inspectionId: reportData['inspection_id'] as String,
            reportType: reportData['report_type'] as String,
            title: reportData['title'] as String?,
          );
          
          result.syncedCount++;
        } catch (e) {
          failedReports.add(reportData);
          result.failedCount++;
        }
      }
      
      // Сохранить неудачные попытки
      if (failedReports.isEmpty) {
        await file.delete();
      } else {
        await file.writeAsString(json.encode(failedReports));
      }
    
      // Обновить время последней синхронизации
      final lastSyncFile = await _getDataFile(_fileNameLastSync);
      await lastSyncFile.writeAsString(DateTime.now().toIso8601String());
      
      result.success = true;
      result.message = 'Синхронизация отчетов завершена: ${result.syncedCount} успешно, ${result.failedCount} ошибок';
    } catch (e) {
      result.error = 'Ошибка синхронизации отчетов: $e';
    }
    
    return result;
  }

  /// Очистить все ожидающие отчеты
  Future<void> clearPendingReports() async {
    final file = await _getDataFile(_fileNamePendingReports);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static const String _fileNamePendingQuestionnaires = 'pending_questionnaires.json';

  /// Сохранить опросный лист в локальное хранилище для последующей синхронизации
  Future<void> saveQuestionnaireOffline(
    dynamic questionnaire,
    Map<String, String> photoPaths,
  ) async {
    try {
      final file = await _getDataFile(_fileNamePendingQuestionnaires);
      List<Map<String, dynamic>> pendingQuestionnaires = [];
      
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          pendingQuestionnaires = List<Map<String, dynamic>>.from(json.decode(content));
        }
      }
      
      final questionnaireData = {
        'equipment_id': questionnaire.equipmentId,
        'equipment_inventory_number': questionnaire.equipmentInventoryNumber,
        'equipment_name': questionnaire.equipmentName,
        'inspection_date': questionnaire.inspectionDate,
        'inspector_name': questionnaire.inspectorName,
        'inspector_position': questionnaire.inspectorPosition,
        'questionnaire_data': questionnaire.toJson(),
        'photo_paths': photoPaths,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      pendingQuestionnaires.add(questionnaireData);
      await file.writeAsString(json.encode(pendingQuestionnaires));
    } catch (e) {
      throw Exception('Ошибка сохранения опросного листа в офлайн-режиме: $e');
    }
  }

  /// Получить список ожидающих синхронизации опросных листов
  Future<List<Map<String, dynamic>>> getPendingQuestionnaires() async {
    try {
      final file = await _getDataFile(_fileNamePendingQuestionnaires);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return List<Map<String, dynamic>>.from(json.decode(content));
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Синхронизировать все ожидающие опросные листы
  Future<SyncResult> syncPendingQuestionnaires() async {
    final result = SyncResult();
    
    try {
      // Проверка подключения
      final isConnected = await _apiService.checkConnection();
      if (!isConnected) {
        result.error = 'Нет подключения к серверу';
        return result;
      }
      
      final pendingQuestionnaires = await getPendingQuestionnaires();
      if (pendingQuestionnaires.isEmpty) {
        result.success = true;
        result.message = 'Нет опросных листов для синхронизации';
        return result;
      }
      
      final file = await _getDataFile(_fileNamePendingQuestionnaires);
      final failedQuestionnaires = <Map<String, dynamic>>[];
      
      for (final questionnaireData in pendingQuestionnaires) {
        try {
          // Восстанавливаем объект Questionnaire из JSON
          // Здесь нужно будет создать метод fromJson в модели Questionnaire
          final photoPaths = Map<String, String>.from(questionnaireData['photo_paths'] ?? {});
          
          // Отправляем на сервер
          await _apiService.submitQuestionnaire(
            questionnaireData,
            photoPaths,
          );
          
          result.syncedCount++;
        } catch (e) {
          failedQuestionnaires.add(questionnaireData);
          result.failedCount++;
        }
      }
      
      // Сохранить неудачные попытки
      if (failedQuestionnaires.isEmpty) {
        await file.delete();
      } else {
        await file.writeAsString(json.encode(failedQuestionnaires));
      }
    
      // Обновить время последней синхронизации
      final lastSyncFile = await _getDataFile(_fileNameLastSync);
      await lastSyncFile.writeAsString(DateTime.now().toIso8601String());
      
      result.success = true;
      result.message = 'Синхронизация опросных листов завершена: ${result.syncedCount} успешно, ${result.failedCount} ошибок';
    } catch (e) {
      result.error = 'Ошибка синхронизации опросных листов: $e';
    }
    
    return result;
  }

  /// Очистить все ожидающие опросные листы
  Future<void> clearPendingQuestionnaires() async {
    final file = await _getDataFile(_fileNamePendingQuestionnaires);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class SyncResult {
  bool success = false;
  int syncedCount = 0;
  int failedCount = 0;
  String? message;
  String? error;
}
