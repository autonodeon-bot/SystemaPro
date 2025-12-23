import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../models/equipment.dart';
import '../models/vessel_checklist.dart';
import '../models/assignment.dart';
import 'auth_service.dart';

class ApiService {
  // TODO: Заменить на реальный URL сервера
  static const String baseUrl = 'http://5.129.203.182:8000';

  // Вход в систему
  Future<Map<String, dynamic>?> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'username=$username&password=$password',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Получаем информацию о пользователе
        final token = data['access_token'];
        if (token != null) {
          try {
            final userResponse = await http.get(
              Uri.parse('$baseUrl/api/auth/me'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
            );
            if (userResponse.statusCode == 200) {
              final userData = json.decode(userResponse.body);
              return {
                'access_token': token,
                'user_id': userData['username'],
                'username': userData['username'],
                'email': userData['email'],
                'full_name': userData['full_name'],
                'role': userData['role'],
                'password_hash': data['password_hash'], // Для офлайн-авторизации
              };
            }
          } catch (_) {
            // Если не удалось получить данные пользователя, возвращаем только токен
            return {
              'access_token': token,
              'username': username,
              'role': data['role'],
              'password_hash': data['password_hash'], // Для офлайн-авторизации
            };
          }
        }
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? 'Ошибка входа');
      }
    } catch (e) {
      throw Exception('Ошибка входа: $e');
    }
  }

  // Получить список оборудования
  Future<List<Equipment>> getEquipmentList() async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      // Увеличиваем лимит для мобильного приложения
      final response = await http.get(
        Uri.parse('$baseUrl/api/equipment?limit=10000'),
        headers: headers,
      );

      if (response.statusCode == 401) {
        throw Exception('AUTH_INVALID');
      }

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
      final authService = AuthService();
      final token = await authService.getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/equipment/$id'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
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

  // Обновить оборудование (серийный номер/attributes и т.п.)
  Future<void> updateEquipment({
    required String equipmentId,
    String? serialNumber,
    Map<String, dynamic>? attributes,
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();

      final body = <String, dynamic>{};
      if (serialNumber != null && serialNumber.trim().isNotEmpty) {
        body['serial_number'] = serialNumber.trim();
      }
      if (attributes != null) {
        body['attributes'] = attributes;
      }

      // Если нечего обновлять — выходим тихо
      if (body.isEmpty) return;

      final response = await http.put(
        Uri.parse('$baseUrl/api/equipment/$equipmentId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode(body),
      );

      if (response.statusCode != 200) {
        String errorMessage = 'Failed to update equipment: ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Error updating equipment: $e');
    }
  }

  // Заполнить/обновить данные оборудования из карты обследования (если инженер ввел/дополнил)
  Future<void> updateEquipmentFromChecklist({
    required String equipmentId,
    required VesselChecklist checklist,
  }) async {
    try {
      final eq = await getEquipmentById(equipmentId);
      final attrs = <String, dynamic>{};
      if (eq.attributes != null) {
        attrs.addAll(eq.attributes!);
      }

      void setAttrIfNotEmpty(String key, String? value) {
        final v = value?.trim();
        if (v == null || v.isEmpty) return;
        attrs[key] = v;
      }

      // Карта обследования -> attributes оборудования
      setAttrIfNotEmpty('vessel_name', checklist.vesselName);
      setAttrIfNotEmpty('reg_number', checklist.regNumber);
      setAttrIfNotEmpty('manufacturer', checklist.manufacturer);
      setAttrIfNotEmpty('manufacture_year', checklist.manufactureYear);
      setAttrIfNotEmpty('diameter', checklist.diameter);
      setAttrIfNotEmpty('working_pressure', checklist.workingPressure);
      setAttrIfNotEmpty('wall_thickness', checklist.wallThickness);

      // Организация (если заполнили)
      setAttrIfNotEmpty('organization', checklist.organization);

      // Серийный номер — в отдельное поле таблицы equipment
      final serial = checklist.serialNumber?.trim();

      await updateEquipment(
        equipmentId: equipmentId,
        serialNumber: (serial != null && serial.isNotEmpty) ? serial : null,
        attributes: attrs,
      );
    } catch (e) {
      // Не блокируем основной поток синхронизации/сохранения
      rethrow;
    }
  }

  // Отправить чек-лист обследования
  Future<Map<String, dynamic>> submitInspection({
    required String equipmentId,
    required VesselChecklist checklist,
    String? conclusion,
    DateTime? datePerformed,
    String? assignmentId, // ID задания (версия 3.3.0)
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final body = {
        'equipment_id': equipmentId,
        'data': checklist.toJson(),
        'conclusion': conclusion,
        'status': 'DRAFT',
        'date_performed': datePerformed?.toIso8601String(),
      };
      
      // Добавляем assignment_id, если он есть (версия 3.3.0)
      if (assignmentId != null) {
        body['assignment_id'] = assignmentId;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/inspections'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        final errorBody = response.body;
        String errorMessage =
            'Failed to submit inspection: ${response.statusCode}';
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
      final authService = AuthService();
      final token = await authService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final uri = equipmentId != null
          ? Uri.parse('$baseUrl/api/inspections?equipment_id=$equipmentId')
          : Uri.parse('$baseUrl/api/inspections');

      final response = await http.get(
        uri,
        headers: headers,
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

  // Добавить метод НК к опросному листу
  Future<Map<String, dynamic>> addNDTMethod({
    required String questionnaireId,
    required Map<String, dynamic> methodData,
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/questionnaires/$questionnaireId/ndt-methods'),
        headers: headers,
        body: json.encode(methodData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        final errorBody = response.body;
        String errorMessage =
            'Failed to add NDT method: ${response.statusCode}';
        try {
          final errorData = json.decode(errorBody);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Error adding NDT method: $e');
    }
  }

  // Получить методы НК для опросного листа
  Future<List<Map<String, dynamic>>> getNDTMethods(
      String questionnaireId) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final response = await http.get(
        Uri.parse('$baseUrl/api/questionnaires/$questionnaireId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['ndt_methods'] ?? []);
      } else {
        throw Exception('Failed to load NDT methods: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching NDT methods: $e');
    }
  }

  // Загрузить файл документа для чек-листа
  Future<Map<String, dynamic>> uploadDocumentFile({
    required String questionnaireId,
    required String documentNumber,
    required String filePath,
    required String fileName,
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();

      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final uri = Uri.parse(
          '$baseUrl/api/questionnaires/$questionnaireId/documents/$documentNumber/upload');

      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';

      final file = await http.MultipartFile.fromPath('file', filePath,
          filename: fileName);
      request.files.add(file);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        String errorMessage = 'Failed to upload file: ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Error uploading document file: $e');
    }
  }

  // Получить список файлов документов для опросного листа
  Future<List<Map<String, dynamic>>> getDocumentFiles(
      String questionnaireId) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final response = await http.get(
        Uri.parse('$baseUrl/api/questionnaires/$questionnaireId/documents'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['items'] ?? []);
      } else {
        throw Exception(
            'Failed to load document files: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching document files: $e');
    }
  }

  // Удалить файл документа
  Future<void> deleteDocumentFile({
    required String questionnaireId,
    required String documentNumber,
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();

      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      final response = await http.delete(
        Uri.parse(
            '$baseUrl/api/questionnaires/$questionnaireId/documents/$documentNumber'),
        headers: headers,
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        String errorMessage = 'Failed to delete file: ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Error deleting document file: $e');
    }
  }

  // Получить список заданий (версия 3.3.0)
  Future<List<Assignment>> getAssignments({String? status}) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      String url = '$baseUrl/api/assignments';
      if (status != null) {
        url += '?status=$status';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      if (response.statusCode == 401) {
        throw Exception('AUTH_INVALID');
      }

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final List<dynamic> items;

        // Поддерживаем оба формата ответа сервера:
        // - []
        // - { items: [] }
        if (decoded is List) {
          items = decoded;
        } else if (decoded is Map && decoded['items'] is List) {
          items = decoded['items'] as List;
        } else {
          throw Exception('Неожиданный формат ответа при загрузке заданий');
        }

        return items
            .map((j) => Assignment.fromJson(j as Map<String, dynamic>))
            .toList();
      } else {
        String errorMessage = 'Failed to load assignments: ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('SocketException')) {
        throw Exception(
            'Нет подключения к серверу. Проверьте интернет-соединение.');
      }
      throw Exception('Ошибка загрузки заданий: $e');
    }
  }

  // Получить задание по ID
  Future<Assignment> getAssignmentById(String assignmentId) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      final response = await http.get(
        Uri.parse('$baseUrl/api/assignments/$assignmentId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return Assignment.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load assignment: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching assignment: $e');
    }
  }

  // Получить информацию об оборудовании из задания
  Future<Equipment> getAssignmentEquipment(String assignmentId) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      final response = await http.get(
        Uri.parse('$baseUrl/api/assignments/$assignmentId/equipment'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return Equipment.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load assignment equipment: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching assignment equipment: $e');
    }
  }

  // Обновить статус задания
  Future<void> updateAssignmentStatus(String assignmentId, String status) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      final response = await http.put(
        Uri.parse('$baseUrl/api/assignments/$assignmentId'),
        headers: headers,
        body: json.encode({'status': status}),
      );

      if (response.statusCode != 200) {
        String errorMessage = 'Failed to update assignment: ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Error updating assignment: $e');
    }
  }

  // Получить список оборудования для поверок
  Future<List<Map<String, dynamic>>> getVerificationEquipment({
    String? equipmentType,
    bool? isActive,
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      String url = '$baseUrl/api/verification-equipment';
      List<String> params = [];
      if (equipmentType != null) {
        params.add('equipment_type=$equipmentType');
      }
      if (isActive != null) {
        params.add('is_active=$isActive');
      }
      if (params.isNotEmpty) {
        url += '?${params.join('&')}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      if (response.statusCode == 401) {
        throw Exception('AUTH_INVALID');
      }

      if (response.statusCode == 200) {
        final List<dynamic> items = json.decode(response.body);
        return items.map((item) => item as Map<String, dynamic>).toList();
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? 'Ошибка загрузки оборудования для поверок');
      }
    } catch (e) {
      throw Exception('Error getting verification equipment: $e');
    }
  }

  // Добавить используемое оборудование к обследованию
  Future<void> addEquipmentToInspection(
    String inspectionId,
    List<String> equipmentIds,
  ) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/inspections/$inspectionId/equipment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'verification_equipment_ids': equipmentIds,
        }),
      );

      if (response.statusCode == 401) {
        throw Exception('AUTH_INVALID');
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? 'Ошибка добавления оборудования');
      }
    } catch (e) {
      throw Exception('Error adding equipment to inspection: $e');
    }
  }

  // Получить используемое оборудование для обследования
  Future<List<Map<String, dynamic>>> getInspectionEquipment(String inspectionId) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/inspections/$inspectionId/equipment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 401) {
        throw Exception('AUTH_INVALID');
      }

      if (response.statusCode == 200) {
        final List<dynamic> items = json.decode(response.body);
        return items.map((item) => item as Map<String, dynamic>).toList();
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? 'Ошибка загрузки оборудования');
      }
    } catch (e) {
      throw Exception('Error getting inspection equipment: $e');
    }
  }

  // Проверить обновление мобильного приложения
  Future<Map<String, dynamic>?> checkAppUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = packageInfo.buildNumber;
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/mobile/check-update?current_version=$currentVersion&current_build=$currentBuild'),
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
}
