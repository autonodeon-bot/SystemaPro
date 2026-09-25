import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'database_service.dart';

/// Сервис для автоматического сохранения черновиков
class AutoSaveService {
  static String draftKey({required String equipmentId, String? assignmentId, String? inspectionId, String? reportFormId}) {
    if (inspectionId != null && inspectionId.isNotEmpty) return inspectionId;
    if ((assignmentId ?? '').isEmpty && (reportFormId ?? '').isEmpty) return 'draft_$equipmentId';
    return 'draft_${Uri.encodeComponent(equipmentId)}_${Uri.encodeComponent(assignmentId ?? "")}_${Uri.encodeComponent(reportFormId ?? "")}';
  }
  static const String _prefsKeyLastSave = 'last_auto_save_time';
  static const String _screenTypeInspection = 'inspection';

  // Типы экранов для черновиков
  static const String screenTypeQuickControl  = 'quick_control';
  static const String screenTypeNdkProtocol   = 'ndk_protocol';
  static const String screenTypeCustomProtocol = 'custom_protocol';

  /// Сохранить черновик обследования (sqflite + file backup)
  Future<void> saveDraft({
    required String equipmentId,
    required Map<String, dynamic> checklistData,
    String? assignmentId,
    String? inspectionId,
  }) async {
    try {
      final key = draftKey(equipmentId: equipmentId, assignmentId: assignmentId,
          inspectionId: inspectionId, reportFormId: checklistData['report_form_id']?.toString());
      final draft = {
        'id': key,
        'equipment_id': equipmentId,
        'assignment_id': assignmentId,
        'checklist_data': checklistData,
        'saved_at': DateTime.now().toIso8601String(),
        'version': 1,
      };

      await DatabaseService.saveDraft(key, _screenTypeInspection, draft);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyLastSave, DateTime.now().toIso8601String());

      await _saveToFile(draft);
    } catch (e) {
      print('Ошибка автосохранения: $e');
      rethrow;
    }
  }

  /// Получить все черновики (sqflite)
  Future<Map<String, Map<String, dynamic>>> getDrafts() async {
    try {
      final rows = await DatabaseService.getAllDrafts();
      final Map<String, Map<String, dynamic>> drafts = {};
      for (var row in rows) {
        final id = row['id'] as String?;
        if (id != null) {
          drafts[id] = row;
        }
      }
      return drafts;
    } catch (e) {
      return {};
    }
  }

  /// Получить черновик для конкретного оборудования
  Future<Map<String, dynamic>?> getDraftForEquipment(String equipmentId, {
    String? assignmentId, String? inspectionId, String? reportFormId,
  }) async {
    final key = draftKey(equipmentId: equipmentId, assignmentId: assignmentId,
        inspectionId: inspectionId, reportFormId: reportFormId);
    final draft = await DatabaseService.getDraft(key);
    if (draft != null) return draft;

    final drafts = await getDrafts();
    final candidates = drafts.values.toList()
      ..sort((a, b) => (b['saved_at'] ?? '').toString().compareTo((a['saved_at'] ?? '').toString()));
    for (var d in candidates) {
      final data = d['checklist_data'];
      final sameForm = reportFormId == null || (data is Map && data['report_form_id'] == reportFormId);
      if (d['equipment_id'] == equipmentId &&
          (d['assignment_id'] ?? '') == (assignmentId ?? '') && sameForm &&
          (inspectionId == null || d['id'] == inspectionId)) {
        return d;
      }
    }
    return null;
  }

  /// Удалить черновик (sqflite + file backup)
  Future<void> deleteDraft(String draftId) async {
    try {
      await DatabaseService.deleteDraft(draftId);
      await _deleteFile(draftId);
    } catch (e) {
      print('Ошибка удаления черновика: $e');
    }
  }

  /// Универсальное сохранение черновика любого типа экрана.
  /// [screenType] — 'quick_control' | 'ndk_protocol' | 'custom_protocol' | 'inspection'
  /// [id] — уникальный ключ черновика
  /// [data] — данные формы
  /// [meta] — отображаемые поля: objectName, controlType, category
  Future<void> saveGenericDraft({
    required String id,
    required String screenType,
    required Map<String, dynamic> data,
    Map<String, dynamic>? meta,
  }) async {
    try {
      final draft = {
        'id': id,
        'screen_type': screenType,
        'equipment_id': meta?['equipment_id'] ?? id,
        'checklist_data': {
          ...data,
          'object_name': meta?['objectName'] ?? '',
          'inspection_type': screenType,
          'control_type': meta?['controlType'] ?? screenType,
          'category': meta?['category'] ?? '',
          ...?meta,
        },
        'saved_at': DateTime.now().toIso8601String(),
        'version': 1,
      };
      await DatabaseService.saveDraft(id, screenType, draft);
      await _saveToFile(draft);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyLastSave, DateTime.now().toIso8601String());
    } catch (e) {
      print('Ошибка saveGenericDraft: $e');
    }
  }

  /// Получить черновик по id
  Future<Map<String, dynamic>?> getDraftById(String id) async {
    return await DatabaseService.getDraft(id);
  }

  /// Очистить все черновики старше определенного времени (sqflite)
  Future<void> cleanOldDrafts({Duration maxAge = const Duration(days: 30)}) async {
    try {
      await DatabaseService.clearOldDrafts(maxAge: maxAge);
    } catch (e) {
      print('Ошибка очистки старых черновиков: $e');
    }
  }

  /// Сохранить в файл для резервного копирования
  Future<void> _saveToFile(Map<String, dynamic> draft) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final draftsDir = Directory(path.join(dir.path, 'drafts_backup'));
      if (!await draftsDir.exists()) {
        await draftsDir.create(recursive: true);
      }

      final file = File(path.join(draftsDir.path, '${draft['id']}.json'));
      await file.writeAsString(json.encode(draft));
    } catch (e) {
      print('Ошибка сохранения в файл: $e');
    }
  }

  /// Удалить файл резервной копии
  Future<void> _deleteFile(String draftId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(path.join(dir.path, 'drafts_backup', '$draftId.json'));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Игнорируем ошибки удаления файла
    }
  }

  /// Восстановить черновик из резервной копии
  Future<Map<String, dynamic>?> restoreFromBackup(String draftId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(path.join(dir.path, 'drafts_backup', '$draftId.json'));
      if (await file.exists()) {
        final content = await file.readAsString();
        return json.decode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      print('Ошибка восстановления из резервной копии: $e');
    }
    return null;
  }
}
