import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as Path;
import '../models/vessel_checklist.dart';
import '../models/compressor_checklist.dart';
import '../models/equipment.dart';
import '../models/assignment.dart';
import 'api_service.dart';

/// Сервис для офлайн-режима и синхронизации данных
class SyncService {
  static const String _prefsKeyPendingInspections = 'pending_inspections';
  static const String _prefsKeyPendingOpoSurveys = 'pending_opo_surveys';
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
    String status = 'DRAFT', // DRAFT / SIGNED
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
        // Статус выставляется UI (вариант Б):
        // - "Сохранить" -> DRAFT
        // - "Подписать/Завершить" -> SIGNED
        'status': status,
        'timestamp': DateTime.now().toIso8601String(),
        // Сохраняем структурированный формат, чтобы синхронизация корректно загрузила файлы
        'document_files': structuredDocumentFiles,
        'assignment_id': assignmentId, // ID задания (версия 3.3.0)
        'verification_equipment_ids': verificationEquipmentIds ?? [], // ID выбранного оборудования для поверок
      };

      // Перезаписываем предыдущую локальную версию для того же оборудования/задания,
      // чтобы при повторном открытии формы подтягивались заполненные данные,
      // и чтобы не было десятков дубликатов в очереди синхронизации.
      final filtered = <String>[];
      for (final item in pendingInspections) {
        try {
          final decoded = json.decode(item) as Map<String, dynamic>;
          final sameEquipment = decoded['equipment_id']?.toString() == equipmentId;
          final sameAssignment =
              (decoded['assignment_id']?.toString() ?? '') == (assignmentId ?? '');
          if (sameEquipment && sameAssignment) {
            continue;
          }
          filtered.add(item);
        } catch (_) {
          filtered.add(item);
        }
      }

      filtered.add(json.encode(inspectionData));
      await prefs.setStringList(_prefsKeyPendingInspections, filtered);
    } catch (e) {
      throw Exception('Ошибка сохранения в офлайн-режиме: $e');
    }
  }

  /// Получить последнюю локально сохраненную диагностику для оборудования/задания
  Future<Map<String, dynamic>?> getLatestPendingInspection({
    required String equipmentId,
    String? assignmentId,
  }) async {
    try {
      final pending = await getPendingInspections();
      Map<String, dynamic>? best;
      DateTime bestTs = DateTime.fromMillisecondsSinceEpoch(0);

      for (final item in pending) {
        final sameEquipment = item['equipment_id']?.toString() == equipmentId;
        final sameAssignment =
            (item['assignment_id']?.toString() ?? '') == (assignmentId ?? '');
        if (!sameEquipment || !sameAssignment) continue;

        final tsStr = item['timestamp']?.toString();
        final ts = tsStr != null
            ? (DateTime.tryParse(tsStr) ?? DateTime.now())
            : DateTime.now();
        if (ts.isAfter(bestTs)) {
          bestTs = ts;
          best = item;
        }
      }
      return best;
    } catch (_) {
      return null;
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

  /// Локальный статус по заданиям:
  /// - hasDraft: есть локальный черновик (DRAFT)
  /// - hasSigned: есть локально подписанное (SIGNED)
  Future<Map<String, LocalAssignmentInspectionState>> getLocalAssignmentInspectionState(
    List<String> assignmentIds,
  ) async {
    final state = <String, LocalAssignmentInspectionState>{};
    try {
      if (assignmentIds.isEmpty) return state;

      for (final id in assignmentIds) {
        state[id] = LocalAssignmentInspectionState.none();
      }

      final pending = await getPendingInspections();
      for (final item in pending) {
        final aId = item['assignment_id']?.toString();
        if (aId == null || aId.isEmpty) continue;
        if (!state.containsKey(aId)) continue;

        final st = (item['status']?.toString().toUpperCase() ?? 'DRAFT');
        final cur = state[aId] ?? LocalAssignmentInspectionState.none();
        if (st == 'SIGNED') {
          state[aId] = cur.copyWith(hasSigned: true);
        } else if (st == 'DRAFT') {
          state[aId] = cur.copyWith(hasDraft: true);
        }
      }
    } catch (_) {
      // Не роняем UI
    }
    return state;
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

      // 0) Сначала синхронизируем ОПО (они нужны для автоподтягивания пунктов 1-9)
      try {
        await _syncPendingOpoSurveys(result);
      } catch (e) {
        result.error = 'Ошибка синхронизации ОПО: $e';
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
        result.message ??= 'Синхронизация завершена. Нет данных для отправки на сервер';
        return result;
      }

      final prefs = await SharedPreferences.getInstance();
      final failedInspections = <String>[];

      for (final inspectionData in pendingInspections) {
        try {
          final data = Map<String, dynamic>.from(inspectionData['data'] as Map);
          
          // Определяем тип чек-листа на основе equipment_type
          VesselChecklist checklist;
          final equipmentType = data['equipment_type'] as String?;
          
          if (equipmentType != null && 
              (equipmentType.toUpperCase().contains('COMPRESSOR') || 
               equipmentType.toUpperCase().contains('КОМПРЕССОР'))) {
            // Используем CompressorChecklist для компрессоров
            checklist = CompressorChecklist.fromJson(data);
          } else {
            checklist = VesselChecklist.fromJson(data);
          }

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
            status: (inspectionData['status'] as String?) ?? 'DRAFT',
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
          // Сохраняем последнюю ошибку, чтобы пользователь видел причину
          result.error = e.toString();
        }
      }

      // Сохранить неудачные попытки
      await prefs.setStringList(_prefsKeyPendingInspections, failedInspections);

      // Обновить время последней синхронизации
      await prefs.setString(
          _prefsKeyLastSync, DateTime.now().toIso8601String());

      result.success = result.failedCount == 0;
      result.message =
          'Синхронизация завершена: ${result.syncedCount} успешно, ${result.failedCount} ошибок';
      if (result.failedCount > 0 && (result.error?.isNotEmpty ?? false)) {
        result.message = '${result.message}\nПоследняя ошибка: ${result.error}';
      }
    } catch (e) {
      result.error = 'Ошибка синхронизации: $e';
    }

    return result;
  }

  /// Сохранить опросный лист ОПО локально (для последующей синхронизации)
  Future<void> saveOpoSurveyOffline({
    required String opoId,
    required Map<String, dynamic> surveyData,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(_prefsKeyPendingOpoSurveys) ?? [];

      // Перезаписываем по opo_id
      final filtered = <String>[];
      for (final item in pending) {
        try {
          final decoded = json.decode(item) as Map<String, dynamic>;
          if (decoded['opo_id']?.toString() == opoId) continue;
          filtered.add(item);
        } catch (_) {
          filtered.add(item);
        }
      }

      filtered.add(json.encode({
        'opo_id': opoId,
        'survey_data': surveyData,
        'timestamp': DateTime.now().toIso8601String(),
      }));

      await prefs.setStringList(_prefsKeyPendingOpoSurveys, filtered);
    } catch (e) {
      throw Exception('Ошибка сохранения ОПО локально: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getPendingOpoSurveys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(_prefsKeyPendingOpoSurveys) ?? [];
      return pending.map((s) => json.decode(s) as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  /// Синхронизировать ожидающие опросные листы ОПО
  Future<void> _syncPendingOpoSurveys(SyncResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = await getPendingOpoSurveys();
    if (pending.isEmpty) return;

    final failed = <String>[];
    for (final item in pending) {
      try {
        final opoId = item['opo_id']?.toString();
        final data = item['survey_data'];
        if (opoId == null || opoId.isEmpty || data is! Map) {
          continue;
        }
        await _apiService.updateOpoSurvey(
          opoId: opoId,
          surveyData: Map<String, dynamic>.from(data),
        );
      } catch (e) {
        failed.add(json.encode(item));
        result.error = e.toString();
      }
    }

    await prefs.setStringList(_prefsKeyPendingOpoSurveys, failed);
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

class LocalAssignmentInspectionState {
  final bool hasDraft;
  final bool hasSigned;

  const LocalAssignmentInspectionState({
    required this.hasDraft,
    required this.hasSigned,
  });

  factory LocalAssignmentInspectionState.none() =>
      const LocalAssignmentInspectionState(hasDraft: false, hasSigned: false);

  LocalAssignmentInspectionState copyWith({bool? hasDraft, bool? hasSigned}) {
    return LocalAssignmentInspectionState(
      hasDraft: hasDraft ?? this.hasDraft,
      hasSigned: hasSigned ?? this.hasSigned,
    );
  }
}
