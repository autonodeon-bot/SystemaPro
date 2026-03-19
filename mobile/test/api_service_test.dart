import 'package:flutter_test/flutter_test.dart';
import 'package:es_td_ngo_mobile/services/api_service.dart';

void main() {
  late ApiService apiService;

  setUp(() {
    apiService = ApiService();
  });

  group('ApiService — конфигурация', () {
    test('baseUrl использует HTTPS', () {
      expect(ApiService.baseUrl, startsWith('https://'));
    });

    test('baseUrl указывает на neftcontrol.ru', () {
      expect(ApiService.baseUrl, contains('neftcontrol.ru'));
    });

    test('baseUrl не содержит завершающий слэш', () {
      expect(ApiService.baseUrl.endsWith('/'), isFalse);
    });

    test('requestTimeout находится в разумных пределах (5–300 сек)', () {
      const timeout = ApiService.requestTimeout;
      expect(timeout.inSeconds, greaterThanOrEqualTo(5));
      expect(timeout.inSeconds, lessThanOrEqualTo(300));
    });

    test('requestTimeout равен 120 секунд', () {
      expect(ApiService.requestTimeout, const Duration(seconds: 120));
    });
  });

  group('ApiService — экземпляр', () {
    test('создаётся без ошибок', () {
      expect(apiService, isNotNull);
      expect(apiService, isA<ApiService>());
    });

    test('несколько экземпляров независимы', () {
      final another = ApiService();
      expect(apiService, isNot(same(another)));
    });
  });

  group('ApiService — публичные методы существуют', () {
    test('login доступен', () {
      expect(apiService.login, isA<Function>());
    });

    test('ensureValidToken доступен', () {
      expect(apiService.ensureValidToken, isA<Function>());
    });

    test('getEquipmentList доступен', () {
      expect(apiService.getEquipmentList, isA<Function>());
    });

    test('getAssignments доступен', () {
      expect(apiService.getAssignments, isA<Function>());
    });

    test('checkConnection доступен', () {
      expect(apiService.checkConnection, isA<Function>());
    });

    test('submitInspection доступен', () {
      expect(apiService.submitInspection, isA<Function>());
    });

    test('checkAppUpdate доступен', () {
      expect(apiService.checkAppUpdate, isA<Function>());
    });
  });

  group('ApiService — формирование URL', () {
    test('URL для API оборудования корректен', () {
      final url = '${ApiService.baseUrl}/api/equipment';
      expect(url, equals('https://neftcontrol.ru/api/equipment'));
    });

    test('URL для авторизации корректен', () {
      final url = '${ApiService.baseUrl}/api/auth/login';
      expect(url, equals('https://neftcontrol.ru/api/auth/login'));
    });

    test('URL для обследований корректен', () {
      final url = '${ApiService.baseUrl}/api/inspections';
      expect(url, equals('https://neftcontrol.ru/api/inspections'));
    });

    test('URL для заданий корректен', () {
      final url = '${ApiService.baseUrl}/api/assignments';
      expect(url, equals('https://neftcontrol.ru/api/assignments'));
    });

    test('URL для health-check корректен', () {
      final url = '${ApiService.baseUrl}/health';
      expect(url, equals('https://neftcontrol.ru/health'));
    });
  });
}
