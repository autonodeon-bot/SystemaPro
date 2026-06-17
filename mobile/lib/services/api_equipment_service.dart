part of 'api_service.dart';

mixin ApiEquipmentMixin on ApiServiceBase {
  Future<List<Equipment>> getEquipmentList({int limit = 500, int offset = 0}) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final response = await http.get(
        Uri.parse('${ApiServiceBase.baseUrl}/api/equipment?limit=$limit&offset=$offset'),
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

  Future<List<Equipment>> getAllEquipment() async {
    final List<Equipment> allEquipment = [];
    int offset = 0;
    const batchSize = 500;

    while (true) {
      final batch = await getEquipmentList(limit: batchSize, offset: offset);
      allEquipment.addAll(batch);
      if (batch.length < batchSize) break;
      offset += batchSize;
    }

    return allEquipment;
  }

  Future<List<Map<String, dynamic>>> getEngineers() async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();

      final response = await http.get(
        Uri.parse('${ApiServiceBase.baseUrl}/api/engineers'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 401) {
        throw Exception('AUTH_INVALID');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List? ?? [];
        return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }

      String errorMessage =
          'Failed to load engineers: ${response.statusCode}';
      try {
        final errorData = json.decode(response.body);
        if (errorData['detail'] != null) {
          errorMessage = '${errorData['detail']} (${response.statusCode})';
        }
      } catch (_) {}
      throw Exception(errorMessage);
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        throw Exception(
            'Нет подключения к серверу. Проверьте интернет-соединение.');
      }
      throw Exception('Ошибка загрузки инженеров: $e');
    }
  }

  Future<Equipment> getEquipmentById(String id) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      final response = await http.get(
        Uri.parse('${ApiServiceBase.baseUrl}/api/equipment/$id'),
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

      if (body.isEmpty) return;

      final response = await http.put(
        Uri.parse('${ApiServiceBase.baseUrl}/api/equipment/$equipmentId'),
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

      setAttrIfNotEmpty('vessel_name', checklist.vesselName);
      setAttrIfNotEmpty('reg_number', checklist.regNumber);
      setAttrIfNotEmpty('manufacturer', checklist.manufacturer);
      setAttrIfNotEmpty('manufacture_year', checklist.manufactureYear);
      setAttrIfNotEmpty('diameter', checklist.diameter);
      setAttrIfNotEmpty('working_pressure', checklist.workingPressure);
      setAttrIfNotEmpty('wall_thickness', checklist.wallThickness);

      setAttrIfNotEmpty('organization', checklist.organization);

      final serial = checklist.serialNumber?.trim();

      await updateEquipment(
        equipmentId: equipmentId,
        serialNumber: (serial != null && serial.isNotEmpty) ? serial : null,
        attributes: attrs,
      );
    } catch (e) {
      rethrow;
    }
  }

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

      String url = '${ApiServiceBase.baseUrl}/api/verification-equipment';
      final List<String> params = [];
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

  Future<List<Map<String, dynamic>>> getOpos({String? enterpriseId}) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();

      Uri uri = Uri.parse('${ApiServiceBase.baseUrl}/api/opos');
      if (enterpriseId != null && enterpriseId.isNotEmpty) {
        uri = uri.replace(queryParameters: {'enterprise_id': enterpriseId});
      }

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 401) {
        throw Exception('AUTH_INVALID');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List? ?? [];
        return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }

      String errorMessage = 'Failed to load OPOs: ${response.statusCode}';
      try {
        final errorData = json.decode(response.body);
        if (errorData['detail'] != null) {
          errorMessage = '${errorData['detail']} (${response.statusCode})';
        }
      } catch (_) {}
      throw Exception(errorMessage);
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        throw Exception(
            'Нет подключения к серверу. Проверьте интернет-соединение.');
      }
      throw Exception('Ошибка загрузки ОПО: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getOposByEnterprise(String enterpriseId) async {
    return getOpos(enterpriseId: enterpriseId);
  }

  Future<void> updateEquipmentOpo({
    required String equipmentId,
    required String? opoId,
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();
      if (token == null) {
        throw Exception('Токен авторизации не найден');
      }

      final response = await http.put(
        Uri.parse('${ApiServiceBase.baseUrl}/api/equipment/$equipmentId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'opo_id': opoId,
        }),
      );

      if (response.statusCode == 401) {
        throw Exception('AUTH_INVALID');
      }

      if (response.statusCode != 200 && response.statusCode != 204) {
        String errorMessage = 'Failed to update equipment OPO: ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          if (errorData['detail'] != null) {
            errorMessage = errorData['detail'].toString();
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      throw Exception('Error updating equipment OPO: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getHierarchyEnterprises() async {
    return _hierarchyList('/api/hierarchy/enterprises');
  }

  Future<List<Map<String, dynamic>>> getHierarchyBranches(String enterpriseId) async {
    return _hierarchyList(
      '/api/hierarchy/branches?enterprise_id=$enterpriseId',
    );
  }

  Future<List<Map<String, dynamic>>> getHierarchyWorkshops(String branchId) async {
    return _hierarchyList('/api/hierarchy/workshops?branch_id=$branchId');
  }

  Future<Map<String, dynamic>> updateHierarchyEntity(
    String path,
    Map<String, dynamic> body,
  ) async {
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http.put(
      Uri.parse('${ApiServiceBase.baseUrl}$path'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseHierarchyError(response));
  }

  Future<void> deleteHierarchyEntity(String path) async {
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http.delete(
      Uri.parse('${ApiServiceBase.baseUrl}$path'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception(_parseHierarchyError(response));
    }
  }

  Future<void> deleteEquipmentById(String equipmentId) async {
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http.delete(
      Uri.parse('${ApiServiceBase.baseUrl}/api/equipment/$equipmentId'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Не удалось удалить оборудование: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> _hierarchyList(String path) async {
    final authService = AuthService();
    final token = await authService.getToken();
    final response = await http.get(
      Uri.parse('${ApiServiceBase.baseUrl}$path'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final items = data['items'] as List? ?? [];
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception(_parseHierarchyError(response));
  }

  String _parseHierarchyError(http.Response response) {
    try {
      final data = json.decode(response.body);
      if (data['detail'] != null) return data['detail'].toString();
    } catch (_) {}
    return 'Ошибка ${response.statusCode}';
  }
}
