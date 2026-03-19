import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/assignment.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../services/location_service.dart';

// ─── Service providers ───────────────────────────────────────────────────────

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final syncServiceProvider = Provider<SyncService>((ref) => SyncService());

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

// ─── State providers ─────────────────────────────────────────────────────────

final assignmentsProvider =
    StateNotifierProvider<AssignmentsNotifier, AsyncValue<List<Assignment>>>((ref) {
  return AssignmentsNotifier(
    ref.read(apiServiceProvider),
    ref.read(syncServiceProvider),
  );
});

class AssignmentsNotifier extends StateNotifier<AsyncValue<List<Assignment>>> {
  final ApiService _apiService;
  final SyncService _syncService;

  AssignmentsNotifier(this._apiService, this._syncService)
      : super(const AsyncValue.loading());

  Future<void> loadAssignments() async {
    state = const AsyncValue.loading();
    try {
      final assignments = await _apiService.getAssignments();
      await _syncService.saveAssignmentsOffline(assignments);
      state = AsyncValue.data(assignments);
    } catch (e, st) {
      // Фолбэк на офлайн-кэш
      try {
        final offline = await _syncService.getOfflineAssignments();
        state = AsyncValue.data(offline);
      } catch (_) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> refresh() async {
    await loadAssignments();
  }
}

/// Провайдер количества ожидающих отправки обследований
final pendingInspectionsCountProvider = FutureProvider<int>((ref) async {
  final syncService = ref.read(syncServiceProvider);
  final pending = await syncService.getPendingInspections();
  return pending.length;
});

/// Провайдер статуса подключения к серверу
final connectionStatusProvider = FutureProvider<bool>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.checkConnection();
});
