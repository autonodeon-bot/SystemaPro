import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Вид оборудования конструктора схем (= форма ТО to-N).
class SchemeEquipmentKind {
  final String code;
  final String formId;
  final String title;
  final String group;
  final String family;
  final String? familyTitle;
  final String category;
  final Map<String, dynamic> defaults;

  const SchemeEquipmentKind({
    required this.code,
    required this.formId,
    required this.title,
    required this.group,
    required this.family,
    this.familyTitle,
    required this.category,
    this.defaults = const {},
  });

  factory SchemeEquipmentKind.fromJson(Map<String, dynamic> json) {
    final rawDefaults = json['defaults'];
    return SchemeEquipmentKind(
      code: (json['code'] ?? '').toString(),
      formId: (json['form_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      group: (json['group'] ?? 'прочее').toString(),
      family: (json['family'] ?? 'generic').toString(),
      familyTitle: json['family_title']?.toString(),
      category: (json['category'] ?? 'other').toString(),
      defaults: rawDefaults is Map
          ? Map<String, dynamic>.from(rawDefaults)
          : const {},
    );
  }
}

/// Каталог 44 форм ТО: API → fallback на локальный JSON.
class SchemeEquipmentCatalog {
  SchemeEquipmentCatalog._();
  static final SchemeEquipmentCatalog instance = SchemeEquipmentCatalog._();

  List<SchemeEquipmentKind> _items = const [];
  List<String> _groups = const [];
  bool _loaded = false;

  List<SchemeEquipmentKind> get items => _items;
  List<String> get groups => _groups;
  int get formsCount => _items.map((e) => e.formId).toSet().length;

  Future<List<SchemeEquipmentKind>> ensureLoaded() async {
    if (_loaded && _items.isNotEmpty) return _items;
    // 1) API
    try {
      final token = await AuthService().getToken();
      if (token != null && token.isNotEmpty) {
        final uri = Uri.parse('${ApiService.baseUrl}/api/vessel-scheme/kinds');
        final res = await http
            .get(uri, headers: {'Authorization': 'Bearer $token'})
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          if (data is Map) {
            _parsePayload(Map<String, dynamic>.from(data));
            if (_items.length >= 40) {
              _loaded = true;
              return _items;
            }
          }
        }
      }
    } catch (_) {
      /* fallback */
    }
    // 2) Asset
    final raw =
        await rootBundle.loadString('assets/scheme_equipment_kinds.json');
    final data = jsonDecode(raw);
    if (data is Map) {
      _parsePayload(Map<String, dynamic>.from(data));
    }
    _loaded = true;
    return _items;
  }

  void _parsePayload(Map<String, dynamic> data) {
    final list = data['items'];
    if (list is List) {
      _items = list
          .whereType<Map>()
          .map((e) => SchemeEquipmentKind.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.code.isNotEmpty)
          .toList();
    }
    final g = data['groups'];
    if (g is List) {
      _groups = g.map((e) => e.toString()).toList();
    }
  }

  SchemeEquipmentKind? findByCodeOrForm(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.trim().toLowerCase().replaceAll('-', '_');
    for (final k in _items) {
      if (k.code == s) return k;
      if (k.formId.toLowerCase() == raw.trim().toLowerCase()) return k;
      if (k.formId.toLowerCase() == 'to-$s') return k;
    }
    // type code VESSEL → vessel
    for (final k in _items) {
      if (k.code == s.replaceAll(' ', '_')) return k;
    }
    return null;
  }
}
