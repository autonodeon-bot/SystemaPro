import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as Path;
import '../models/vessel_checklist.dart';
import '../models/equipment.dart';
import '../models/assignment.dart';
import 'api_service.dart';

/// Сервис для офлайн-режима и синхронизации данных
class SyncService {
  static const String _prefsKeyPendingInspections = 'pending_inspections';
  static const String _prefsKeyLastSync = 'last_sync';
  static const String _prefsKeyOfflineMode = 'offline_mode';
  static const String _prefsKeyOfflineEquipment = 'offline_equipment';
  static const String _prefsKeyOfflineAssignments = 'offline_assignments'; // Версия 3.3.0

  final ApiService _apiService = ApiService();

  /// Сохранить диагностику в локальное хранилище для последующей синхронизации
  Future<void> saveInspectionOffline({
    required String equipmentId,
    required VesselChecklist checklist,
    String? conclusion,
    required String inspectionDate,
    Map<String, String>? documentFiles,
    String? assignmentId, // ID задания (версия 3.3.0)
    List<String>? verificationEquipmentIds, // ID выбранного оборудования для поверок
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingInspections =
          prefs.getStringList(_prefsKeyPendingInspections) ?? [];

      final checklistJson = checklist.toJson();
      // Добавляем информацию о файлах документов (единый формат: docNumber -> {file_path, file_name})
      // Важно: этот формат должен совпадать с тем, как он читается в syncPendingInspections().
      final structuredDocumentFiles = <String, Map<String, dynamic>>{};

      // Также сохраняем системные вложения чек-листа (фото таблички / схема контроля),
      // чтобы они загрузились на сервер при синхронизации и были доступны в вебе/отчетах.
      // Эти ключи НЕ относятся к перечню документов 1..17.
      void addAttachmentIfPresent(String key) {
        final v = checklistJson[key];
        if (v is String && v.trim().isNotEmpty) {
          structuredDocumentFiles[key] = {
            'file_path': v,
            'file_name': Path.basename(v),
          };
        }
      }
      addAttachmentIfPresent('factory_plate_photo');
      addAttachmentIfPresent('control_scheme_image');
      if (documentFiles != null && documentFiles.isNotEmpty) {
        for (final entry in documentFiles.entries) {
          structuredDocumentFiles[entry.key] = {
            'file_path': entry.value,
            'file_name': Path.basename(entry.value),
          };
        }
        // Дублируем в data: иногда полезно для предпросмотра/отладки
        checklistJson['document_files'] = structuredDocumentFiles;
      }

      final inspectionData = {
        'equipment_id': equipmentId,
        'data': checklistJson,
        'conclusion': conclusion,
        'date_performed': inspectionDate,
        'status': 'DRAFT',
        'timestamp': DateTime.now().toIso8601String(),
        // Сохраняем структурированный формат, чтобы синхронизация корректно загрузила файлы
        'document_files': structuredDocumentFiles,
        'assignment_id': assignmentId, // ID задания (версия 3.3.0)
        'verification_equipment_ids': verificationEquipmentIds ?? [], // ID выбранного оборудования для поверок
      };

      pendingInspections.add(json.encode(inspectionData));
      await prefs.setStringList(
          _prefsKeyPendingInspections, pendingInspections);
    } catch (e) {
      throw Exception('Ошибка сохранения в офлайн-режиме: $e');
    }
  }

  /// Получить список ожидающих синхронизации диагностик
  Future<List<Map<String, dynamic>>> getPendingInspections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingInspections =
          prefs.getStringList(_prefsKeyPendingInspections) ?? [];

      return pendingInspections.map((item) {
        return json.decode(item) as Map<String, dynamic>;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Синхронизировать все ожидающие диагностики и загрузить оборудование
  Future<SyncResult> syncPendingInspections() async {
    final result = SyncResult();

    try {
      // Проверка подключения
      final isConnected = await _apiService.checkConnection();
      if (!isConnected) {
        result.error = 'Нет подключения к серверу';
        return result;
      }

      // Загружаем список оборудования с сервера и сохраняем локально
      try {
        final equipmentList = await _apiService.getEquipmentList();
        // Сохраняем оборудование локально для офлайн-режима
        await saveEquipmentOffline(equipmentList);
        result.message = 'Список оборудования обновлен и сохранен локально';
      } catch (e) {
        result.error = 'Ошибка загрузки оборудования: $e';
        // Продолжаем синхронизацию диагностик даже если не удалось загрузить оборудование
      }

      // Загружаем задания инженера и сохраняем локально (для офлайн-режима)
      try {
        final assignments = await _apiService.getAssignments();
        await saveAssignmentsOffline(assignments);

        // Также подтягиваем оборудование по заданиям (MERGE внутри saveEquipmentOffline)
        for (final a in assignments) {
          try {
            final equipment = await _apiService.getAssignmentEquipment(a.id);
            await saveEquipmentOffline([equipment]);
          } catch (_) {
            // Игнорируем ошибки по одному объекту, не роняем всю синхронизацию
          }
        }
      } catch (_) {
        // Игнорируем: задания синхронизируются дополнительно к основному потоку
      }

      final pendingInspections = await getPendingInspections();
      if (pendingInspections.isEmpty) {
        result.success = true;
        if (result.message == null) {
          result.message =
              'Синхронизация завершена. Нет данных для отправки на сервер';
        }
        return result;
      }

      final prefs = await SharedPreferences.getInstance();
      final failedInspections = <String>[];

      for (final inspectionData in pendingInspections) {
        try {
          final checklist = VesselChecklist.fromJson(
              inspectionData['data'] as Map<String, dynamic>);

          DateTime? datePerformed;
          if (inspectionData['date_performed'] != null) {
            try {
              datePerformed =
                  DateTime.parse(inspectionData['date_performed'] as String);
            } catch (e) {
              datePerformed = DateTime.now();
            }
          }

          // Отправляем inspection на сервер
          final submitResult = await _apiService.submitInspection(
            equipmentId: inspectionData['equipment_id'] as String,
            checklist: checklist,
            conclusion: inspectionData['conclusion'] as String?,
            datePerformed: datePerformed,
            assignmentId: inspectionData['assignment_id'] as String?, // Версия 3.3.0
          );

          // После отправки (при наличии связи) — обновляем карточку оборудования данными,
          // которые инженер заполнил/дополнил в "Карте обследования".
          try {
            await _apiService.updateEquipmentFromChecklist(
              equipmentId: inspectionData['equipment_id'] as String,
              checklist: checklist,
            );
          } catch (e) {
            // Не блокируем синхронизацию из-за обновления оборудования
            print('Ошибка обновления данных оборудования: $e');
          }
          
          // Добавляем используемое оборудование для поверок, если оно было выбрано
          final inspectionId = submitResult['id'] as String?;
          final verificationEquipmentIds = inspectionData['verification_equipment_ids'] as List<dynamic>?;
          if (inspectionId != null && verificationEquipmentIds != null && verificationEquipmentIds.isNotEmpty) {
            try {
              final equipmentIds = verificationEquipmentIds
                  .map((id) => id.toString())
                  .where((id) => id.isNotEmpty)
                  .toList();
              if (equipmentIds.isNotEmpty) {
                await _apiService.addEquipmentToInspection(
                  inspectionId,
                  equipmentIds,
                );
              }
            } catch (e) {
              // Не блокируем синхронизацию из-за ошибки добавления оборудования
              print('Ошибка добавления оборудования для поверок: $e');
            }
          }

          // Если есть questionnaire_id, загружаем файлы документов
          String? questionnaireId;
          if (submitResult.containsKey('questionnaire_id') && 
              submitResult['questionnaire_id'] != null) {
            questionnaireId = submitResult['questionnaire_id'] as String;
          }

          // Загружаем файлы документов, если они есть
          final documentFiles =
              inspectionData['document_files'] as Map<String, dynamic>?;
          if (questionnaireId != null && documentFiles != null && documentFiles.isNotEmpty) {
            for (var entry in documentFiles.entries) {
              try {
                String? filePath;
                String? fileName;

                // Поддерживаем оба формата (старый: docNumber -> "path", новый: docNumber -> {file_path, file_name})
                final value = entry.value;
                if (value is String) {
                  filePath = value;
                  fileName = Path.basename(value);
                } else if (value is Map<String, dynamic>) {
                  filePath = value['file_path'] as String?;
                  fileName = value['file_name'] as String?;
                } else if (value is Map) {
                  // На случай, если декодер дал Map<dynamic,dynamic>
                  final m = Map<String, dynamic>.from(value);
                  filePath = m['file_path'] as String?;
                  fileName = m['file_name'] as String?;
                }
                
                if (filePath != null && fileName != null) {
                  await _apiService.uploadDocumentFile(
                    questionnaireId: questionnaireId,
                    documentNumber: entry.key,
                    filePath: filePath,
                    fileName: fileName,
                  );
                }
              } catch (e) {
                // Логируем ошибку, но не прерываем синхронизацию
                print('Ошибка загрузки файла документа ${entry.key}: $e');
              }
            }
          }

          result.syncedCount++;
        } catch (e) {
          failedInspections.add(json.encode(inspectionData));
          result.failedCount++;
        }
      }

      // Сохранить неудачные попытки
      await prefs.setStringList(_prefsKeyPendingInspections, failedInspections);

      // Обновить время последней синхронизации
      await prefs.setString(
          _prefsKeyLastSync, DateTime.now().toIso8601String());

      result.success = true;
      result.message =
          'Синхронизация завершена: ${result.syncedCount} успешно, ${result.failedCount} ошибок';
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

  /// Сохранить список оборудования локально для офлайн-режима
  Future<void> saveEquipmentOffline(List<Equipment> equipmentList) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // MERGE: не перетираем список (иначе при синхронизации по заданиям останется только последний объект)
      final existing = await getOfflineEquipment();
      final merged = <String, Equipment>{};
      for (final e in existing) {
        merged[e.id] = e;
      }
      for (final e in equipmentList) {
        merged[e.id] = e;
      }

      final equipmentJsonList =
          merged.values.map((eq) => json.encode(eq.toJson())).toList();
      await prefs.setStringList(_prefsKeyOfflineEquipment, equipmentJsonList);
    } catch (e) {
      throw Exception('Ошибка сохранения оборудования локально: $e');
    }
  }

  /// Очистить офлайн-данные (при выходе/смене пользователя)
  Future<void> clearOfflineCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyPendingInspections);
    await prefs.remove(_prefsKeyOfflineEquipment);
    await prefs.remove(_prefsKeyOfflineAssignments);
    await prefs.remove(_prefsKeyLastSync);
    await prefs.remove(_prefsKeyOfflineMode);
  }

  /// Получить список оборудования из локального хранилища
  Future<List<Equipment>> getOfflineEquipment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final equipmentJsonList =
          prefs.getStringList(_prefsKeyOfflineEquipment) ?? [];

      return equipmentJsonList.map((item) {
        final jsonData = json.decode(item) as Map<String, dynamic>;
        return Equipment.fromJson(jsonData);
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Сохранить список заданий локально для офлайн-режима (версия 3.3.0)
  Future<void> saveAssignmentsOffline(List<Assignment> assignments) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final assignmentsJsonList =
          assignments.map((a) => json.encode(a.toJson())).toList();
      await prefs.setStringList(_prefsKeyOfflineAssignments, assignmentsJsonList);
    } catch (e) {
      throw Exception('Ошибка сохранения заданий локально: $e');
    }
  }

  /// Получить список заданий из локального хранилища (версия 3.3.0)
  Future<List<Assignment>> getOfflineAssignments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final assignmentsJsonList =
          prefs.getStringList(_prefsKeyOfflineAssignments) ?? [];

      return assignmentsJsonList.map((item) {
        final jsonData = json.decode(item) as Map<String, dynamic>;
        return Assignment.fromJson(jsonData);
      }).toList();
    } catch (e) {
      return [];
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
