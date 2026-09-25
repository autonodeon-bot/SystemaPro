import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import '../../lib/services/inspection_archive_service.dart';

class _TempPaths extends PathProviderPlatform {
  _TempPaths(this.directory);
  final String directory;
  @override
  Future<String?> getTemporaryPath() async => directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform original;
  setUp(() async {
    original = PathProviderPlatform.instance;
    directory = await Directory.systemTemp.createTemp('report_archive_test_');
    PathProviderPlatform.instance = _TempPaths(directory.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = original;
    await directory.delete(recursive: true);
  });
  test('PDF retains extension and bytes; names cannot collide', () async {
    final a = File('${directory.path}/first.pdf');
    final b = File('${directory.path}/second.pdf');
    await a.writeAsString('%PDF-first'); await b.writeAsString('%PDF-second');
    final zip = await InspectionArchiveService.buildArchive(inspectionData: {
      'equipment_id': 'test', 'data': <String, dynamic>{},
      'document_files': {'a.b': a.path, 'a/b': b.path},
    });
    final archive = ZipDecoder().decodeBytes(await File(zip).readAsBytes());
    final attachments = archive.files.where((f) => f.name.startsWith('photos/')).toList();
    expect(attachments.length, 2);
    expect(attachments.map((f) => f.name).toSet().length, 2);
    expect(attachments.every((f) => f.name.endsWith('.pdf')), isTrue);
    final manifest = jsonDecode(utf8.decode(archive.findFile('manifest.json')!.content as List<int>));
    for (final file in archive.files.where((f) => f.name != 'manifest.json')) {
      expect(manifest['checksums'][file.name], sha256.convert(file.content as List<int>).toString());
    }
  });
  test('missing local attachment blocks upload', () async {
    await expectLater(InspectionArchiveService.buildArchive(inspectionData: {
      'data': <String, dynamic>{}, 'document_files': {'1': '${directory.path}/lost.pdf'},
    }), throwsException);
  });
}
