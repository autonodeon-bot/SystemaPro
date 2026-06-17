import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/diagnostic_menu_config.dart';
import 'api_service.dart';

/// Загрузка и кэш редактируемого меню диагностики с сервера.
class DiagnosticMenuService {
  static const _cacheKey = 'diagnostic_menu_published_v1';
  static final DiagnosticMenuService instance = DiagnosticMenuService._();
  DiagnosticMenuService._();

  DiagnosticMenuConfig? _memory;
  final ApiService _api = ApiService();

  Future<DiagnosticMenuConfig> getConfig({bool forceRefresh = false}) async {
    if (!forceRefresh && _memory != null) return _memory!;

    try {
      final raw = await _api.getDiagnosticMenuPublished();
      final config = DiagnosticMenuConfig.fromJson(raw);
      _memory = config;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(raw));
      return config;
    } catch (_) {
      final cached = await _readCache();
      if (cached != null) {
        _memory = cached;
        return cached;
      }
    }
    _memory = DiagnosticMenuConfig.builtin();
    return _memory!;
  }

  Future<void> prefetch() => getConfig();

  Future<DiagnosticMenuConfig?> _readCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return DiagnosticMenuConfig.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }
}
