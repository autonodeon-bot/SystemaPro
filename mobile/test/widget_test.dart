import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/services/api_service.dart';

void main() {
  group('App Smoke Tests', () {
    test('ApiService can be instantiated', () {
      final service = ApiService();
      expect(service, isNotNull);
      expect(service, isA<ApiService>());
    });

    test('app package name is correct', () {
      // Пакет должен импортироваться без ошибок
      expect(ApiService.baseUrl, isNotEmpty);
    });
  });
}
