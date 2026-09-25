import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../../lib/services/api_service.dart';

class _PreviewApi extends ApiServiceBase with ApiReportsMixin {
  @override
  Future<bool> ensureValidToken() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({'auth_token': 'test-token'}));

  test('preview requests official PDF and returns the downloaded bytes', () async {
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      expect(request.headers['Authorization'], 'Bearer test-token');
      if (request.method == 'POST') {
        expect(json.decode(request.body)['inspection_id'], 'inspection');
        expect(json.decode(request.body)['format'], 'pdf');
        return http.Response('{"id":"report"}', 200);
      }
      expect(request.url.path, '/api/reports/report/download');
      return http.Response('%PDF-1.7 test', 200);
    });
    final result = await http.runWithClient(() => _PreviewApi().generateInspectionPdf('inspection'), () => client);
    expect(utf8.decode(result), '%PDF-1.7 test');
    expect(calls.length, 2);
  });

  test('preview rejects HTML returned in place of a PDF', () async {
    final client = MockClient((request) async => request.method == 'POST'
      ? http.Response('{"id":"report"}', 200) : http.Response('<html>error</html>', 200));
    await expectLater(http.runWithClient(() => _PreviewApi().generateInspectionPdf('inspection'), () => client),
      throwsA(isA<Exception>()));
  });
}
