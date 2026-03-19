part of 'api_service.dart';

mixin ApiAssignmentsMixin on ApiServiceBase {
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

      String url = '${ApiServiceBase.baseUrl}/api/assignments';
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
        Uri.parse('${ApiServiceBase.baseUrl}/api/assignments/$assignmentId'),
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
        Uri.parse('${ApiServiceBase.baseUrl}/api/assignments/$assignmentId/equipment'),
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
        Uri.parse('${ApiServiceBase.baseUrl}/api/assignments/$assignmentId'),
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

  Future<List<dynamic>> getAssignmentsDelta({String? since}) async {
    await ensureValidToken();
    final authService = AuthService();
    final token = await authService.getToken();
    if (token == null) {
      throw Exception('Токен авторизации не найден');
    }

    String url = '${ApiServiceBase.baseUrl}/api/assignments/sync';
    if (since != null) {
      url += '?since=$since';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is List) return decoded;
      if (decoded is Map && decoded['items'] is List) {
        return decoded['items'] as List;
      }
      return [];
    }
    throw Exception('Ошибка синхронизации заданий: ${response.statusCode}');
  }
}
