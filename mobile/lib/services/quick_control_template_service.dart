import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quick_control_template_codes.dart';
import 'api_service.dart';

/// Загрузка и кэш шаблонов быстрого контроля с сервера.
class QuickControlTemplateService {
  static const _cachePrefix = 'qc_protocol_tpl_';

  final ApiService _api;

  QuickControlTemplateService({ApiService? api}) : _api = api ?? ApiService();

  Future<Map<String, dynamic>> getTemplate(String quickControlCode) async {
    try {
      final tpl = await _api.getQuickControlProtocolTemplate(quickControlCode);
      await _writeCache(quickControlCode, tpl);
      return tpl;
    } catch (_) {
      final cached = await _readCache(quickControlCode);
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Предзагрузка всех шаблонов (хаб быстрого контроля / синхронизация).
  Future<void> prefetchAll() async {
    for (final code in QuickControlTemplateCodes.all) {
      try {
        await getTemplate(code);
      } catch (_) {
        // отдельные шаблоны не блокируют остальные
      }
    }
  }

  Future<void> _writeCache(String code, Map<String, dynamic> tpl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachePrefix + code, jsonEncode(tpl));
  }

  Future<Map<String, dynamic>?> _readCache(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachePrefix + code);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }
}
