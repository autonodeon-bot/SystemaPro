import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyRecent = 'recent_assignments';
const int _maxRecent = 10;

class RecentItem {
  final String assignmentId;
  final String equipmentId;
  final String title;
  final DateTime openedAt;

  RecentItem({
    required this.assignmentId,
    required this.equipmentId,
    required this.title,
    required this.openedAt,
  });

  Map<String, dynamic> toJson() => {
        'assignment_id': assignmentId,
        'equipment_id': equipmentId,
        'title': title,
        'opened_at': openedAt.toIso8601String(),
      };

  factory RecentItem.fromJson(Map<String, dynamic> json) {
    return RecentItem(
      assignmentId: json['assignment_id'] as String? ?? '',
      equipmentId: json['equipment_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Задание',
      openedAt: json['opened_at'] != null
          ? DateTime.tryParse(json['opened_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class RecentService {
  Future<List<RecentItem>> getRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyRecent);
      if (raw == null || raw.isEmpty) return [];
      final list = json.decode(raw) as List<dynamic>?;
      if (list == null) return [];
      return list
          .map((e) => RecentItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addRecent({
    required String assignmentId,
    required String equipmentId,
    required String title,
  }) async {
    try {
      var list = await getRecent();
      final newItem = RecentItem(
        assignmentId: assignmentId,
        equipmentId: equipmentId,
        title: title,
        openedAt: DateTime.now(),
      );
      list = list.where((e) => e.assignmentId != assignmentId).toList();
      list.insert(0, newItem);
      if (list.length > _maxRecent) {
        list = list.take(_maxRecent).toList();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _keyRecent,
        json.encode(list.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }
}
