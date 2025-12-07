import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/equipment.dart';
import '../models/vessel_checklist.dart';
import '../models/user.dart';
import 'auth_service.dart';

class ApiService {
  // TODO: Заменить на реальный URL сервера
  static const String baseUrl = 'http://5.129.203.182:8000';

  // Получить список оборудования
  Future<List<Equipment>> getEquipmentList({String? token}) async {
    try {
      final headers = {'Content-Type': 'application/json'};

      // Автоматически получаем токен из AuthService, если не передан
      String? authToken = token;
      if (authToken == null) {
        final authService = AuthService();
        authToken = await authService.getToken();
      }

      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/equipment'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;
        return items.map((item) => Equipment.fromJson(item)).toList();
      } else {
        // Попытка получить детали ошибки из ответа
        String errorMessage =
            'Failed to load equipment: ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          if (errorData['detail'] != null) {
            errorMessage = '${errorData['detail']} (${response.statusCode})';
          }
        } catch (_) {
          errorMessage = 'Server error: ${response.statusCode}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        throw Exception(
            'Нет подключения к серверу. Проверьте интернет-соединение.');
      }
      throw Exception('Ошибка загрузки оборудования: $e');
    }
  }

  // Получить оборудование по ID
  Future<Equipment> getEquipmentById(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/equipment/$id'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return Equipment.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load equipment: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching equipment: $e');
    }
  }

  // Отправить чек-лист обследования
  Future<Map<String, dynamic>> submitInspection({
    required String equipmentId,
    required VesselChecklist checklist,
    String? conclusion,
    DateTime? datePerformed,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/inspections'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'equipment_id': equipmentId,
          'data': checklist.toJson(),
          'conclusion': conclusion,
          'status': 'DRAFT',
          'date_performed': datePerformed?.toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        final errorBody = response.body;
        String errorMessage =
            'Failed to submit inspection: ${response.statusCode}';

        // Обработка ошибки авторизации
        if (response.statusCode == 401 || response.statusCode == 403) {
          errorMessage =
              'Ошибка авторизации. Пожалуйста, войдите в систему заново.';
          // Очищаем токен при ошибке авторизации
          final authService = AuthService();
          await authService.logout();
        }

        try {
          final errorData = json.decode(errorBody);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Error submitting inspection: $e');
    }
  }

  // Получить список инспекций для оборудования
  Future<List<Map<String, dynamic>>> getInspections(String? equipmentId) async {
    try {
      final uri = equipmentId != null
          ? Uri.parse('$baseUrl/api/inspections?equipment_id=$equipmentId')
          : Uri.parse('$baseUrl/api/inspections');

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['items']);
      } else {
        throw Exception('Failed to load inspections: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching inspections: $e');
    }
  }

  // Создать новое оборудование
  Future<Equipment> createEquipment({
    required String name,
    String? typeId,
    String? serialNumber,
    String? location,
    Map<String, dynamic>? attributes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/equipment'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'type_id': typeId,
          'serial_number': serialNumber,
          'location': location,
          'attributes': attributes ?? {},
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return Equipment.fromJson(json.decode(response.body));
      } else {
        final errorBody = response.body;
        String errorMessage =
            'Failed to create equipment: ${response.statusCode}';
        try {
          final errorData = json.decode(errorBody);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Error creating equipment: $e');
    }
  }

  // Получить типы оборудования
  Future<List<Map<String, dynamic>>> getEquipmentTypes() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/equipment-types'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['items'] ?? []);
      } else {
        throw Exception(
            'Failed to load equipment types: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching equipment types: $e');
    }
  }

  // Создать отчет из инспекции
  Future<Map<String, dynamic>> createReport({
    required String inspectionId,
    required String reportType,
    String? title,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/reports/generate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'inspection_id': inspectionId,
          'report_type': reportType,
          'title': title,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        final errorBody = response.body;
        String errorMessage = 'Failed to create report: ${response.statusCode}';
        try {
          final errorData = json.decode(errorBody);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Error creating report: $e');
    }
  }

  // Авторизация
  Future<User> login(String username, String password) async {
    try {
      // Правильное кодирование URL для form-urlencoded
      final body = Uri(
        queryParameters: {
          'username': username,
          'password': password,
        },
      ).query;

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['access_token'];

        if (token == null) {
          throw Exception('Токен не получен от сервера');
        }

        // ОБЯЗАТЕЛЬНО получаем информацию о пользователе из /api/auth/me
        // Это единственный надежный источник роли пользователя
        final userResponse = await http.get(
          Uri.parse('$baseUrl/api/auth/me'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );

        if (userResponse.statusCode == 200) {
          final userData = json.decode(userResponse.body);
          userData['token'] = token;

          // Проверяем, что роль присутствует и валидна
          if (userData['role'] == null || userData['role'].toString().isEmpty) {
            print(
                '⚠️ ВНИМАНИЕ: роль не получена от сервера, устанавливаем engineer по умолчанию');
            userData['role'] = 'engineer';
          }

          final role = userData['role'].toString().toLowerCase().trim();
          print(
              'API /auth/me вернул: role=$role, username=${userData['username']}');

          // Убеждаемся, что роль валидна
          final validRoles = [
            'admin',
            'chief_operator',
            'operator',
            'engineer'
          ];
          if (!validRoles.contains(role)) {
            print(
                '⚠️ ВНИМАНИЕ: получена невалидная роль "$role", устанавливаем engineer');
            userData['role'] = 'engineer';
          } else {
            userData['role'] = role;
          }

          final user = User.fromJson(userData);
          print(
              'Создан User объект: username=${user.username}, role=${user.role}');

          // Финальная проверка роли
          if (user.role != 'admin' &&
              user.role != 'chief_operator' &&
              user.role != 'operator' &&
              user.role != 'engineer') {
            print(
                '⚠️ КРИТИЧЕСКАЯ ОШИБКА: роль "${user.role}" невалидна, принудительно устанавливаем engineer');
            // Создаем нового пользователя с правильной ролью
            return User(
              id: user.id,
              username: user.username,
              fullName: user.fullName,
              email: user.email,
              phone: user.phone,
              role: 'engineer', // Принудительно engineer
              position: user.position,
              engineerId: user.engineerId,
              qualifications: user.qualifications,
              certifications: user.certifications,
              equipmentTypes: user.equipmentTypes,
              token: user.token,
            );
          }

          return user;
        } else {
          // Если /api/auth/me не работает - это критическая ошибка
          final errorBody = userResponse.body;
          print(
              '❌ КРИТИЧЕСКАЯ ОШИБКА: /api/auth/me вернул ${userResponse.statusCode}');
          print('Ответ сервера: $errorBody');
          throw Exception('Не удалось получить информацию о пользователе. '
              'Код ошибки: ${userResponse.statusCode}. '
              'Пожалуйста, попробуйте войти снова.');
        }
      } else {
        final errorBody = response.body;
        String errorMessage = 'Ошибка авторизации';
        try {
          final errorData = json.decode(errorBody);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          } else if (errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {
          if (response.statusCode == 401) {
            errorMessage = 'Неверный логин или пароль';
          } else if (response.statusCode == 404) {
            errorMessage = 'Пользователь не найден. Проверьте логин и пароль.';
          } else if (response.statusCode == 422) {
            errorMessage = 'Неверный формат данных. Проверьте логин и пароль.';
          } else {
            errorMessage =
                'Ошибка сервера: ${response.statusCode}. ${errorBody.length > 100 ? errorBody.substring(0, 100) : errorBody}';
          }
        }
        throw Exception(errorMessage);
      }
    } on http.ClientException catch (e) {
      // Ошибки сети
      if (e.message.contains('Failed host lookup') ||
          e.message.contains('SocketException')) {
        throw Exception(
            'Нет подключения к серверу. Проверьте интернет-соединение.');
      }
      throw Exception('Ошибка сети: ${e.message}');
    } catch (e) {
      String errorMsg = e.toString();
      if (errorMsg.contains('SocketException') ||
          errorMsg.contains('Failed host lookup')) {
        throw Exception(
            'Нет подключения к серверу. Проверьте интернет-соединение.');
      } else if (errorMsg.contains('Exception:')) {
        throw Exception(errorMsg.replaceAll('Exception: ', ''));
      }
      throw Exception(
          'Ошибка авторизации: ${errorMsg.replaceAll('Exception: ', '')}');
    }
  }

  // Получить информацию о текущем пользователе
  Future<User> getCurrentUser(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        data['token'] = token;
        return User.fromJson(data);
      } else {
        throw Exception('Failed to get user info: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching user: $e');
    }
  }

  // Получить статистику специалиста
  Future<Map<String, dynamic>> getSpecialistStats(String engineerId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/engineers/$engineerId/stats'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'total_inspections': 0,
          'total_reports': 0,
          'active_projects': 0,
          'certifications_count': 0,
        };
      }
    } catch (e) {
      return {
        'total_inspections': 0,
        'total_reports': 0,
        'active_projects': 0,
        'certifications_count': 0,
      };
    }
  }

  // Получить документы специалиста
  Future<List<Map<String, dynamic>>> getSpecialistDocuments(
      String engineerId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/engineers/$engineerId/documents'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['items'] ?? []);
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // Получить сертификаты специалиста
  Future<List<Map<String, dynamic>>> getSpecialistCertifications(
      String engineerId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/certifications?engineer_id=$engineerId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['items'] ?? []);
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // Обновить профиль пользователя
  Future<User?> updateUserProfile({
    required String userId,
    String? phone,
    String? email,
    String? fullName,
    File? photo,
    required String token,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/users/$userId');
      final request = http.MultipartRequest('PUT', uri);

      request.headers['Authorization'] = 'Bearer $token';

      // Добавляем поля
      if (phone != null) request.fields['phone'] = phone;
      if (email != null) request.fields['email'] = email;
      if (fullName != null) request.fields['full_name'] = fullName;

      // Добавляем фото, если есть
      if (photo != null && await photo.exists()) {
        final multipartFile = await http.MultipartFile.fromPath(
          'photo',
          photo.path,
          filename: photo.path.split('/').last,
        );
        request.files.add(multipartFile);
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        data['token'] = token;
        return User.fromJson(data);
      } else {
        throw Exception('Failed to update profile: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error updating profile: $e');
    }
  }

  // Загрузить документ по НК
  Future<void> uploadNDTDocument({
    required String userId,
    required File file,
    required String fileName,
    required String documentType,
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final uri = Uri.parse('$baseUrl/api/users/$userId/ndt-documents');
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['document_type'] = documentType;
      request.fields['name'] = fileName;

      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: fileName,
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorBody = response.body;
        String errorMessage =
            'Failed to upload document: ${response.statusCode}';
        try {
          final errorData = json.decode(errorBody);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Error uploading NDT document: $e');
    }
  }

  // Скачать документ
  Future<String> downloadDocument(String documentId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/documents/$documentId/download'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        // Возвращаем URL для скачивания или путь к файлу
        return response.body;
      } else {
        throw Exception('Failed to download document: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error downloading document: $e');
    }
  }

  // Проверка подключения
  Future<bool> checkConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: {'Content-Type': 'application/json'},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Получить токен из AuthService
  Future<String?> getToken() async {
    final authService = AuthService();
    return await authService.getToken();
  }

  // Отправка опросного листа
  Future<Map<String, dynamic>> submitQuestionnaire(
    dynamic questionnaire,
    Map<String, String> photoPaths,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/api/questionnaires');
      final request = http.MultipartRequest('POST', uri);

      // Получаем токен из AuthService
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null || token.isEmpty) {
        throw Exception(
            'Токен авторизации не найден. Пожалуйста, войдите в систему заново.');
      }
      request.headers['Authorization'] = 'Bearer $token';

      // Добавляем основные поля
      request.fields['equipment_id'] = questionnaire.equipmentId ?? '';
      request.fields['equipment_inventory_number'] =
          questionnaire.equipmentInventoryNumber ?? '';
      request.fields['equipment_name'] = questionnaire.equipmentName ?? '';
      request.fields['inspection_date'] =
          questionnaire.inspectionDate ?? DateTime.now().toIso8601String();
      request.fields['inspector_name'] = questionnaire.inspectorName ?? '';
      request.fields['inspector_position'] =
          questionnaire.inspectorPosition ?? '';
      request.fields['questionnaire_data'] =
          json.encode(questionnaire.toJson());

      // Добавляем файлы
      // Метаданные (item-id и item-name) уже включены в имя файла через FileNaming
      for (final entry in photoPaths.entries) {
        final file = File(entry.value);
        if (await file.exists()) {
          // Используем MultipartFile.fromPath для упрощения
          final multipartFile = await http.MultipartFile.fromPath(
            'files',
            entry.value,
            filename: file.path.split('/').last,
            contentType: MediaType('image', 'jpeg'),
          );

          request.files.add(multipartFile);
        }
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        final errorBody = response.body;
        String errorMessage =
            'Failed to submit questionnaire: ${response.statusCode}';

        // Обработка ошибки авторизации
        if (response.statusCode == 401 || response.statusCode == 403) {
          errorMessage =
              'Ошибка авторизации. Пожалуйста, войдите в систему заново.';
          // Очищаем токен при ошибке авторизации
          final authService = AuthService();
          await authService.logout();
        }

        try {
          final errorData = json.decode(errorBody);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Error submitting questionnaire: $e');
    }
  }
}
