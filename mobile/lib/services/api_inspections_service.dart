part of 'api_service.dart';

mixin ApiInspectionsMixin on ApiServiceBase {
  Future<Map<String, dynamic>> submitInspection({
    required String equipmentId,
    required VesselChecklist checklist,
    String? conclusion,
    DateTime? datePerformed,
    String? assignmentId,
    String status = 'DRAFT',
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final body = <String, dynamic>{
        'equipment_id': equipmentId,
        'data': checklist.toJson(),
        'conclusion': conclusion,
        'status': status,
        'date_performed': datePerformed?.toIso8601String(),
      };

      if (assignmentId != null) {
        body['assignment_id'] = assignmentId;
      }

      final response = await http
          .post(
            Uri.parse('${ApiServiceBase.baseUrl}/api/inspections'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode(body),
          )
          .timeout(ApiServiceBase.requestTimeout, onTimeout: () {
            throw TimeoutException(
                'Сервер не ответил за ${ApiServiceBase.requestTimeout.inSeconds} сек. Проверьте интернет и попробуйте снова.');
          });

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        final errorBody = response.body;
        String errorMessage =
            'Код ${response.statusCode}';
        try {
          final errorData = json.decode(errorBody);
          final detail = errorData['detail'];
          if (detail != null) {
            if (detail is List) {
              errorMessage = detail
                  .map((e) => e is Map ? (e['message'] ?? e.toString()) : e.toString())
                  .join('; ');
            } else {
              errorMessage = detail.toString();
            }
          }
        } catch (_) {}
        if (response.statusCode == 401) {
          errorMessage = 'Сессия истекла. Войдите в приложение заново.';
        } else if (response.statusCode == 413) {
          errorMessage = 'Объём данных слишком большой. Уменьшите количество фото и повторите.';
        }
        throw Exception(errorMessage);
      }
    } on TimeoutException {
      rethrow;
    } on SocketException {
      throw Exception(
          'Нет связи с сервером. Проверьте интернет и доступность сервера.');
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> uploadInspectionArchive(
    String zipPath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final authService = AuthService();
    final hasToken = await ensureValidToken();
    final token = await authService.getToken();
    if (!hasToken || token == null) {
      throw Exception('Не удалось войти. Войдите в приложение (логин и пароль сохраняются для следующей синхронизации).');
    }

    final dio = Dio(BaseOptions(
      baseUrl: ApiServiceBase.baseUrl,
      connectTimeout: ApiServiceBase.requestTimeout,
      sendTimeout: const Duration(seconds: 300),
      receiveTimeout: ApiServiceBase.requestTimeout,
    ));
    final file = File(zipPath);
    if (!file.existsSync()) throw Exception('Файл архива не найден');

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(zipPath, filename: path.basename(zipPath)),
    });

    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/api/inspections/upload-archive',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.json,
        ),
        onSendProgress: onProgress,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data ?? {};
      }
      final detail = response.data?['detail'] ?? 'Код ${response.statusCode}';
      throw Exception(detail is List ? detail.map((e) => e.toString()).join('; ') : detail.toString());
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final data = e.response?.data;
      dynamic detail = data is Map ? data['detail'] : null;
      if (detail == null) {
        detail = e.message ?? 'Ошибка сети или сервера';
      } else if (detail is List) {
        detail = detail.map((x) => x.toString()).join('; ');
      } else {
        detail = detail.toString();
      }
      final msg = statusCode != null
          ? 'Сервер вернул $statusCode: $detail'
          : detail.toString();
      throw Exception(msg);
    }
  }

  Future<List<Map<String, dynamic>>> getInspections(String? equipmentId) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final uri = equipmentId != null
          ? Uri.parse('${ApiServiceBase.baseUrl}/api/inspections?equipment_id=$equipmentId')
          : Uri.parse('${ApiServiceBase.baseUrl}/api/inspections');

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
        Uri.parse('${ApiServiceBase.baseUrl}/api/questionnaires/$questionnaireId/ndt-methods'),
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
        Uri.parse('${ApiServiceBase.baseUrl}/api/questionnaires/$questionnaireId'),
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
          '${ApiServiceBase.baseUrl}/api/questionnaires/$questionnaireId/documents/$documentNumber/upload');

      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';

      final ext = path.extension(filePath).toLowerCase();
      final MediaType? contentType = _contentTypeFromExtension(ext);
      final file = await http.MultipartFile.fromPath(
        'file',
        filePath,
        filename: fileName,
        contentType: contentType,
      );
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

  Future<Map<String, dynamic>> uploadNdtMethodPhoto({
    required String questionnaireId,
    required String methodId,
    required String filePath,
    bool annotated = false,
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }
      final uri = Uri.parse(
        '${ApiServiceBase.baseUrl}/api/questionnaires/$questionnaireId/ndt-methods/$methodId/photos/upload?annotated=$annotated',
      );
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      final file = await http.MultipartFile.fromPath('file', filePath);
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
      throw Exception('Error uploading NDT photo: $e');
    }
  }

  Future<Map<String, dynamic>> uploadNdtMethodPhotoForInspection({
    required String inspectionId,
    required String methodId,
    required String filePath,
    bool annotated = false,
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }
      final uri = Uri.parse(
        '${ApiServiceBase.baseUrl}/api/inspections/$inspectionId/ndt-methods/$methodId/photos/upload?annotated=$annotated',
      );
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      final file = await http.MultipartFile.fromPath('file', filePath);
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
      throw Exception('Error uploading NDT photo: $e');
    }
  }

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
        Uri.parse('${ApiServiceBase.baseUrl}/api/questionnaires/$questionnaireId/documents'),
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
            '${ApiServiceBase.baseUrl}/api/questionnaires/$questionnaireId/documents/$documentNumber'),
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
        Uri.parse('${ApiServiceBase.baseUrl}/api/inspections/$inspectionId/equipment'),
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

  Future<List<Map<String, dynamic>>> getInspectionEquipment(String inspectionId) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final response = await http.get(
        Uri.parse('${ApiServiceBase.baseUrl}/api/inspections/$inspectionId/equipment'),
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

  Future<Map<String, dynamic>> getOpoSurvey(String opoId) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final response = await http.get(
        Uri.parse('${ApiServiceBase.baseUrl}/api/opos/$opoId/survey'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 401) {
        throw Exception('AUTH_INVALID');
      }

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }

      String errorMessage = 'Failed to load OPO survey: ${response.statusCode}';
      try {
        final errorData = json.decode(response.body);
        if (errorData is Map && errorData['detail'] != null) {
          errorMessage = errorData['detail'].toString();
        }
      } catch (_) {}
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('Error fetching OPO survey: $e');
    }
  }

  Future<void> updateOpoSurvey({
    required String opoId,
    required Map<String, dynamic> surveyData,
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final response = await http.put(
        Uri.parse('${ApiServiceBase.baseUrl}/api/opos/$opoId/survey'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'survey_data': surveyData}),
      );

      if (response.statusCode == 401) {
        throw Exception('AUTH_INVALID');
      }

      if (response.statusCode == 200) {
        return;
      }

      String errorMessage = 'Failed to update OPO survey: ${response.statusCode}';
      try {
        final errorData = json.decode(response.body);
        if (errorData is Map && errorData['detail'] != null) {
          errorMessage = errorData['detail'].toString();
        }
      } catch (_) {}
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('Error updating OPO survey: $e');
    }
  }
}
