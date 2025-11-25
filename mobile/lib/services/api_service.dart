import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/equipment.dart';
import '../models/vessel_checklist.dart';

class ApiService {
  // TODO: Заменить на реальный URL сервера
  static const String baseUrl = 'http://5.129.203.182:8000';

  // Получить список оборудования
  Future<List<Equipment>> getEquipmentList() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/equipment'),
        headers: {'Content-Type': 'application/json'},
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
}
