import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/drawing_template.dart';
import '../models/equipment.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'database_service.dart';

/// Сервис работы с шаблонами чертежей оборудования (П.2 ТЗ 2026-04).
///
/// Ключевые возможности:
///   * загрузка списка шаблонов с сервера (fetchForEquipment)
///   * офлайн-кэш: файл PNG/JPG в getApplicationDocumentsDirectory()
///     и мета-данные в sqflite (таблица drawing_templates)
///   * дельта-синхронизация (syncDelta) — скачивает только изменённые
///     шаблоны, сравнивая version с локальным кэшем
///   * pre-fetch: [prefetchForEquipmentIds] — предзагрузка перед выездом
class DrawingTemplatesService {
  static const _syncSinceKey = 'drawing_templates_last_sync';

  static String get _baseUrl => ApiServiceBase.baseUrl;
  static const Duration _timeout = Duration(seconds: 60);

  /// Относительный каталог для файлов шаблонов в documents dir.
  static const String _cacheFolder = 'drawing_templates';

  final ApiService _api = const ApiService();
  final AuthService _auth = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    await _api.ensureValidToken();
    final token = await _auth.getToken();
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  // ── Кэш файлов ─────────────────────────────────────────────────────────

  static Future<Directory> _cacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _cacheFolder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _localFileName(String templateId, int version, String mimeType) {
    final ext = mimeType.contains('png') ? 'png' : 'jpg';
    return '${templateId}_v$version.$ext';
  }

  /// Путь к локальному файлу (без гарантии его существования).
  Future<String> _localFilePathFor(String templateId, int version, String mimeType) async {
    final dir = await _cacheDir();
    return p.join(dir.path, _localFileName(templateId, version, mimeType));
  }

  /// Удаляет старые версии файла этого шаблона (оставляет актуальную).
  Future<void> _cleanupOldVersions(String templateId, int keepVersion) async {
    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) return;
      final prefix = '${templateId}_v';
      await for (final f in dir.list()) {
        if (f is File) {
          final name = p.basename(f.path);
          if (name.startsWith(prefix) && !name.contains('v$keepVersion.')) {
            try { await f.delete(); } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  // ── Загрузка изображения ───────────────────────────────────────────────

  Future<String?> downloadImage(String templateId, int version, String mimeType) async {
    try {
      final url = Uri.parse('$_baseUrl/api/drawing-templates/$templateId/image?v=$version');
      final headers = await _authHeaders();
      final res = await http.get(url, headers: {...headers, 'Content-Type': 'image/*'}).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final localPath = await _localFilePathFor(templateId, version, mimeType);
      final file = File(localPath);
      await file.writeAsBytes(res.bodyBytes);
      await _cleanupOldVersions(templateId, version);
      return localPath;
    } catch (e) {
      // print — допустимо в разработке, продакшн-логирование через logger сервиса
      // ignore: avoid_print
      print('DrawingTemplatesService.downloadImage error for $templateId: $e');
      return null;
    }
  }

  // ── Работа со списком шаблонов ──────────────────────────────────────────

  /// Загрузить (со свежим скачиванием файла, если надо) шаблоны для конкретной
  /// единицы оборудования. Если сети нет — вернёт кэш из sqflite.
  Future<List<DrawingTemplate>> fetchForEquipment({
    required Equipment equipment,
    bool downloadImages = true,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/api/drawing-templates?equipment_id=${equipment.id}&active_only=true',
      );
      final headers = await _authHeaders();
      final res = await http.get(url, headers: headers).timeout(_timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = (body is Map && body['items'] is List) ? body['items'] as List : const <dynamic>[];
        final results = <DrawingTemplate>[];
        for (final item in list) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          final t = DrawingTemplate.fromJson(m);

          String? localPath;
          if (downloadImages) {
            final cached = await DatabaseService.getDrawingTemplate(t.id);
            if (cached != null &&
                (cached['version'] as int? ?? 0) == t.version &&
                cached['local_image_path'] is String &&
                await File(cached['local_image_path'] as String).exists()) {
              localPath = cached['local_image_path'] as String;
            } else {
              localPath = await downloadImage(t.id, t.version, t.mimeType ?? 'image/png');
            }
          }

          // Подгружаем детали (с точками) если их нет в ответе списка
          DrawingTemplate full = t;
          if (t.points.isEmpty) {
            final detail = await _fetchDetail(t.id);
            if (detail != null) full = detail.copyWith(localImagePath: localPath);
          } else {
            full = t.copyWith(localImagePath: localPath);
          }

          await DatabaseService.saveDrawingTemplate(
            id: full.id,
            data: full.toJson(),
            version: full.version,
            localImagePath: localPath,
            equipmentId: full.equipmentId,
            equipmentTypeId: full.equipmentTypeId,
          );
          results.add(full);
        }
        return results;
      }
      // fallback: offline cache
      return _readCacheForEquipment(equipment);
    } catch (e) {
      // ignore: avoid_print
      print('DrawingTemplatesService.fetchForEquipment error: $e');
      return _readCacheForEquipment(equipment);
    }
  }

  Future<DrawingTemplate?> _fetchDetail(String templateId) async {
    try {
      final headers = await _authHeaders();
      final res = await http
          .get(Uri.parse('$_baseUrl/api/drawing-templates/$templateId'), headers: headers)
          .timeout(_timeout);
      if (res.statusCode == 200) {
        return DrawingTemplate.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return null;
  }

  Future<List<DrawingTemplate>> _readCacheForEquipment(Equipment equipment) async {
    try {
      final eqTypeId = _equipmentTypeId(equipment);
      final rows = await DatabaseService.getDrawingTemplatesForEquipment(
        equipmentId: equipment.id,
        equipmentTypeId: eqTypeId,
      );
      final seen = <String>{};
      final list = <DrawingTemplate>[];
      for (final r in rows) {
        final id = r['id']?.toString();
        if (id == null || seen.contains(id)) continue;
        seen.add(id);
        final raw = r['data'];
        final decoded = raw is String ? jsonDecode(raw) : raw;
        if (decoded is Map) {
          list.add(DrawingTemplate.fromJson(
            Map<String, dynamic>.from(decoded),
            localImagePath: r['local_image_path']?.toString(),
          ));
        }
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  String? _equipmentTypeId(Equipment equipment) => equipment.typeId;

  // ── Дельта-синхронизация (вызывается из SyncService) ──────────────────

  /// Сравнивает server-state с локальным и докачивает/обновляет шаблоны.
  /// Возвращает количество обновлённых шаблонов.
  Future<int> syncDelta({List<String>? equipmentIds}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final since = prefs.getString(_syncSinceKey);

      var url = '$_baseUrl/api/drawing-templates/sync';
      final query = <String, String>{};
      if (since != null) query['since'] = since;
      if (equipmentIds != null && equipmentIds.isNotEmpty) {
        query['equipment_ids'] = equipmentIds.join(',');
      }
      if (query.isNotEmpty) {
        url =
            '$url?${query.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
      }

      final headers = await _authHeaders();
      final res = await http.get(Uri.parse(url), headers: headers).timeout(_timeout);
      if (res.statusCode != 200) return 0;

      final body = jsonDecode(res.body);
      final items = (body is Map && body['items'] is List) ? body['items'] as List : const <dynamic>[];
      final serverTime = (body is Map && body['server_time'] is String) ? body['server_time'] as String : null;

      int updated = 0;
      for (final it in items) {
        if (it is! Map) continue;
        final m = Map<String, dynamic>.from(it);
        final id = m['id']?.toString();
        if (id == null) continue;
        final serverVersion = (m['version'] is int) ? m['version'] as int : int.tryParse('${m['version']}') ?? 1;

        final cached = await DatabaseService.getDrawingTemplate(id);
        final localVersion = cached != null ? (cached['version'] as int? ?? 0) : -1;
        if (localVersion == serverVersion && cached != null && cached['local_image_path'] != null) {
          continue;
        }

        // Нужно дотянуть детали + скачать изображение
        final detail = await _fetchDetail(id);
        if (detail == null) continue;

        String? localPath = await downloadImage(
          detail.id,
          detail.version,
          detail.mimeType ?? 'image/png',
        );

        await DatabaseService.saveDrawingTemplate(
          id: detail.id,
          data: detail.toJson(),
          version: detail.version,
          localImagePath: localPath,
          equipmentId: detail.equipmentId,
          equipmentTypeId: detail.equipmentTypeId,
        );
        updated++;
      }

      if (serverTime != null) {
        await prefs.setString(_syncSinceKey, serverTime);
      }
      return updated;
    } catch (e) {
      // ignore: avoid_print
      print('DrawingTemplatesService.syncDelta error: $e');
      return 0;
    }
  }

  // ── Pre-fetch перед выездом ───────────────────────────────────────────

  /// Предзагрузка шаблонов для списка оборудования (например, в рамках
  /// назначения на инженера). Вызывать после логина/входа в assignments.
  Future<int> prefetchForEquipmentIds(List<String> equipmentIds) async {
    if (equipmentIds.isEmpty) return 0;
    return syncDelta(equipmentIds: equipmentIds);
  }

  // ── Офлайн-чтение только из кэша ──────────────────────────────────────

  Future<List<DrawingTemplate>> getOfflineForEquipment(Equipment equipment) async {
    return _readCacheForEquipment(equipment);
  }

  Future<DrawingTemplate?> getOfflineById(String id) async {
    final cached = await DatabaseService.getDrawingTemplate(id);
    if (cached == null) return null;
    final raw = cached['data'];
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is Map) {
      return DrawingTemplate.fromJson(
        Map<String, dynamic>.from(decoded),
        localImagePath: cached['local_image_path']?.toString(),
      );
    }
    return null;
  }
}
