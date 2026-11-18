import 'dart:convert';

/// Page navigation and a fresh GPS fix are not a new revision of a completed document.
String inspectionContentSnapshot(Map<String, dynamic> data) {
  final copy = Map<String, dynamic>.from(data)..remove('gps_coordinates');
  if (copy['additional_data'] is Map) {
    copy['additional_data'] =
        Map<String, dynamic>.from(copy['additional_data'] as Map)
          ..remove('current_page')
          ..remove('gps_coordinates')
          ..remove('_client_document_id');
    final extra = copy['additional_data'] as Map;
    for (final key in ['manual_verification_equipment', 'object_photos']) {
      if (extra[key] is List && (extra[key] as List).isEmpty) extra.remove(key);
    }
  }
  dynamic ordered(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return {for (final key in keys) key: ordered(value[key])};
    }
    if (value is List) return value.map(ordered).toList();
    return value;
  }

  return jsonEncode(ordered(copy));
}

/// Find the saved document for this assignment, not another inspection of the vessel.
Map<String, dynamic>? inspectionToResume(List<Map<String, dynamic>> records,
    {String? inspectionId, String? assignmentId, String? reportFormId}) {
  final candidates = records.where((item) {
    if (item['is_archived'] == true || item['is_deleted'] == true) return false;
    if (inspectionId != null) return item['id']?.toString() == inspectionId;
    if (assignmentId == null) return false;
    final data = item['data'] is Map ? item['data'] as Map : {};
    return (item['assignment_id'] ?? data['assignment_id'])?.toString() ==
            assignmentId &&
        (reportFormId == null || data['report_form_id'] == reportFormId);
  }).toList();
  candidates.sort((a, b) {
    // Legacy autosaves sometimes created a sparse draft after a complete document.
    final signed = (b['status'] == 'SIGNED' ? 1 : 0)
        .compareTo(a['status'] == 'SIGNED' ? 1 : 0);
    if (signed != 0) return signed;
    return (b['revision'] ?? b['created_at'] ?? '')
        .toString()
        .compareTo((a['revision'] ?? a['created_at'] ?? '').toString());
  });
  return candidates.isEmpty ? null : candidates.first;
}
