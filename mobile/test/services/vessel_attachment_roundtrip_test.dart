import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:es_td_ngo_mobile/models/vessel_checklist.dart';
import 'package:es_td_ngo_mobile/models/vessel_geometry.dart';
import 'package:es_td_ngo_mobile/services/inspection_archive_service.dart';
import 'package:es_td_ngo_mobile/services/sync_service.dart';

class TestPaths extends PathProviderPlatform {
  TestPaths(this.directory);
  final String directory;
  @override
  Future<String?> getTemporaryPath() async => directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('restored geometry packs detail files without an in-memory attachment map', () async {
    final dir = await Directory.systemTemp.createTemp('vessel-archive-');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(dir.path);
    final original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = TestPaths(dir.path);
    addTearDown(() { PathProviderPlatform.instance = original; });
    final file = File('${dir.path}/detail.png');
    await file.writeAsBytes([137, 80, 78, 71]);
    final g = VesselGeometry.create();
    g.data['views'] = [{
      'id': 'view-1', 'kind': 'part_detail',
      'part_ids': [g.shells.first['id']],
      'image_path': file.path, 'document_number': 'vessel_detail_1',
    }];
    final checklist = VesselChecklist()
      ..reportFormId = 'to-1'
      ..baseVesselScheme = (BaseVesselScheme()..geometry = g.data);
    final sync = SyncService();
    await sync.saveInspectionOffline(equipmentId: 'test-vessel',
      checklist: checklist, inspectionDate: '2026-10-13');
    final pending = (await sync.getPendingInspections()).single;
    final zip = await InspectionArchiveService.buildArchive(inspectionData: pending);
    final archive = ZipDecoder().decodeBytes(await File(zip).readAsBytes());
    final payload = jsonDecode(utf8.decode(archive.findFile('checklist.json')!.content as List<int>));
    final path = payload['data']['base_vessel_scheme']['geometry']['views'][0]['image_path'] as String;
    expect(path, startsWith('photos/'));
    expect(archive.findFile(path), isNotNull);
    expect(archive.findFile(path)!.content, [137,80,78,71]);
  });
}
