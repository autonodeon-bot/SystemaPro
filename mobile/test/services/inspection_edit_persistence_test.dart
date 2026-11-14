import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';
import 'package:es_td_ngo_mobile/services/auto_save_service.dart';
import 'package:es_td_ngo_mobile/services/database_service.dart';
import 'package:es_td_ngo_mobile/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await DatabaseService.resetForTest();
    await deleteDatabase(join(await getDatabasesPath(), 'systemapro.db'));
  });
  tearDown(() async => DatabaseService.resetForTest());

  test(
      'edits of two inspections of the same vessel retain separate queue records',
      () async {
    final sync = SyncService();
    for (final id in ['server-a', 'server-b']) {
      await sync.saveInspectionOffline(
          equipmentId: 'vessel',
          inspectionId: id,
          checklist: VesselChecklist()
            ..reportFormId = 'to-1'
            ..vesselName = id,
          inspectionDate: '2026-11-13T10:00:00Z');
    }
    expect((await sync.getPendingInspections()).length, 2);
    final a = await sync.getLatestPendingInspection(
        equipmentId: 'vessel', inspectionId: 'server-a', reportFormId: 'to-1');
    expect(a?['data']['vessel_name'], 'server-a');
    expect(
        await sync.getLatestPendingInspection(
            equipmentId: 'vessel', reportFormId: 'to-1'),
        isNull);
  });
  test('successful sync never removes another inspection draft', () async {
    final now = DateTime.now();
    for (final id in ['server-a', 'server-b']) {
      await DatabaseService.saveDraft(id, 'inspection', {
        'id': id,
        'inspection_id': id,
        'equipment_id': 'vessel',
        'saved_at': now.subtract(const Duration(seconds: 1)).toIso8601String(),
        'checklist_data': {'report_form_id': 'to-1', 'vessel_name': id}
      });
    }
    await DatabaseService.acknowledgeInspectionUpload({
      'id': 'queue-a',
      'inspection_id': 'server-a',
      'equipment_id': 'vessel',
      'timestamp': now.toIso8601String(),
      'data': {'report_form_id': 'to-1'}
    });
    expect(await DatabaseService.getDraft('server-a'), isNull);
    expect(
        (await AutoSaveService().getDraftForEquipment('vessel',
            inspectionId: 'server-b',
            reportFormId: 'to-1'))?['checklist_data']['vessel_name'],
        'server-b');
  });
  test('edits saved during upload survive and follow the acknowledged revision',
      () async {
    final sentAt = DateTime.now().toUtc();
    final uploaded = <String, dynamic>{
      'id': 'queue-a',
      'inspection_id': 'server-a',
      'equipment_id': 'vessel',
      'source_revision': 'old',
      'timestamp': sentAt.toIso8601String(),
      'data': {'report_form_id': 'to-1', 'vessel_name': 'uploaded'}
    };
    await DatabaseService.enqueueInspection({
      ...uploaded,
      'timestamp': sentAt.add(const Duration(seconds: 1)).toIso8601String(),
      'data': {'report_form_id': 'to-1', 'vessel_name': 'newer edit'}
    });
    await DatabaseService.saveDraft('server-a', 'inspection', {
      'id': 'server-a',
      'inspection_id': 'server-a',
      'equipment_id': 'vessel',
      'source_revision': 'old',
      'saved_at': sentAt.add(const Duration(seconds: 2)).toIso8601String(),
      'checklist_data': {'report_form_id': 'to-1', 'vessel_name': 'newer draft'}
    });
    await DatabaseService.acknowledgeInspectionUpload(uploaded,
        serverRevision: 'new');
    final pending = (await SyncService().getPendingInspections()).single;
    expect(pending['data']['vessel_name'], 'newer edit');
    expect(pending['source_revision'], 'new');
    final draft = await DatabaseService.getDraft('server-a');
    expect(draft?['checklist_data']['vessel_name'], 'newer draft');
    expect(draft?['source_revision'], 'new');
    expect(
        await AutoSaveService()
            .getDraftForEquipment('vessel', reportFormId: 'to-1'),
        isNull);
  });
}
