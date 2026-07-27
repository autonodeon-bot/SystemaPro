import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Автоподстановка последних значений инженера (исполнители, организация, приборы).
class LastValuesService {
  static const _keyOrg = 'last_inspection_organization';
  static const _keyExecutors = 'last_inspection_executors';
  static const _keyDevices = 'last_inspection_devices';

  Future<void> save({
    String? organization,
    String? executors,
    String? devices,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (organization != null && organization.trim().isNotEmpty) {
      await prefs.setString(_keyOrg, organization.trim());
    }
    if (executors != null && executors.trim().isNotEmpty) {
      await prefs.setString(_keyExecutors, executors.trim());
    }
    if (devices != null && devices.trim().isNotEmpty) {
      await prefs.setString(_keyDevices, devices.trim());
    }
  }

  Future<Map<String, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      if ((prefs.getString(_keyOrg) ?? '').isNotEmpty)
        'organization': prefs.getString(_keyOrg)!,
      if ((prefs.getString(_keyExecutors) ?? '').isNotEmpty)
        'executors': prefs.getString(_keyExecutors)!,
      if ((prefs.getString(_keyDevices) ?? '').isNotEmpty)
        'devices': prefs.getString(_keyDevices)!,
    };
  }

  /// Сохранить снимок шапки протокола для «создать на основе».
  Future<void> saveProtocolTemplateSnapshot(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_protocol_snapshot', json.encode(data));
  }

  Future<Map<String, dynamic>?> loadProtocolTemplateSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('last_protocol_snapshot');
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(json.decode(raw) as Map);
    } catch (_) {
      return null;
    }
  }
}
