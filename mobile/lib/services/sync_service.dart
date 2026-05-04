import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as Path;
import 'package:path_provider/path_provider.dart';
import '../models/vessel_checklist.dart';
import '../models/compressor_checklist.dart';
import '../models/equipment.dart';
import '../models/assignment.dart';
import 'api_service.dart';
import 'inspection_archive_service.dart';
import 'database_service.dart';
import 'drawing_templates_service.dart';

/// Сервис для офлайн-режима и синхронизации данных
class SyncService {
  static const String _prefsKeyLastSync = 'last_sync';
  static const String _prefsKeyOfflineMode = 'offline_mode';

  final ApiService _apiService = ApiService();
  static const int _uploadArchiveRetryCount = 3;
  static const Duration _uploadArchiveRetryDelay = Duration(seconds: 2);

  static String? _nonEmptyString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  static String _normalizedStatus(Map<String, dynamic> item) {
    return (item['status']?.toString().trim().toUpperCase() ?? 'DRAFT');
  }

  static String _queueKey(Map<String, dynamic> item) {
    final assignmentId = _nonEmptyString(item['assignment_id']) ?? '';
    final equipmentId = _nonEmptyString(item['equipment_id']) ?? '';
    final datePerformed = _nonEmptyString(item['date_performed']) ?? '';
    return '$assignmentId|$equipmentId|$datePerformed';
  }

  static String _normalizeIsoDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return DateTime.now().toIso8601String();
    }
    try {
      return DateTime.parse(value.trim()).toIso8601String();
    } catch (_) {
      return DateTime.now().toIso8601String();
    }
  }

  static bool _sameAssignmentAndEquipment(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aAssignmentId = _nonEmptyString(a['assignment_id']);
    final bAssignmentId = _nonEmptyString(b['assignment_id']);
    final aEquipmentId = _nonEmptyString(a['equipment_id']);
    final bEquipmentId = _nonEmptyString(b['equipment_id']);
    return aAssignmentId != null &&
        bAssignmentId != null &&
        aEquipmentId != null &&
        bEquipmentId != null &&
        aAssignmentId == bAssignmentId &&
        aEquipmentId == bEquipmentId;
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
      final pendingInspections = await DatabaseService.getPendingInspections();

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
      final additionalData = checklistJson['additional_data'];
      if (additionalData is Map) {
        final objectPhotos = additionalData['object_photos'];
        if (objectPhotos is List) {
          for (var i = 0; i < objectPhotos.length; i++) {
            final path = objectPhotos[i]?.toString();
            if (path == null || path.trim().isEmpty) continue;
            structuredDocumentFiles['object_photo_$i'] = {
              'file_path': path,
              'file_name': Path.basename(path),
            };
          }
        }
      }
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

      final inspectionData = <String, dynamic>{
        'equipment_id': equipmentId,
        'data': checklistJson,
        'conclusion': conclusion,
        'date_performed': _normalizeIsoDateTime(
          _nonEmptyString(inspectionDate) ??
              _nonEmptyString(checklistJson['inspection_date']),
        ),
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
      inspectionData['id'] = _queueKey(inspectionData);

      final newStatus = _normalizedStatus(inspectionData);
      final cleaned = pendingInspections.where((existing) {
        final existingStatus = _normalizedStatus(existing);
        final sameScope = _sameAssignmentAndEquipment(existing, inspectionData);
        if (!sameScope) {
          return true;
        }

        // Для SIGNED оставляем только последний подписанный вариант (удаляем и старые черновики).
        if (newStatus == 'SIGNED') {
          return false;
        }
        // Для DRAFT обновляем текущий черновик по этому же заданию/оборудованию.
        if (newStatus == 'DRAFT' && existingStatus == 'DRAFT') {
          return false;
        }
        return true;
      }).toList();

      cleaned.add(inspectionData);
      await DatabaseService.replacePendingInspections(cleaned);
    } catch (e) {
      throw Exception('Ошибка сохранения в офлайн-режиме: $e');
    }
  }

  /// Получить список ожидающих синхронизации диагностик
  Future<List<Map<String, dynamic>>> getPendingInspections() async {
    try {
      return await DatabaseService.getPendingInspections();
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
        final equipmentList = await _apiService.getAllEquipment();
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
      } catch (e) {
        result.message = '${result.message ?? 'Синхронизация завершена'}; '
            'не удалось обновить задания (${e.toString()})';
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

      // Отправляем и DRAFT, и SIGNED: офлайн-работа должна появляться на сервере после синхронизации.
      final toSend = List<Map<String, dynamic>>.from(pendingInspections);
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

          final submitResult = await _uploadInspectionArchiveWithRetry(
            zipPath: zipPath,
            reportIndex: reportIndex,
            totalReports: totalReports,
            totalBytes: totalBytes,
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
        } catch (e) {
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
      final successfulKeys = successfulInspections.map(_queueKey).toSet();
      final successfulAssignmentEquipment = successfulInspections
          .where((s) => _nonEmptyString(s['assignment_id']) != null && _nonEmptyString(s['equipment_id']) != null)
          .map((s) => '${_nonEmptyString(s['assignment_id'])}|${_nonEmptyString(s['equipment_id'])}')
          .toSet();

      final remainingInspections = pendingInspections.where((item) {
        final key = _queueKey(item);
        if (successfulKeys.contains(key)) {
          return false;
        }

        // После успешной отправки подписанного отчета очищаем связанные локальные записи по тому же assignment/equipment.
        final assignmentId = _nonEmptyString(item['assignment_id']);
        final equipmentId = _nonEmptyString(item['equipment_id']);
        if (assignmentId != null && equipmentId != null) {
          final pair = '$assignmentId|$equipmentId';
          if (successfulAssignmentEquipment.contains(pair)) {
            return false;
          }
        }
        return true;
      }).toList();
      
      // Сохраняем только неудачные попытки и черновики
      await DatabaseService.replacePendingInspections(remainingInspections);

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
        
        // Удаляем успешно отправленные ОПО опросники из sqflite
        for (final opoId in successfulOpoIds) {
          await DatabaseService.deleteOpoSurvey(opoId);
        }
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

  Future<Map<String, dynamic>> _uploadInspectionArchiveWithRetry({
    required String zipPath,
    required int reportIndex,
    required int totalReports,
    required int totalBytes,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _uploadArchiveRetryCount; attempt++) {
      try {
        return await _apiService.uploadInspectionArchive(
          zipPath,
          onProgress: (sent, total) {
            onUploadProgress?.call(
              reportIndex + 1,
              totalReports,
              sent,
              total > 0 ? total : totalBytes,
            );
          },
        );
      } catch (e) {
        lastError = e;
        if (attempt < _uploadArchiveRetryCount) {
          await Future.delayed(_uploadArchiveRetryDelay);
        }
      }
    }
    throw Exception(
      'Не удалось отправить архив после $_uploadArchiveRetryCount попыток: $lastError',
    );
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
    await DatabaseService.clearPendingInspections();
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

  /// Сохранить список оборудования локально для офлайн-режима (sqflite)
  Future<void> saveEquipmentOffline(List<Equipment> equipmentList) async {
    try {
      final jsonList = equipmentList.map((eq) => eq.toJson()).toList();
      await DatabaseService.saveEquipment(jsonList);
    } catch (e) {
      throw Exception('Ошибка сохранения оборудования локально: $e');
    }
  }

  /// Сохранить список инженеров локально для офлайн-режима (sqflite, MERGE)
  Future<void> saveEngineersOffline(
      List<Map<String, dynamic>> engineers) async {
    try {
      await DatabaseService.saveEngineers(engineers);
    } catch (e) {
      throw Exception('Ошибка сохранения инженеров локально: $e');
    }
  }

  /// Получить список инженеров из локального хранилища (sqflite)
  Future<List<Map<String, dynamic>>> getOfflineEngineers() async {
    try {
      return await DatabaseService.getEngineers();
    } catch (e) {
      return [];
    }
  }

  /// Сохранить список поверенного оборудования локально для офлайн-режима (sqflite, MERGE)
  Future<void> saveVerificationEquipmentOffline(
      List<Map<String, dynamic>> equipment) async {
    try {
      await DatabaseService.saveVerificationEquipment(equipment);
    } catch (e) {
      throw Exception(
          'Ошибка сохранения поверенного оборудования локально: $e');
    }
  }

  /// Получить список поверенного оборудования из локального хранилища (sqflite)
  Future<List<Map<String, dynamic>>> getOfflineVerificationEquipment() async {
    try {
      return await DatabaseService.getVerificationEquipment();
    } catch (e) {
      return [];
    }
  }

  /// Очистить офлайн-данные (при выходе/смене пользователя).
  /// Очередь неотправленных обследований (pending_inspections) НЕ очищаем,
  /// чтобы после повторного входа можно было подключиться и синхронизировать.
  Future<void> clearOfflineCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyLastSync);
    await prefs.remove(_prefsKeyOfflineMode);
    await DatabaseService.clearAllCaches();
  }

  /// Полная очистка, включая очередь неотправленных обследований (только по явному запросу пользователя).
  Future<void> clearOfflineCacheIncludingPending() async {
    await DatabaseService.clearPendingInspections();
    await clearOfflineCache();
  }

  /// Синхронизировать шаблоны чертежей (П.2 ТЗ 2026-04).
  ///
  /// Делает дельта-sync (по last_sync), при необходимости docачивает свежие
  /// PNG/JPG и обновляет sqflite.drawing_templates.
  /// Возвращает количество обновлённых шаблонов.
  Future<int> syncDrawingTemplates({List<String>? equipmentIds}) async {
    try {
      final svc = DrawingTemplatesService();
      return await svc.syncDelta(equipmentIds: equipmentIds);
    } catch (e) {
      // ignore: avoid_print
      print('SyncService.syncDrawingTemplates error: $e');
      return 0;
    }
  }

  /// Предзагрузка шаблонов для набора оборудования (напр., при открытии
  /// списка заданий, чтобы инженер мог работать офлайн).
  Future<int> prefetchDrawingTemplatesForAssignments(List<Assignment> assignments) async {
    final ids = assignments
        .map((a) => a.equipmentId)
        .where((e) => e != null && e.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return 0;
    final svc = DrawingTemplatesService();
    return svc.prefetchForEquipmentIds(ids);
  }

  /// Получить список оборудования из локального хранилища (sqflite)
  Future<List<Equipment>> getOfflineEquipment() async {
    try {
      final rows = await DatabaseService.getEquipment();
      return rows.map((jsonData) {
        final map = jsonData is Map<String, dynamic>
            ? jsonData
            : json.decode(jsonData.toString()) as Map<String, dynamic>;
        return Equipment.fromJson(map);
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Сохранить список заданий локально для офлайн-режима (sqflite, версия 3.3.0)
  Future<void> saveAssignmentsOffline(List<Assignment> assignments) async {
    try {
      final jsonList = assignments.map((a) => a.toJson()).toList();
      await DatabaseService.saveAssignments(jsonList);
    } catch (e) {
      throw Exception('Ошибка сохранения заданий локально: $e');
    }
  }

  /// Получить список заданий из локального хранилища (sqflite, версия 3.3.0)
  Future<List<Assignment>> getOfflineAssignments() async {
    try {
      final rows = await DatabaseService.getAssignments();
      return rows.map((jsonData) {
        final map = jsonData is Map<String, dynamic>
            ? jsonData
            : json.decode(jsonData.toString()) as Map<String, dynamic>;
        return Assignment.fromJson(map);
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Сохранить опросник ОПО в офлайн-режиме (sqflite, версия 3.7.0)
  Future<void> saveOpoSurveyOffline({
    required String opoId,
    required Map<String, dynamic> surveyData,
  }) async {
    try {
      final surveyEntry = {
        'survey_data': surveyData,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await DatabaseService.saveOpoSurvey(opoId, surveyEntry);
    } catch (e) {
      throw Exception('Ошибка сохранения опросника ОПО: $e');
    }
  }

  /// Получить список ожидающих синхронизации опросников ОПО (sqflite, версия 3.7.0)
  Future<List<Map<String, dynamic>>> getPendingOpoSurveys() async {
    try {
      return await DatabaseService.getOpoSurveys();
    } catch (e) {
      return [];
    }
  }

  /// Сохранить список ОПО локально для офлайн-режима (sqflite, MERGE)
  Future<void> saveOposOffline(List<Map<String, dynamic>> opos) async {
    try {
      await DatabaseService.saveOpos(opos);
    } catch (e) {
      throw Exception('Ошибка сохранения ОПО локально: $e');
    }
  }

  /// Получить список ОПО из локального хранилища (sqflite)
  Future<List<Map<String, dynamic>>> getOfflineOpos() async {
    try {
      return await DatabaseService.getOpos();
    } catch (e) {
      return [];
    }
  }

  // ─── Delta sync ──────────────────────────────────────────────────────────

  static const String _prefsKeyLastAssignmentsSync = 'last_assignments_sync'; // хранится в sync_metadata (sqflite)

  /// Инкрементальная синхронизация заданий (дельта).
  /// Запрашивает только изменённые записи с момента последней синхронизации,
  /// мерджит с локальным кэшем и обновляет метку времени.
  Future<List<dynamic>> syncAssignmentsDelta() async {
    final lastSyncStr = await DatabaseService.getSyncMeta(_prefsKeyLastAssignmentsSync);

    final assignments = await _apiService.getAssignmentsDelta(since: lastSyncStr);

    final cached = await DatabaseService.getAssignments();

    final Map<String, dynamic> assignmentMap = {};
    for (var a in cached) {
      if (a is Map<String, dynamic>) {
        final id = a['id']?.toString();
        if (id != null) assignmentMap[id] = a;
      }
    }
    for (var a in assignments) {
      if (a is Map<String, dynamic>) {
        final id = a['id']?.toString();
        if (id != null) assignmentMap[id] = a;
      }
    }

    final merged = assignmentMap.values.toList();

    final mergedAssignments = merged
        .whereType<Map<String, dynamic>>()
        .map((j) => Assignment.fromJson(j))
        .toList();
    await saveAssignmentsOffline(mergedAssignments);

    await DatabaseService.setSyncMeta(
      _prefsKeyLastAssignmentsSync,
      DateTime.now().toUtc().toIso8601String(),
    );

    return merged;
  }

  // ─── Conflict-aware full sync ──────────────────────────────────────────

  /// Полная синхронизация с определением конфликтов:
  /// 1. Отправить локальные обследования
  /// 2. Скачать дельту заданий
  /// 3. Обновить оборудование
  Future<SyncResultFull> syncWithConflictDetection() async {
    final results = SyncResultFull();

    try {
      final uploaded = await syncPendingInspections();
      results.uploaded = uploaded.syncedCount;
      results.uploadFailed = uploaded.failedCount;

      try {
        final updated = await syncAssignmentsDelta();
        results.updatedAssignments = updated.length;
      } catch (e) {
        results.deltaSyncError = e.toString();
      }

      try {
        final equipmentList = await _apiService.getAllEquipment();
        await saveEquipmentOffline(equipmentList);
      } catch (_) {}

      results.success = true;
    } catch (e) {
      results.success = false;
      results.error = e.toString();
    }

    return results;
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

class SyncResultFull {
  bool success = false;
  int uploaded = 0;
  int uploadFailed = 0;
  int updatedAssignments = 0;
  String? error;
  String? deltaSyncError;
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
