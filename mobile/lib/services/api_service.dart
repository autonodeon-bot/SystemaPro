import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../models/equipment.dart';
import '../models/user.dart';
import '../models/vessel_checklist.dart';
import '../models/assignment.dart';
import 'auth_service.dart';

part 'api_equipment_service.dart';
part 'api_assignments_service.dart';
part 'api_inspections_service.dart';
part 'api_reports_service.dart';

MediaType? _contentTypeFromExtension(String ext) {
  switch (ext) {
    case '.jpg':
    case '.jpeg':
      return MediaType('image', 'jpeg');
    case '.png':
      return MediaType('image', 'png');
    case '.pdf':
      return MediaType('application', 'pdf');
    default:
      return null;
  }
}

abstract class ApiServiceBase {
  const ApiServiceBase();

  static String get baseUrl => AppConfig.effectiveApiBaseUrl;
  static const Duration requestTimeout = Duration(seconds: 120);

  Future<bool> ensureValidToken();
}

class ApiService extends ApiServiceBase
    with
        ApiEquipmentMixin,
        ApiAssignmentsMixin,
        ApiInspectionsMixin,
        ApiReportsMixin {
  const ApiService();

  static String get baseUrl => ApiServiceBase.baseUrl;
  static const Duration requestTimeout = ApiServiceBase.requestTimeout;

  static const Duration _loginTimeout = Duration(seconds: 45);

  static bool _isNetworkFailure(Object e) {
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('No route to host') ||
        s.contains('Failed host lookup') ||
        s.contains('Network is unreachable') ||
        s.contains('Connection refused') ||
        s.contains('Connection timed out');
  }

  static Exception _loginNetworkError() {
    return Exception(
      'Нет связи с сервером ($baseUrl). Проверьте интернет, отключите VPN и '
      'прокси/фильтры трафика (AdGuard и т.п.). Убедитесь, что в браузере '
      'телефона открывается сайт.',
    );
  }

  static String _parseApiErrorDetail(dynamic detail, {String fallback = 'Ошибка входа'}) {
    if (detail == null) return fallback;
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] != null) {
        return first['msg'].toString();
      }
      return first.toString();
    }
    return detail.toString();
  }

  static Never _throwLoginHttpError(int statusCode, String body) {
    String message;
    try {
      final errorData = json.decode(body) as Map<String, dynamic>;
      message = _parseApiErrorDetail(errorData['detail']);
    } catch (_) {
      if (statusCode == 423) {
        message = 'Учётная запись временно заблокирована. Попробуйте позже.';
      } else if (statusCode >= 500) {
        message = 'Сервер недоступен. Попробуйте позже.';
      } else {
        message = 'Ошибка входа (код $statusCode)';
      }
    }
    throw Exception(message);
  }

  Future<Map<String, dynamic>> _enrichLoginWithProfile(
    Map<String, dynamic> data, {
    required String fallbackUsername,
  }) async {
    final token = data['access_token'];
    if (token == null) return data;

    try {
      final userResponse = await http
          .get(
        Uri.parse('$baseUrl/api/auth/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      )
          .timeout(_loginTimeout);
      if (userResponse.statusCode == 200) {
        final userData = json.decode(userResponse.body) as Map<String, dynamic>;
        return {
          ...data,
          'access_token': token,
          'user_id': userData['username'],
          'username': userData['username'],
          'email': userData['email'],
          'full_name': userData['full_name'],
          'role': userData['role'],
        };
      }
    } catch (_) {
      // профиль необязателен — используем данные из login/2fa
    }

    return {
      ...data,
      'access_token': token,
      'username': data['username'] ?? fallbackUsername,
      'role': data['role'],
    };
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http
          .post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body:
            'username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}',
      )
          .timeout(_loginTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['two_factor_required'] == true) {
          return {
            'two_factor_required': true,
            'username': data['username'] ?? username,
            'role': data['role'],
          };
        }
        final token = data['access_token'];
        if (token != null) {
          return _enrichLoginWithProfile(
            {
              'access_token': token,
              'role': data['role'],
              'password_hash': data['password_hash'],
            },
            fallbackUsername: username,
          );
        }
        throw Exception('Токен не получен от сервера');
      }
      _throwLoginHttpError(response.statusCode, response.body);
    } on SocketException {
      throw _loginNetworkError();
    } on TimeoutException {
      throw _loginNetworkError();
    } catch (e) {
      if (_isNetworkFailure(e)) {
        throw _loginNetworkError();
      }
      rethrow;
    }
  }

  /// Второй шаг входа при включённой 2FA (TOTP или recovery-код).
  Future<Map<String, dynamic>> verifyTwoFactorLogin({
    required String username,
    required String password,
    required String code,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse('$baseUrl/api/auth/2fa/verify'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
          'code': code.trim(),
        }),
      )
          .timeout(_loginTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final token = data['access_token'];
        if (token == null) {
          throw Exception('Токен не получен от сервера');
        }
        return _enrichLoginWithProfile(
          {
            'access_token': token,
            'role': data['role'],
          },
          fallbackUsername: username,
        );
      }
      _throwLoginHttpError(response.statusCode, response.body);
    } on SocketException {
      throw _loginNetworkError();
    } on TimeoutException {
      throw _loginNetworkError();
    } catch (e) {
      if (_isNetworkFailure(e)) {
        throw _loginNetworkError();
      }
      rethrow;
    }
  }

  @override
  Future<bool> ensureValidToken() async {
    final authService = AuthService();
    final token = await authService.getToken();
    if (token != null && token.isNotEmpty) return true;

    final creds = await authService.getStoredCredentials();
    if (creds == null) return false;

    try {
      final response = await login(creds.username, creds.password);
      if (response['two_factor_required'] == true) return false;
      if (response['access_token'] == null) return false;
      final user = User(
        id: response['user_id']?.toString() ?? creds.username,
        username: response['username'] ?? creds.username,
        email: response['email'],
        fullName: response['full_name'],
        role: response['role'],
        token: response['access_token'],
      );
      await authService.saveUser(user, passwordHash: response['password_hash']);
      await authService.saveCredentials(creds.username, creds.password);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Проверка доступности сервера для синхронизации и UI.
  ///
  /// Используется [GET /api/mobile/version] — без обращения к БД (в отличие от [/health],
  /// который при недоступности базы отдаёт 503 и ложно блокировал бы синхронизацию).
  /// Запасной вариант — [/health]. Таймаут увеличен для слабых каналов связи.
  Future<bool> checkConnection() async {
    const timeout = Duration(seconds: 15);
    final base = baseUrl;

    try {
      final r = await http
          .get(
            Uri.parse('$base/api/mobile/version'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(timeout);
      if (r.statusCode == 200) {
        try {
          final decoded = json.decode(r.body);
          if (decoded is Map && decoded.containsKey('version')) {
            return true;
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('checkConnection /api/mobile/version: $e');
    }

    try {
      final response = await http
          .get(
            Uri.parse('$base/health'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('checkConnection /health: $e');
      return false;
    }
  }

  Future<void> registerFcmToken(String token) async {
    try {
      await ensureValidToken();
      final authService = AuthService();
      final authToken = await authService.getToken();
      if (authToken == null) return;

      await http.post(
        Uri.parse('$baseUrl/api/notifications/register-device'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: json.encode({
          'fcm_token': token,
          'platform': Platform.isAndroid ? 'android' : 'ios',
        }),
      );
    } catch (e) {
      debugPrint('Error registering FCM token: $e');
    }
  }

  Future<Map<String, dynamic>?> checkAppUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = packageInfo.buildNumber;

      final response = await http.get(
        Uri.parse(
            '$baseUrl/api/mobile/check-update?current_version=$currentVersion&current_build=$currentBuild'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  //  Реестр приборов (приборный парк) — П.4
  // ============================================================

  Future<List<dynamic>> getInstruments() async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/api/instruments'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(requestTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body) as List<dynamic>;
    }
    throw Exception('Ошибка загрузки приборов: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> createInstrument(Map<String, dynamic> data) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/instruments'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: json.encode(data),
    ).timeout(requestTimeout);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Ошибка создания прибора: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> updateInstrument(
      String id, Map<String, dynamic> data) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http.put(
      Uri.parse('$baseUrl/api/instruments/$id'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: json.encode(data),
    ).timeout(requestTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Ошибка обновления прибора: ${response.statusCode}');
  }

  Future<void> deleteInstrument(String id) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http.delete(
      Uri.parse('$baseUrl/api/instruments/$id'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(requestTimeout);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Ошибка удаления прибора: ${response.statusCode}');
    }
  }

  Future<List<dynamic>> getMyInstruments() async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/api/instruments/my'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(requestTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body) as List<dynamic>;
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> listStandaloneProtocols() async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/standalone-protocols'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(requestTimeout);
    if (response.statusCode == 200) {
      final d = json.decode(response.body);
      if (d is Map && d['items'] is List) {
        return (d['items'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    }
    return [];
  }

  /// Сохранение протокола с мобильного (без полного обследования на сервере).
  Future<Map<String, dynamic>?> submitStandaloneProtocol({
    required String title,
    required String kind,
    String? templateId,
    String? templateName,
    String? equipmentId,
    String? equipmentName,
    String? assignmentId,
    required Map<String, dynamic> payload,
  }) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final bodyMap = <String, dynamic>{
      'title': title,
      'kind': kind,
      if (templateId != null && templateId.isNotEmpty) 'template_id': templateId,
      if (templateName != null && templateName.isNotEmpty) 'template_name': templateName,
      if (equipmentId != null && equipmentId.isNotEmpty) 'equipment_id': equipmentId,
      if (equipmentName != null && equipmentName.isNotEmpty) 'equipment_name': equipmentName,
      if (assignmentId != null && assignmentId.isNotEmpty) 'assignment_id': assignmentId,
      'payload': payload,
    };
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/standalone-protocols'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: json.encode(bodyMap),
        )
        .timeout(requestTimeout);
    if (response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    final err = response.body;
    throw Exception('Протокол на сервере не сохранён (${response.statusCode}): $err');
  }

  // ── Шаблоны протоколов (конструктор П.2) ──────────────────────────────────

  Future<List<dynamic>> getProtocolTemplates({String? category}) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    var url = '$baseUrl/api/protocol-templates?active_only=true';
    if (category != null && category.isNotEmpty) {
      url += '&category=${Uri.encodeComponent(category)}';
    }
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(requestTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body) as List<dynamic>;
    }
    throw Exception('Ошибка загрузки шаблонов: ${response.statusCode}');
  }

  /// Один шаблон по id (для задания с обязательным шаблоном).
  Future<Map<String, dynamic>> getProtocolTemplateById(String templateId) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/protocol-templates/$templateId'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(requestTimeout);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    throw Exception('Шаблон не загружен (${response.statusCode}): ${response.body}');
  }

  /// Шаблон «Быстрый контроль» по коду (qc_vik, qc_emergency, …).
  Future<Map<String, dynamic>> getQuickControlProtocolTemplate(
    String quickControlCode,
  ) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http
        .get(
          Uri.parse(
            '$baseUrl/api/protocol-templates/by-quick-control/${Uri.encodeComponent(quickControlCode)}',
          ),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(requestTimeout);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    if (response.statusCode == 404) {
      throw Exception(
        'Шаблон «$quickControlCode» не найден на сервере. Обновите backend или выполните seed.',
      );
    }
    throw Exception(
      'Ошибка загрузки шаблона (${response.statusCode}): ${response.body}',
    );
  }

  // ── Опытная база ───────────────────────────────────────────────────────────

  Future<List<dynamic>> getExperienceBaseEntries({
    String? categoryCode,
    String? equipmentId,
    String? assignmentId,
    String? equipmentKind,
    String? equipmentMark,
    String? entryType,
    bool includeArchetypes = true,
    String? q,
  }) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final qParams = <String, String>{
      'limit': '100',
      'include_archetypes': includeArchetypes.toString(),
    };
    if (categoryCode != null && categoryCode.isNotEmpty) {
      qParams['category_code'] = categoryCode;
    }
    if (equipmentId != null && equipmentId.isNotEmpty) {
      qParams['equipment_id'] = equipmentId;
    }
    if (assignmentId != null && assignmentId.isNotEmpty) {
      qParams['assignment_id'] = assignmentId;
    }
    if (equipmentKind != null && equipmentKind.isNotEmpty) {
      qParams['equipment_kind'] = equipmentKind;
    }
    if (equipmentMark != null && equipmentMark.isNotEmpty) {
      qParams['equipment_mark'] = equipmentMark;
    }
    if (entryType != null && entryType.isNotEmpty) {
      qParams['entry_type'] = entryType;
    }
    if (q != null && q.isNotEmpty) qParams['q'] = q;
    final uri = Uri.parse('$baseUrl/api/experience-base/entries')
        .replace(queryParameters: qParams);
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(requestTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body) as List<dynamic>;
    }
    throw Exception('Ошибка загрузки опытной базы: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> getExperienceBaseContext({
    String? assignmentId,
    String? equipmentId,
    String? categoryCode,
    String? equipmentKind,
    String? equipmentMark,
  }) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final qParams = <String, String>{};
    if (assignmentId != null && assignmentId.isNotEmpty) {
      qParams['assignment_id'] = assignmentId;
    }
    if (equipmentId != null && equipmentId.isNotEmpty) {
      qParams['equipment_id'] = equipmentId;
    }
    if (categoryCode != null && categoryCode.isNotEmpty) {
      qParams['category_code'] = categoryCode;
    }
    if (equipmentKind != null && equipmentKind.isNotEmpty) {
      qParams['equipment_kind'] = equipmentKind;
    }
    if (equipmentMark != null && equipmentMark.isNotEmpty) {
      qParams['equipment_mark'] = equipmentMark;
    }
    final uri = Uri.parse('$baseUrl/api/experience-base/context')
        .replace(queryParameters: qParams);
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(requestTimeout);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    throw Exception('Контекст опытной базы: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> resolveInspectionObjectTemplates({
    required String categoryCode,
    required String inspectionDirection,
    String? equipmentId,
    String? equipmentKind,
    String? equipmentMark,
    String? equipmentPreset,
  }) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final q = <String, String>{
      'category_code': categoryCode,
      'inspection_direction': inspectionDirection,
    };
    if (equipmentId != null && equipmentId.isNotEmpty) {
      q['equipment_id'] = equipmentId;
    }
    if (equipmentKind != null && equipmentKind.isNotEmpty) {
      q['equipment_kind'] = equipmentKind;
    }
    if (equipmentMark != null && equipmentMark.isNotEmpty) {
      q['equipment_mark'] = equipmentMark;
    }
    if (equipmentPreset != null && equipmentPreset.isNotEmpty) {
      q['equipment_preset'] = equipmentPreset;
    }
    final uri = Uri.parse('$baseUrl/api/inspection-object-templates/resolve')
        .replace(queryParameters: q);
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(requestTimeout);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    throw Exception('Шаблоны обследования: ${response.statusCode}');
  }

  /// Профиль оборудования + default_data для чек-листа (единый реестр backend).
  Future<Map<String, dynamic>> resolveEquipmentProfile({
    String? typeCode,
    String? preset,
    String inspectionDirection = 'technical',
    bool includeUztTemplate = true,
  }) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final q = <String, String>{
      'inspection_direction': inspectionDirection,
      'include_uzt_template': includeUztTemplate.toString(),
    };
    if (typeCode != null && typeCode.isNotEmpty) q['type_code'] = typeCode;
    if (preset != null && preset.isNotEmpty) q['preset'] = preset;
    final uri = Uri.parse('$baseUrl/api/equipment-profiles/resolve')
        .replace(queryParameters: q);
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(requestTimeout);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    throw Exception('Профиль оборудования: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> getDiagnosticMenuPublished() async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/api/diagnostic-menu'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(requestTimeout);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    throw Exception('Ошибка загрузки меню: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> createExperienceBaseEntry({
    required String categoryCode,
    required String equipmentKind,
    String? equipmentMark,
    required String body,
    String entryType = 'note',
    String? title,
    String? equipmentId,
    String? assignmentId,
  }) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/experience-base/entries'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'category_code': categoryCode,
            'equipment_kind': equipmentKind,
            'equipment_mark': equipmentMark,
            'entry_type': entryType,
            'title': title,
            'body': body,
            if (equipmentId != null && equipmentId.isNotEmpty)
              'equipment_id': equipmentId,
            if (assignmentId != null && assignmentId.isNotEmpty)
              'assignment_id': assignmentId,
          }),
        )
        .timeout(requestTimeout);
    if (response.statusCode == 201) {
      return Map<String, dynamic>.from(json.decode(response.body) as Map);
    }
    throw Exception('Не удалось сохранить запись: ${response.body}');
  }
}
