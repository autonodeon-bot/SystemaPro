import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:es_td_ngo_mobile/services/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseService.resetForTest();
    final dbPath = join(await getDatabasesPath(), 'systemapro.db');
    await deleteDatabase(dbPath);
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
  });

  group('DatabaseService — assignments', () {
    test('saveAssignments и getAssignments', () async {
      final list = [
        {'id': 'a1', 'status': 'PENDING'},
        {'id': 'a2', 'status': 'COMPLETED'},
      ];
      await DatabaseService.saveAssignments(list);
      final loaded = await DatabaseService.getAssignments();
      expect(loaded.length, 2);
      expect(loaded[0]['id'], 'a1');
      expect(loaded[1]['status'], 'COMPLETED');
    });
  });

  group('DatabaseService — equipment', () {
    test('saveEquipment и getEquipment', () async {
      final list = [
        {'id': 'e1', 'name': 'Сосуд'},
      ];
      await DatabaseService.saveEquipment(list);
      final loaded = await DatabaseService.getEquipment();
      expect(loaded.length, 1);
      expect(loaded[0]['name'], 'Сосуд');
    });
  });

  group('DatabaseService — pending_inspections', () {
    test('savePendingInspection, getPendingInspections, markInspectionSynced', () async {
      await DatabaseService.savePendingInspection('insp-1', {'field': 'v'});
      final pending = await DatabaseService.getPendingInspections();
      expect(pending.length, 1);
      expect(pending[0]['id'], 'insp-1');
      expect(pending[0]['field'], 'v');

      await DatabaseService.markInspectionSynced('insp-1');
      final after = await DatabaseService.getPendingInspections();
      expect(after, isEmpty);
    });
  });

  group('DatabaseService — sync_metadata', () {
    test('setSyncMeta и getSyncMeta', () async {
      await DatabaseService.setSyncMeta('last_sync', '2025-01-01');
      expect(await DatabaseService.getSyncMeta('last_sync'), '2025-01-01');
      expect(await DatabaseService.getSyncMeta('missing'), isNull);
    });
  });

  group('DatabaseService — engineers', () {
    test('saveEngineers пропускает запись без id', () async {
      await DatabaseService.saveEngineers([
        {'name': 'no id'},
      ]);
      expect(await DatabaseService.getEngineers(), isEmpty);
    });

    test('saveEngineers, getEngineers, clearEngineers', () async {
      await DatabaseService.saveEngineers([
        {'id': 'eng-1', 'full_name': 'Иванов'},
      ]);
      final rows = await DatabaseService.getEngineers();
      expect(rows.length, 1);
      expect(rows[0]['full_name'], 'Иванов');
      await DatabaseService.clearEngineers();
      expect(await DatabaseService.getEngineers(), isEmpty);
    });
  });

  group('DatabaseService — verification_equipment', () {
    test('saveVerificationEquipment и clearVerificationEquipment', () async {
      await DatabaseService.saveVerificationEquipment([
        {'id': 've-1', 'name': 'Прибор'},
      ]);
      final rows = await DatabaseService.getVerificationEquipment();
      expect(rows.length, 1);
      await DatabaseService.clearVerificationEquipment();
      expect(await DatabaseService.getVerificationEquipment(), isEmpty);
    });
  });

  group('DatabaseService — opos', () {
    test('saveOpos и clearOpos', () async {
      await DatabaseService.saveOpos([
        {'id': 'opo-1', 'code': 'OPO-1'},
      ]);
      final rows = await DatabaseService.getOpos();
      expect(rows.length, 1);
      await DatabaseService.clearOpos();
      expect(await DatabaseService.getOpos(), isEmpty);
    });
  });

  group('DatabaseService — opo_surveys', () {
    test('saveOpoSurvey, getOpoSurveys, deleteOpoSurvey, clearOpoSurveys', () async {
      await DatabaseService.saveOpoSurvey('opo-x', {'q': 1});
      final list = await DatabaseService.getOpoSurveys();
      expect(list.length, 1);
      expect(list[0]['opo_id'], 'opo-x');
      expect(list[0]['q'], 1);

      await DatabaseService.deleteOpoSurvey('opo-x');
      expect(await DatabaseService.getOpoSurveys(), isEmpty);

      await DatabaseService.saveOpoSurvey('o2', {});
      await DatabaseService.clearOpoSurveys();
      expect(await DatabaseService.getOpoSurveys(), isEmpty);
    });
  });

  group('DatabaseService — drafts', () {
    test('saveDraft, getDraft, deleteDraft', () async {
      await DatabaseService.saveDraft('d1', 'inspection', {'k': 'v'});
      final d = await DatabaseService.getDraft('d1');
      expect(d, isNotNull);
      expect(d!['k'], 'v');
      await DatabaseService.deleteDraft('d1');
      expect(await DatabaseService.getDraft('d1'), isNull);
    });

    test('getAllDrafts сортирует по updated_at DESC', () async {
      await DatabaseService.saveDraft('old', 't', {'n': 1});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await DatabaseService.saveDraft('new', 't', {'n': 2});
      final all = await DatabaseService.getAllDrafts();
      expect(all.length, 2);
      expect(all[0]['id'], 'new');
      expect(all[1]['id'], 'old');
    });

    test('clearDrafts', () async {
      await DatabaseService.saveDraft('x', 't', {});
      await DatabaseService.clearDrafts();
      expect(await DatabaseService.getAllDrafts(), isEmpty);
    });

    test('clearOldDrafts удаляет устаревшие записи', () async {
      await DatabaseService.saveDraft('fresh', 't', {'a': 1});
      final db = await DatabaseService.database;
      final oldIso =
          DateTime.now().subtract(const Duration(days: 90)).toUtc().toIso8601String();
      await db.rawInsert(
        'INSERT OR REPLACE INTO drafts (id, screen_type, data, updated_at) VALUES (?, ?, ?, ?)',
        ['stale', 't', jsonEncode({'a': 2}), oldIso],
      );

      await DatabaseService.clearOldDrafts(maxAge: const Duration(days: 30));
      final ids = (await DatabaseService.getAllDrafts()).map((e) => e['id']).toList();
      expect(ids, contains('fresh'));
      expect(ids, isNot(contains('stale')));
    });
  });

  group('DatabaseService — clearAllCaches', () {
    test('очищает кэш-таблицы', () async {
      await DatabaseService.saveAssignments([{'id': 'a'}]);
      await DatabaseService.saveEquipment([{'id': 'e'}]);
      await DatabaseService.setSyncMeta('k', 'v');
      await DatabaseService.saveEngineers([{'id': 'en'}]);

      await DatabaseService.clearAllCaches();

      expect(await DatabaseService.getAssignments(), isEmpty);
      expect(await DatabaseService.getEquipment(), isEmpty);
      expect(await DatabaseService.getEngineers(), isEmpty);
      expect(await DatabaseService.getSyncMeta('k'), isNull);
    });
  });
}
