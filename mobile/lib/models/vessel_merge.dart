import 'dart:convert';
import 'vessel_geometry.dart';

class VesselConflict {
  final String key;
  final String? id;
  final dynamic local, remote;
  VesselConflict(this.key, this.id, this.local, this.remote);
}

class VesselMerge {
  final VesselEntity merged;
  final List<VesselConflict> conflicts = [];
  static bool same(dynamic a, dynamic b) => jsonEncode(a) == jsonEncode(b);
  VesselMerge(VesselEntity base, VesselEntity local, VesselEntity remote)
      : merged = VesselGeometry.copy(remote) {
    if (local['model_id'] != remote['model_id']) {
      throw StateError('Нельзя объединить разные модели сосудов');
    }
    for (final key in {...base.keys, ...local.keys, ...remote.keys}) {
      if (['revision', 'base_revision', 'operation_id', 'diagnostics'].contains(key)) continue;
      final b = base[key], l = local[key], r = remote[key];
      if (same(l, b)) continue;
      if (same(r, b) || same(l, r)) { merged[key] = l; continue; }
      if (l is List && r is List && [...l, ...r].every((e) => e is Map && e['id'] != null)) {
        final bm = {for (final e in (b is List ? b : [])) e['id']: e};
        final lm = {for (final e in l) e['id']: e}, rm = {for (final e in r) e['id']: e};
        final result = <dynamic>[];
        for (final id in {...rm.keys, ...lm.keys, ...bm.keys}) {
          final be = bm[id], le = lm[id], re = rm[id];
          dynamic chosen = re;
          if (same(le, be)) { chosen = re; }
          else if (same(re, be) || same(le, re)) { chosen = le; }
          else { conflicts.add(VesselConflict(key, id as String, le, re)); }
          if (chosen != null) result.add(chosen);
        }
        merged[key] = result;
      } else { conflicts.add(VesselConflict(key, null, l, r)); }
    }
    merged['base_revision'] = remote['revision'];
    final l = local['revision'] as int, r = remote['revision'] as int;
    merged['revision'] = (l > r ? l : r) + 1;
    merged['operation_id'] = VesselGeometry.id();
  }
  void choose(VesselConflict conflict, bool useLocal) {
    final value = useLocal ? conflict.local : conflict.remote;
    if (conflict.id != null) {
      final list = merged[conflict.key] as List;
      final index = list.indexWhere((e) => e['id'] == conflict.id);
      if (index >= 0) { if (value == null) { list.removeAt(index); } else { list[index] = value; } }
      else if (value != null) { list.add(value); }
    } else { merged[conflict.key] = value; }
    conflicts.remove(conflict);
  }
}
