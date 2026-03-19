import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/services/sync_service.dart';

void main() {
  group('SyncResult', () {
    test('значения по умолчанию', () {
      final result = SyncResult();
      expect(result.success, false);
      expect(result.syncedCount, 0);
      expect(result.failedCount, 0);
      expect(result.message, isNull);
      expect(result.error, isNull);
      expect(result.lastFailureReason, isNull);
    });

    test('изменение полей', () {
      final result = SyncResult();
      result.success = true;
      result.syncedCount = 5;
      result.failedCount = 2;
      result.message = 'Синхронизация завершена';
      result.error = null;

      expect(result.success, true);
      expect(result.syncedCount, 5);
      expect(result.failedCount, 2);
      expect(result.message, 'Синхронизация завершена');
    });
  });

  group('SyncResultFull', () {
    test('значения по умолчанию', () {
      final result = SyncResultFull();
      expect(result.success, false);
      expect(result.uploaded, 0);
      expect(result.uploadFailed, 0);
      expect(result.updatedAssignments, 0);
      expect(result.error, isNull);
      expect(result.deltaSyncError, isNull);
    });

    test('изменение полей', () {
      final result = SyncResultFull();
      result.success = true;
      result.uploaded = 3;
      result.uploadFailed = 1;
      result.updatedAssignments = 10;

      expect(result.success, true);
      expect(result.uploaded, 3);
      expect(result.uploadFailed, 1);
      expect(result.updatedAssignments, 10);
    });
  });

  group('LocalAssignmentInspectionState', () {
    test('none() создаёт пустое состояние', () {
      final state = LocalAssignmentInspectionState.none();
      expect(state.hasDraft, false);
      expect(state.hasSigned, false);
    });

    test('copyWith обновляет hasDraft', () {
      final state = LocalAssignmentInspectionState.none();
      final updated = state.copyWith(hasDraft: true);
      expect(updated.hasDraft, true);
      expect(updated.hasSigned, false);
    });

    test('copyWith обновляет hasSigned', () {
      final state = LocalAssignmentInspectionState.none();
      final updated = state.copyWith(hasSigned: true);
      expect(updated.hasDraft, false);
      expect(updated.hasSigned, true);
    });

    test('copyWith обновляет оба поля', () {
      final state = LocalAssignmentInspectionState.none();
      final updated = state.copyWith(hasDraft: true, hasSigned: true);
      expect(updated.hasDraft, true);
      expect(updated.hasSigned, true);
    });

    test('copyWith без параметров сохраняет значения', () {
      final state = LocalAssignmentInspectionState(
        hasDraft: true,
        hasSigned: false,
      );
      final copy = state.copyWith();
      expect(copy.hasDraft, true);
      expect(copy.hasSigned, false);
    });

    test('конструктор с именованными параметрами', () {
      final state = LocalAssignmentInspectionState(
        hasDraft: true,
        hasSigned: true,
      );
      expect(state.hasDraft, true);
      expect(state.hasSigned, true);
    });
  });
}
