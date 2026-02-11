import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as Path;
import 'package:path_provider/path_provider.dart';
import '../models/vessel_checklist.dart';
import '../models/compressor_checklist.dart';
import '../models/equipment.dart';
import '../models/assignment.dart';
import 'api_service.dart';
import 'inspection_archive_service.dart';

/// Сервис для офлайн-режима и синхронизации данных
class SyncService {
  static const String _prefsKeyPendingInspections = 'pending_inspections';
  static const String _prefsKeyLastSync = 'last_sync';
  static const String _prefsKeyOfflineMode = 'offline_mode';
  static const String _prefsKeyOfflineEquipment = 'offline_equipment';
  static const String _prefsKeyOfflineAssignments =
      'offline_assignments'; // Версия 3.3.0
  static const String _prefsKeyPendingOpoSurveys =
      'pending_opo_surveys'; // Версия 3.7.0
  static const String _prefsKeyOfflineEngineers = 'offline_engineers';
  static const String _prefsKeyOfflineVerificationEquipment =
      'offline_verification_equipment';
  static const String _prefsKeyOfflineOpos = 'offline_opos';

  final ApiService _apiService = ApiService();

  static String? _nonEmptyString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  /// Сохранить диагностику в локальное хранилище для последующей синхронизации
  Future<void> saveInspectionOffline({
    required String equipmentId,
    required VesselChecklist checklist,
    String? conclusion,
    required String inspectionDate,
    Map<String, String>? documentFiles,
    String? assignmentId, // ID задания (версия 3.3.0)
    List<String>?
        verificationEquipmentIds, // ID выбранного оборудования для поверок
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
      // Фото дефектов ВИК — загружаются на сервер с ключами vd_i_j для отчётов
      final vd = checklistJson['visual_defects'];
      if (vd is List) {
        for (var i = 0; i < vd.length; i++) {
          final d = vd[i];
          if (d is Map && d['photos'] is List) {
            final photos = d['photos'] as List;
            for (var j = 0; j < photos.length; j++) {
              final path = photos[j]?.toString();
              if (path != null && path.trim().isNotEmpty) {
                structuredDocumentFiles['vd_${i}_$j'] = {
                  'file_path': path,
                  'file_name': Path.basename(path),
                };
              }
            }
          }
        }
      }
      // Фото замеров УЗТ (точки замера толщины) — ключи uzt_point_i_j для отчётов
      final thickness = checklistJson['thickness_measurements'];
      if (thickness is List) {
        for (var i = 0; i < thickness.length; i++) {
          final t = thickness[i];
          if (t is Map && t['photos'] is List) {
            final photos = t['photos'] as List;
            for (var j = 0; j < photos.length; j++) {
              final path = photos[j]?.toString();
              if (path != null && path.trim().isNotEmpty) {
                structuredDocumentFiles['uzt_point_${i}_$j'] = {
                  'file_path': path,
                  'file_name': Path.basename(path),
                };
              }
            }
          }
        }
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
        'verification_equipment_ids': verificationEquipmentIds ??
            [], // ID выбранного оборудования для поверок
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

  /// Ищет файл по имени в папке offline_documents (fallback при смене пути)
  Future<String?> _findInOfflineDocuments(String fileName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final storageDir = Directory(Path.join(dir.path, 'offline_documents'));
      if (!await storageDir.exists()) return null;
      final baseName = Path.basename(fileName);
      final entities = storageDir.listSync();
      for (final e in entities) {
        if (e is File) {
          final name = Path.basename(e.path);
          if (name == baseName || name.endsWith('_$baseName')) return e.path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Локальный статус по заданиям:
  /// - hasDraft: есть локальный черновик (DRAFT)
  /// - hasSigned: есть локально подписанное (SIGNED)
  Future<Map<String, LocalAssignmentInspectionState>>
      getLocalAssignmentInspectionState(
    List<String> assignmentIds,
  ) async {
    final state = <String, LocalAssignmentInspectionState>{};
    try {
      if (assignmentIds.isEmpty) return state;

      // Инициализируем
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
        } else {
          // Игнорируем неизвестные статусы
        }
      }
    } catch (_) {
      // Не роняем UI, просто вернем то, что есть
    }
    return state;
  }

  /// Прогресс отправки: [reportIndex] из [reportTotal], отправлено [bytesSent] из [totalBytes].
  void Function(int reportIndex, int reportTotal, int bytesSent, int totalBytes)? onUploadProgress;

  /// Синхронизировать все ожидающие диагностики и загрузить оборудование.
  /// Каждое обследование собирается в ZIP-архив и загружается одним запросом (с прогрессом).
  Future<SyncResult> syncPendingInspections() async {
    final result = SyncResult();

    try {
      // Проверка подключения
      final isConnected = await _apiService.checkConnection();
      if (!isConnected) {
        result.error = 'Нет подключения к серверу';
        return result;
      }

      // Убедиться, что есть валидный токен (при переходе из офлайна — войти по сохранённым логину/паролю)
      final hasToken = await _apiService.ensureValidToken();
      if (!hasToken) {
        result.error = 'Войдите в приложение. После входа логин и пароль сохранятся для следующей синхронизации.';
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

      // Загружаем список инженеров с сервера и сохраняем локально
      try {
        final engineers = await _apiService.getEngineers();
        await saveEngineersOffline(engineers);
        if (result.message != null) {
          result.message = '${result.message}; Инженеры обновлены';
        } else {
          result.message = 'Список инженеров обновлен и сохранен локально';
        }
      } catch (e) {
        // Игнорируем ошибки загрузки инженеров, не роняем синхронизацию
        print('Ошибка загрузки инженеров: $e');
      }

      // Загружаем список поверенного оборудования с сервера и сохраняем локально
      try {
        final verificationEquipment = await _apiService.getVerificationEquipment();
        await saveVerificationEquipmentOffline(verificationEquipment);
        if (result.message != null) {
          result.message = '${result.message}; Поверенное оборудование обновлено';
        } else {
          result.message = 'Список поверенного оборудования обновлен и сохранен локально';
        }
      } catch (e) {
        // Игнорируем ошибки загрузки поверенного оборудования, не роняем синхронизацию
        print('Ошибка загрузки поверенного оборудования: $e');
      }

      // Загружаем задания инженера и сохраняем локально (для офлайн-режима)
      try {
        final assignments = await _apiService.getAssignments();
        await saveAssignmentsOffline(assignments);

        // Также подтягиваем оборудование по заданиям (MERGE внутри saveEquipmentOffline)
        final enterpriseIds = <String>{};
        for (final a in assignments) {
          try {
            final equipment = await _apiService.getAssignmentEquipment(a.id);
            await saveEquipmentOffline([equipment]);
            
            // Собираем enterprise_id для загрузки ОПО
            if (a.enterpriseId != null && a.enterpriseId!.isNotEmpty) {
              enterpriseIds.add(a.enterpriseId!);
            }
          } catch (_) {
            // Игнорируем ошибки по одному объекту, не роняем всю синхронизацию
          }
        }
        
        // Загружаем ОПО для предприятий из заданий
        for (final enterpriseId in enterpriseIds) {
          try {
            final opos = await _apiService.getOposByEnterprise(enterpriseId);
            await saveOposOffline(opos);
          } catch (_) {
            // Игнорируем ошибки загрузки ОПО
          }
        }
      } catch (_) {
        // Игнорируем: задания синхронизируются дополнительно к основному потоку
      }

      final pendingInspections = await getPendingInspections();
      if (pendingInspections.isEmpty) {
        result.success = true;
        result.message ??=
            'Синхронизация завершена. Нет данных для отправки на сервер';
        return result;
      }

      final prefs = await SharedPreferences.getInstance();
      final failedInspections = <Map<String, dynamic>>[];
      final successfulInspections = <Map<String, dynamic>>[];

      final toSend = pendingInspections.where((i) => (i['status'] as String? ?? 'DRAFT') != 'DRAFT').toList();
      final totalReports = toSend.length;

      for (var reportIndex = 0; reportIndex < toSend.length; reportIndex++) {
        final inspectionData = toSend[reportIndex];
        String? zipPath;
        try {
          final data = inspectionData['data'] as Map<String, dynamic>? ?? {};
          final rawEqId = inspectionData['equipment_id'];
          final equipmentId = rawEqId != null ? rawEqId.toString().trim() : '';
          if (equipmentId.isEmpty) {
            result.lastFailureReason = 'Нет ID оборудования в сохранённых данных';
            failedInspections.add(inspectionData);
            result.failedCount++;
            continue;
          }

          zipPath = await InspectionArchiveService.buildArchive(inspectionData: inspectionData);
          final zipFile = File(zipPath);
          final totalBytes = zipFile.lengthSync();

          final submitResult = await _apiService.uploadInspectionArchive(
            zipPath,
            onProgress: (sent, total) {
              onUploadProgress?.call(reportIndex + 1, totalReports, sent, total > 0 ? total : totalBytes);
            },
          );

          try {
            zipFile.deleteSync();
          } catch (_) {}

          final inspectionId = submitResult['id'] as String?;
          if (submitResult.containsKey('questionnaire_id') && submitResult['questionnaire_id'] != null) {
            inspectionData['questionnaire_id_synced'] = submitResult['questionnaire_id'] as String;
          }

          final checklist = data['equipment_type'] != null &&
                  (data['equipment_type'].toString().toUpperCase().contains('COMPRESSOR') ||
                      data['equipment_type'].toString().toUpperCase().contains('КОМПРЕССОР'))
              ? CompressorChecklist.fromJson(data)
              : VesselChecklist.fromJson(data);
          try {
            await _apiService.updateEquipmentFromChecklist(equipmentId: equipmentId, checklist: checklist);
          } catch (e) {
            print('Ошибка обновления данных оборудования: $e');
          }
          final verificationEquipmentIds = inspectionData['verification_equipment_ids'] as List<dynamic>?;
          if (inspectionId != null && verificationEquipmentIds != null && verificationEquipmentIds.isNotEmpty) {
            try {
              final equipmentIds = verificationEquipmentIds
                  .map((id) => id.toString())
                  .where((id) => id.isNotEmpty)
                  .toList();
              if (equipmentIds.isNotEmpty) {
                await _apiService.addEquipmentToInspection(inspectionId, equipmentIds);
              }
            } catch (e) {
              print('Ошибка добавления оборудования для поверок: $e');
            }
          }
          successfulInspections.add(inspectionData);
          result.syncedCount++;
        } catch (e, st) {
          try {
            if (zipPath != null) File(zipPath).deleteSync();
          } catch (_) {}
          result.lastFailureReason = e is Exception ? e.toString() : '$e';
          if (result.lastFailureReason != null && result.lastFailureReason!.startsWith('Exception: ')) {
            result.lastFailureReason = result.lastFailureReason!.substring('Exception: '.length);
          }
          print('Синхронизация: ошибка отправки обследования: $e');
          failedInspections.add(inspectionData);
          result.failedCount++;
        }
      }

      // Удаляем успешно отправленные инспекции из локального хранилища
      // Оставляем только неудачные попытки и черновики (DRAFT)
      final remainingInspections = pendingInspections
          .where((item) {
            final itemJson = json.encode(item);
            return !successfulInspections.any((s) => json.encode(s) == itemJson);
          })
          .toList();
      
      // Сохраняем только неудачные попытки и черновики
      final remainingInspectionsJson = remainingInspections
          .map((s) => json.encode(s))
          .toList();
      await prefs.setStringList(_prefsKeyPendingInspections, remainingInspectionsJson);

      // Синхронизация ОПО опросников
      try {
        final pendingOpoSurveys = await getPendingOpoSurveys();
        final successfulOpoIds = <String>[];
        
        for (final surveyData in pendingOpoSurveys) {
          try {
            final opoId = surveyData['opo_id'] as String;
            final survey = surveyData['survey_data'] as Map<String, dynamic>;
            
            await _apiService.updateOpoSurvey(
              opoId: opoId,
              surveyData: survey,
            );
            
            successfulOpoIds.add(opoId);
          } catch (e) {
            print('Ошибка синхронизации ОПО: $e');
          }
        }
        
        // Удаляем успешно отправленные ОПО опросники
        final remainingOpoSurveys = pendingOpoSurveys
            .where((item) {
              final opoId = item['opo_id'] as String?;
              return opoId != null && !successfulOpoIds.contains(opoId);
            })
            .toList();
        
        final remainingOpoSurveysJson = remainingOpoSurveys
            .map((s) => json.encode(s))
            .toList();
        await prefs.setStringList(_prefsKeyPendingOpoSurveys, remainingOpoSurveysJson);
      } catch (e) {
        // Не блокируем основную синхронизацию из-за ошибок ОПО
        print('Ошибка синхронизации ОПО опросников: $e');
      }

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

  /// Сохранить список инженеров локально для офлайн-режима
  /// MERGE: не перетираем список (иначе при синхронизации останется только последний набор)
  Future<void> saveEngineersOffline(
      List<Map<String, dynamic>> engineers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // MERGE: не перетираем список (иначе при синхронизации останется только последний набор)
      final existing = await getOfflineEngineers();
      final merged = <String, Map<String, dynamic>>{};
      for (final e in existing) {
        final id = e['id']?.toString();
        if (id != null && id.isNotEmpty) {
          merged[id] = e;
        }
      }
      for (final e in engineers) {
        final id = e['id']?.toString();
        if (id != null && id.isNotEmpty) {
          merged[id] = e; // Обновляем существующие или добавляем новые
        }
      }

      final engineersJsonList =
          merged.values.map((e) => json.encode(e)).toList();
      await prefs.setStringList(_prefsKeyOfflineEngineers, engineersJsonList);
    } catch (e) {
      throw Exception('Ошибка сохранения инженеров локально: $e');
    }
  }

  /// Получить список инженеров из локального хранилища
  Future<List<Map<String, dynamic>>> getOfflineEngineers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final engineersJsonList =
          prefs.getStringList(_prefsKeyOfflineEngineers) ?? [];
      return engineersJsonList.map((item) {
        return json.decode(item) as Map<String, dynamic>;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Сохранить список поверенного оборудования локально для офлайн-режима
  /// MERGE: не перетираем список (иначе при синхронизации останется только последний набор)
  Future<void> saveVerificationEquipmentOffline(
      List<Map<String, dynamic>> equipment) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // MERGE: не перетираем список (иначе при синхронизации останется только последний набор)
      final existing = await getOfflineVerificationEquipment();
      final merged = <String, Map<String, dynamic>>{};
      for (final e in existing) {
        final id = e['id']?.toString();
        if (id != null && id.isNotEmpty) {
          merged[id] = e;
        }
      }
      for (final e in equipment) {
        final id = e['id']?.toString();
        if (id != null && id.isNotEmpty) {
          merged[id] = e; // Обновляем существующие или добавляем новые
        }
      }

      final equipmentJsonList =
          merged.values.map((e) => json.encode(e)).toList();
      await prefs.setStringList(
          _prefsKeyOfflineVerificationEquipment, equipmentJsonList);
    } catch (e) {
      throw Exception(
          'Ошибка сохранения поверенного оборудования локально: $e');
    }
  }

  /// Получить список поверенного оборудования из локального хранилища
  Future<List<Map<String, dynamic>>> getOfflineVerificationEquipment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final equipmentJsonList =
          prefs.getStringList(_prefsKeyOfflineVerificationEquipment) ?? [];
      return equipmentJsonList.map((item) {
        return json.decode(item) as Map<String, dynamic>;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Очистить офлайн-данные (при выходе/смене пользователя).
  /// Очередь неотправленных обследований (pending_inspections) НЕ очищаем,
  /// чтобы после повторного входа можно было подключиться и синхронизировать.
  Future<void> clearOfflineCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyOfflineEquipment);
    await prefs.remove(_prefsKeyOfflineAssignments);
    await prefs.remove(_prefsKeyLastSync);
    await prefs.remove(_prefsKeyOfflineMode);
    await prefs.remove(_prefsKeyOfflineEngineers);
    await prefs.remove(_prefsKeyOfflineVerificationEquipment);
    await prefs.remove(_prefsKeyOfflineOpos);
    await prefs.remove(_prefsKeyPendingOpoSurveys);
  }

  /// Полная очистка, включая очередь неотправленных обследований (только по явному запросу пользователя).
  Future<void> clearOfflineCacheIncludingPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyPendingInspections);
    await clearOfflineCache();
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
      await prefs.setStringList(
          _prefsKeyOfflineAssignments, assignmentsJsonList);
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

  /// Сохранить опросник ОПО в офлайн-режиме (версия 3.7.0)
  Future<void> saveOpoSurveyOffline({
    required String opoId,
    required Map<String, dynamic> surveyData,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingSurveys =
          prefs.getStringList(_prefsKeyPendingOpoSurveys) ?? [];

      final surveyEntry = {
        'opo_id': opoId,
        'survey_data': surveyData,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Удаляем старую запись для этого ОПО, если есть
      pendingSurveys.removeWhere((item) {
        try {
          final decoded = json.decode(item) as Map<String, dynamic>;
          return decoded['opo_id'] == opoId;
        } catch (_) {
          return false;
        }
      });

      pendingSurveys.add(json.encode(surveyEntry));
      await prefs.setStringList(_prefsKeyPendingOpoSurveys, pendingSurveys);
    } catch (e) {
      throw Exception('Ошибка сохранения опросника ОПО: $e');
    }
  }

  /// Получить список ожидающих синхронизации опросников ОПО (версия 3.7.0)
  Future<List<Map<String, dynamic>>> getPendingOpoSurveys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingSurveys =
          prefs.getStringList(_prefsKeyPendingOpoSurveys) ?? [];

      return pendingSurveys.map((item) {
        return json.decode(item) as Map<String, dynamic>;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Сохранить список ОПО локально для офлайн-режима
  Future<void> saveOposOffline(List<Map<String, dynamic>> opos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // MERGE: не перетираем список
      final existing = await getOfflineOpos();
      final merged = <String, Map<String, dynamic>>{};
      for (final o in existing) {
        final id = o['id'] as String?;
        if (id != null) {
          merged[id] = o;
        }
      }
      for (final o in opos) {
        final id = o['id'] as String?;
        if (id != null) {
          merged[id] = o;
        }
      }

      final oposJsonList = merged.values.map((o) => json.encode(o)).toList();
      await prefs.setStringList(_prefsKeyOfflineOpos, oposJsonList);
    } catch (e) {
      throw Exception('Ошибка сохранения ОПО локально: $e');
    }
  }

  /// Получить список ОПО из локального хранилища
  Future<List<Map<String, dynamic>>> getOfflineOpos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final oposJsonList = prefs.getStringList(_prefsKeyOfflineOpos) ?? [];

      return oposJsonList.map((item) {
        return json.decode(item) as Map<String, dynamic>;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Получить последний ожидающий inspection для оборудования (версия 3.7.0)
  Future<Map<String, dynamic>?> getLatestPendingInspection({
    required String equipmentId,
    String? assignmentId,
  }) async {
    try {
      final pending = await getPendingInspections();

      // Фильтруем по equipment_id и assignment_id (если указан)
      final matching = pending.where((item) {
        final eqId = item['equipment_id']?.toString();
        if (eqId != equipmentId) return false;

        if (assignmentId != null) {
          final aId = item['assignment_id']?.toString();
          if (aId != assignmentId) return false;
        }

        return true;
      }).toList();

      if (matching.isEmpty) return null;

      // Сортируем по timestamp (новые первыми) и возвращаем последний
      matching.sort((a, b) {
        final tsA = a['timestamp'] as String? ?? '';
        final tsB = b['timestamp'] as String? ?? '';
        return tsB.compareTo(tsA);
      });

      return matching.first;
    } catch (e) {
      return null;
    }
  }
}

class SyncResult {
  bool success = false;
  int syncedCount = 0;
  int failedCount = 0;
  String? message;
  String? error;
  /// Текст последней ошибки при отправке обследования (для показа пользователю).
  String? lastFailureReason;
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
