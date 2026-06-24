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

// ─── State providers (Riverpod 3.x) ──────────────────────────────────────────

final assignmentsProvider =
    AsyncNotifierProvider<AssignmentsNotifier, List<Assignment>>(
  AssignmentsNotifier.new,
);

class AssignmentsNotifier extends AsyncNotifier<List<Assignment>> {
  late final ApiService _apiService;
  late final SyncService _syncService;

  @override
  Future<List<Assignment>> build() async {
    _apiService = ref.read(apiServiceProvider);
    _syncService = ref.read(syncServiceProvider);
    return _loadAssignments();
  }

  Future<List<Assignment>> _loadAssignments() async {
    try {
      final assignments = await _apiService.getAssignments();
      await _syncService.saveAssignmentsOffline(assignments);
      return assignments;
    } catch (e) {
      try {
        return await _syncService.getOfflineAssignments();
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_loadAssignments);
  }
}

/// Провайдер количества ожидающих отправки обследований
final pendingInspectionsCountProvider = FutureProvider<int>((ref) async {
  final syncService = ref.read(syncServiceProvider);
  final pending = await syncService.getPendingInspections();
  final standalone = await syncService.getPendingStandaloneProtocols();
  return pending.length + standalone.length;
});

/// Провайдер статуса подключения к серверу
final connectionStatusProvider = FutureProvider<bool>((ref) async {
  final api = ref.read(apiServiceProvider);
  return api.checkConnection();
});
