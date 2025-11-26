import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/equipment.dart';
import '../models/vessel_checklist.dart';
import 'api_service.dart';

/// Сервис для офлайн-режима и синхронизации данных
class SyncService {
  static const String _fileNamePendingInspections = 'pending_inspections.json';
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
  Future<SyncResult> syncPendingInspections() async {
    final result = SyncResult();
    
    try {
      // Проверка подключения
      final isConnected = await _apiService.checkConnection();
      if (!isConnected) {
        result.error = 'Нет подключения к серверу';
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
}

class SyncResult {
  bool success = false;
  int syncedCount = 0;
  int failedCount = 0;
  String? message;
  String? error;
}
