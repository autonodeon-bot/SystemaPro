import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

/// Сервис для автоматического сохранения черновиков
class AutoSaveService {
  static const String _prefsKeyDrafts = 'auto_save_drafts';
  static const String _prefsKeyLastSave = 'last_auto_save_time';
  static const Duration _autoSaveInterval = Duration(seconds: 30);

  /// Сохранить черновик обследования
  Future<void> saveDraft({
    required String equipmentId,
    required Map<String, dynamic> checklistData,
    String? assignmentId,
    String? inspectionId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final drafts = await getDrafts();
      
      final draftKey = inspectionId ?? 'draft_$equipmentId';
      final draft = {
        'id': draftKey,
        'equipment_id': equipmentId,
        'assignment_id': assignmentId,
        'checklist_data': checklistData,
        'saved_at': DateTime.now().toIso8601String(),
        'version': 1,
      };

      // Обновляем или добавляем черновик
      drafts[draftKey] = draft;

      // Сохраняем в SharedPreferences
      final draftsJson = drafts.values.map((d) => json.encode(d)).toList();
      await prefs.setStringList(_prefsKeyDrafts, draftsJson);
      await prefs.setString(_prefsKeyLastSave, DateTime.now().toIso8601String());

      // Также сохраняем в файл для резервного копирования
      await _saveToFile(draft);
    } catch (e) {
      print('Ошибка автосохранения: $e');
    }
  }

  /// Получить все черновики
  Future<Map<String, Map<String, dynamic>>> getDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftsJson = prefs.getStringList(_prefsKeyDrafts) ?? [];
      
      final Map<String, Map<String, dynamic>> drafts = {};
      for (var jsonStr in draftsJson) {
        try {
          final draft = json.decode(jsonStr) as Map<String, dynamic>;
          final id = draft['id'] as String?;
          if (id != null) {
            drafts[id] = draft;
          }
        } catch (e) {
          print('Ошибка парсинга черновика: $e');
        }
      }
      return drafts;
    } catch (e) {
      return {};
    }
  }

  /// Получить черновик для конкретного оборудования
  Future<Map<String, dynamic>?> getDraftForEquipment(String equipmentId) async {
    final drafts = await getDrafts();
    for (var draft in drafts.values) {
      if (draft['equipment_id'] == equipmentId) {
        return draft;
      }
    }
    return null;
  }

  /// Удалить черновик
  Future<void> deleteDraft(String draftId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final drafts = await getDrafts();
      drafts.remove(draftId);
      
      final draftsJson = drafts.values.map((d) => json.encode(d)).toList();
      await prefs.setStringList(_prefsKeyDrafts, draftsJson);
      
      // Удаляем файл резервной копии
      await _deleteFile(draftId);
    } catch (e) {
      print('Ошибка удаления черновика: $e');
    }
  }

  /// Очистить все черновики старше определенного времени
  Future<void> cleanOldDrafts({Duration maxAge = const Duration(days: 30)}) async {
    try {
      final drafts = await getDrafts();
      final now = DateTime.now();
      final toDelete = <String>[];

      for (var entry in drafts.entries) {
        final savedAtStr = entry.value['saved_at'] as String?;
        if (savedAtStr != null) {
          final savedAt = DateTime.parse(savedAtStr);
          if (now.difference(savedAt) > maxAge) {
            toDelete.add(entry.key);
          }
        }
      }

      for (var id in toDelete) {
        await deleteDraft(id);
      }
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
