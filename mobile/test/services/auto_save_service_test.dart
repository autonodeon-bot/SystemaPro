import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:es_td_ngo_mobile/services/auto_save_service.dart';
import 'package:es_td_ngo_mobile/services/database_service.dart';

class _TempDocsPathProvider extends PathProviderPlatform {
  _TempDocsPathProvider(this._docsPath);
  final String _docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;
}

void main() {
  late PathProviderPlatform originalPathProvider;
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    originalPathProvider = PathProviderPlatform.instance;
  });

  setUp(() async {
    await DatabaseService.resetForTest();
    final dbPath = join(await getDatabasesPath(), 'systemapro.db');
    await deleteDatabase(dbPath);
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('auto_save_test_');
    PathProviderPlatform.instance = _TempDocsPathProvider(tempDir.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPathProvider;
    await DatabaseService.resetForTest();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AutoSaveService', () {
    test('queue keeps signed revisions, separate forms and only replaces matching drafts', () async {
      Map<String, dynamic> item(String id, String form, String status) => {
        'id': id, 'equipment_id': 'eq', 'assignment_id': 'job', 'status': status,
        'data': {'report_form_id': form}, 'timestamp': id,
      };
      await DatabaseService.enqueueInspection(item('signed', 'to-1', 'SIGNED'));
      await DatabaseService.enqueueInspection(item('other', 'to-12', 'DRAFT'));
      await Future.wait([
        DatabaseService.enqueueInspection(item('draft', 'to-1', 'DRAFT')),
        DatabaseService.enqueueInspection(item('independent', 'to-3', 'DRAFT')),
      ]);
      await DatabaseService.enqueueInspection(item('new', 'to-1', 'DRAFT'));
      expect((await DatabaseService.getPendingInspections()).map((e) => e['id']),
        unorderedEquals(['signed', 'other', 'independent', 'new']));
      await DatabaseService.recordInspectionSyncError(item('new', 'to-1', 'DRAFT'), 'Нет сети');
      final pending = await DatabaseService.getPendingInspections();
      expect(pending.singleWhere((e) => e['id'] == 'new')['sync_error'], 'Нет сети');
      await DatabaseService.recordInspectionSyncError({...item('new', 'to-1', 'DRAFT'), 'timestamp': 'old'}, 'Устаревшая ошибка');
      expect((await DatabaseService.getPendingInspections()).singleWhere((e) => e['id'] == 'new')['sync_attempts'], 1);
    });
    test('saveDraft записывает в БД и last_auto_save_time в prefs', () async {
      final service = AutoSaveService();
      await service.saveDraft(
        equipmentId: 'eq-99',
        checklistData: {'section': 'a'},
        assignmentId: 'asg-1',
      );

      final draft = await DatabaseService.getDraft(AutoSaveService.draftKey(equipmentId: 'eq-99', assignmentId: 'asg-1'));
      expect(draft, isNotNull);
      expect(draft!['equipment_id'], 'eq-99');
      expect(draft['assignment_id'], 'asg-1');
      expect((draft['checklist_data'] as Map)['section'], 'a');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_auto_save_time'), isNotNull);
    });

    test('saveDraft с inspectionId использует его как ключ черновика', () async {
      final service = AutoSaveService();
      await service.saveDraft(
        equipmentId: 'eq-1',
        checklistData: {},
        inspectionId: 'insp-fixed-id',
      );
      final d = await DatabaseService.getDraft('insp-fixed-id');
      expect(d, isNotNull);
    });

    test('getDraftForEquipment возвращает черновик по draft_equipmentId', () async {
      final service = AutoSaveService();
      await service.saveDraft(
        equipmentId: 'eq-42',
        checklistData: {'x': 1},
      );
      final found = await service.getDraftForEquipment('eq-42');
      expect(found, isNotNull);
      expect(found!['equipment_id'], 'eq-42');
    });

    test('getDrafts возвращает карту по id', () async {
      final service = AutoSaveService();
      await service.saveDraft(equipmentId: 'e1', checklistData: {});
      final map = await service.getDrafts();
      expect(map.containsKey('draft_e1'), true);
    });

    test('deleteDraft удаляет из БД', () async {
      final service = AutoSaveService();
      await service.saveDraft(equipmentId: 'e-del', checklistData: {});
      await service.deleteDraft('draft_e-del');
      expect(await DatabaseService.getDraft('draft_e-del'), isNull);
    });

    test('restoreFromBackup читает файл после saveDraft', () async {
      final service = AutoSaveService();
      await service.saveDraft(
        equipmentId: 'eq-backup',
        checklistData: {'v': 2},
      );
      final restored = await service.restoreFromBackup('draft_eq-backup');
      expect(restored, isNotNull);
      expect(restored!['equipment_id'], 'eq-backup');
    });

    test('cleanOldDrafts делегирует в DatabaseService', () async {
      final service = AutoSaveService();
      await service.saveDraft(equipmentId: 'e-old', checklistData: {});
      final db = await DatabaseService.database;
      final oldIso =
          DateTime.now().subtract(const Duration(days: 60)).toUtc().toIso8601String();
      await db.update(
        'drafts',
        {'updated_at': oldIso},
        where: 'id = ?',
        whereArgs: ['draft_e-old'],
      );

      await service.cleanOldDrafts(maxAge: const Duration(days: 30));
      expect(await DatabaseService.getDraft('draft_e-old'), isNull);
    });

    test('upload acknowledgement preserves new edits and other forms', () async {
      final sent = <String, dynamic>{'id': 'revision', 'equipment_id': 'eq', 'assignment_id': 'job',
        'timestamp': '2026-09-18T10:00:00', 'data': {'report_form_id': 'to-1'}};
      final edited = <String, dynamic>{...sent, 'timestamp': '2026-09-18T10:01:00'};
      await DatabaseService.savePendingInspection('revision', edited);
      for (final entry in {'old': 'to-1', 'other-form': 'to-12', 'new': 'to-1'}.entries) {
        await DatabaseService.saveDraft(entry.key, 'inspection', {
          'equipment_id': 'eq', 'assignment_id': 'job',
          'checklist_data': {'report_form_id': entry.value},
          'saved_at': entry.key == 'new' ? '2026-09-18T10:01:00' : '2026-09-18T09:59:00',
        });
      }
      await DatabaseService.acknowledgeInspectionUpload(sent);
      expect((await DatabaseService.getPendingInspections()).single['timestamp'], edited['timestamp']);
      expect(await DatabaseService.getDraft('old'), isNull);
      expect(await DatabaseService.getDraft('new'), isNotNull);
      expect(await DatabaseService.getDraft('other-form'), isNotNull);
      await DatabaseService.acknowledgeInspectionUpload(edited);
      expect(await DatabaseService.getPendingInspections(), isEmpty);
    });
  });
}
