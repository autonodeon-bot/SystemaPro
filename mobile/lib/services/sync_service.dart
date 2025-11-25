import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences';
import '../models/equipment.dart';
import '../models/vessel_checklist.dart';
import 'api_service.dart';

/// Сервис для офлайн-режима и синхронизации данных
class SyncService {
  static const String _prefsKeyPendingInspections = 'pending_inspections';
  static const String _prefsKeyLastSync = 'last_sync';
  static const String _prefsKeyOfflineMode = 'offline_mode';
  
  final ApiService _apiService = ApiService();
  
  /// Сохранить диагностику в локальное хранилище для последующей синхронизации
  Future<void> saveInspectionOffline({
    required String equipmentId,
    required VesselChecklist checklist,
    String? conclusion,
    required String inspectionDate,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingInspections = prefs.getStringList(_prefsKeyPendingInspections) ?? [];
      
      final inspectionData = {
        'equipment_id': equipmentId,
        'data': checklist.toJson(),
        'conclusion': conclusion,
        'date_performed': inspectionDate,
        'status': 'DRAFT',
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      pendingInspections.add(json.encode(inspectionData));
      await prefs.setStringList(_prefsKeyPendingInspections, pendingInspections);
    } catch (e) {
      throw Exception('Ошибка сохранения в офлайн-режиме: $e');
    }
  }
  
  /// Получить список ожидающих синхронизации диагностик
  Future<List<Map<String, dynamic>>> getPendingInspections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingInspections = prefs.getStringList(_prefsKeyPendingInspections) ?? [];
      
      return pendingInspections.map((item) {
        return json.decode(item) as Map<String, dynamic>;
      }).toList();
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
      
      final prefs = await SharedPreferences.getInstance();
      final failedInspections = <String>[];
      
      for (final inspectionData in pendingInspections) {
        try {
          final checklist = VesselChecklist.fromJson(inspectionData['data'] as Map<String, dynamic>);
          
          await _apiService.submitInspection(
            equipmentId: inspectionData['equipment_id'] as String,
            checklist: checklist,
            conclusion: inspectionData['conclusion'] as String?,
            inspectionDate: inspectionData['date_performed'] as String,
          );
          
          result.syncedCount++;
        } catch (e) {
          failedInspections.add(json.encode(inspectionData));
          result.failedCount++;
        }
      }
      
      // Сохранить неудачные попытки
      await prefs.setStringList(_prefsKeyPendingInspections, failedInspections);
      
      // Обновить время последней синхронизации
      await prefs.setString(_prefsKeyLastSync, DateTime.now().toIso8601String());
      
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
      final prefs = await SharedPreferences.getInstance();
      final lastSyncStr = prefs.getString(_prefsKeyLastSync);
      if (lastSyncStr != null) {
        return DateTime.parse(lastSyncStr);
      }
    } catch (e) {
      // Игнорировать ошибки
    }
    return null;
  }
  
  /// Очистить все ожидающие диагностики
  Future<void> clearPendingInspections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyPendingInspections);
  }
  
  /// Установить режим офлайн
  Future<void> setOfflineMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyOfflineMode, enabled);
  }
  
  /// Получить режим офлайн
  Future<bool> isOfflineMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyOfflineMode) ?? false;
  }
}

class SyncResult {
  bool success = false;
  int syncedCount = 0;
  int failedCount = 0;
  String? message;
  String? error;
}



