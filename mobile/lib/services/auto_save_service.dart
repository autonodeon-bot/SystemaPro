import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'database_service.dart';

/// Сервис для автоматического сохранения черновиков
class AutoSaveService {
  static const String _prefsKeyLastSave = 'last_auto_save_time';
  static const Duration _autoSaveInterval = Duration(seconds: 30);
  static const String _screenTypeInspection = 'inspection';

  /// Сохранить черновик обследования (sqflite + file backup)
  Future<void> saveDraft({
    required String equipmentId,
    required Map<String, dynamic> checklistData,
    String? assignmentId,
    String? inspectionId,
  }) async {
    try {
      final draftKey = inspectionId ?? 'draft_$equipmentId';
      final draft = {
        'id': draftKey,
        'equipment_id': equipmentId,
        'assignment_id': assignmentId,
        'checklist_data': checklistData,
        'saved_at': DateTime.now().toIso8601String(),
        'version': 1,
      };

      await DatabaseService.saveDraft(draftKey, _screenTypeInspection, draft);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyLastSave, DateTime.now().toIso8601String());

      await _saveToFile(draft);
    } catch (e) {
      print('Ошибка автосохранения: $e');
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
  Future<Map<String, dynamic>?> getDraftForEquipment(String equipmentId) async {
    final draftKey = 'draft_$equipmentId';
    final draft = await DatabaseService.getDraft(draftKey);
    if (draft != null) return draft;

    final drafts = await getDrafts();
    for (var d in drafts.values) {
      if (d['equipment_id'] == equipmentId) {
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
