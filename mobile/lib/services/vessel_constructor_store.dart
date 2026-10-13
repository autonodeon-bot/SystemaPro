import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/vessel_geometry.dart';
import 'database_service.dart';

class VesselConstructorStore extends ChangeNotifier {
  VesselGeometry geometry;
  late final VesselEntity baseGeometry;
  final String draftKey;
  final List<VesselEntity> _undo = [], _redo = [];
  String? selection;
  int step = 0;
  String saveStatus = 'Изменений нет';
  Timer? _timer;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  VesselConstructorStore(this.geometry, this.draftKey) {
    baseGeometry = VesselGeometry.copy(geometry.data);
  }
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void command(void Function(VesselGeometry) action) {
    final before = VesselGeometry.copy(geometry.data);
    try {
      action(geometry);
    } catch (_) {
      geometry = VesselGeometry(before);
      rethrow;
    }
    _undo.add(before);
    if (_undo.length > 50) _undo.removeAt(0);
    _redo.clear();
    geometry.data['revision'] = (geometry.data['revision'] as num).toInt() + 1;
    changed();
  }

  void changed() {
    saveStatus = 'Сохраняется на устройстве…';
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), flush);
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(VesselGeometry.copy(geometry.data));
    final revision = (geometry.data['revision'] as num).toInt() + 1;
    geometry = VesselGeometry(_undo.removeLast());
    geometry.data['revision'] = revision;
    changed();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(VesselGeometry.copy(geometry.data));
    final revision = (geometry.data['revision'] as num).toInt() + 1;
    geometry = VesselGeometry(_redo.removeLast());
    geometry.data['revision'] = revision;
    changed();
  }

  Future<Map<String, dynamic>?> readDraft() =>
      DatabaseService.getDraft(draftKey);
  void restore(Map<String, dynamic> draft) {
    geometry = VesselGeometry.load(
        Map<String, dynamic>.from(draft['geometry'] as Map));
    selection = draft['selection'] as String?;
    step = (draft['step'] as num? ?? 0).toInt();
    saveStatus = 'Черновик восстановлен';
    notifyListeners();
  }

  Future<void> flush() {
    _timer?.cancel();
    final snapshot = {
      'geometry': VesselGeometry.copy(geometry.data),
      'base_geometry': baseGeometry,
      'selection': selection,
      'step': step,
      'saved_at': DateTime.now().toIso8601String()
    };
    _writes = _writes.catchError((_) {}).then((_) =>
        DatabaseService.saveDraft(draftKey, 'vessel_constructor', snapshot));
    return _writes.then((_) {
      saveStatus = 'Сохранено на устройстве';
      if (!_disposed) notifyListeners();
    }, onError: (Object error, StackTrace stack) {
      saveStatus = 'Не удалось сохранить черновик: $error';
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> discard() async {
    _timer?.cancel();
    await _writes.catchError((_) {});
    await DatabaseService.deleteDraft(draftKey);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
