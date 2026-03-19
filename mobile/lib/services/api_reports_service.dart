part of 'api_service.dart';

mixin ApiReportsMixin on ApiServiceBase {
  Future<String?> getVesselTemplate(String templateName) async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final response = await http.get(
        Uri.parse('${ApiServiceBase.baseUrl}/api/vessel-templates/$templateName'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$templateName');
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Ошибка загрузки шаблона: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка получения шаблона: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getVesselTemplates() async {
    try {
      final authService = AuthService();
      final token = await authService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final response = await http.get(
        Uri.parse('${ApiServiceBase.baseUrl}/api/vessel-templates'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['templates'] ?? []);
      } else {
        return [];
      }
    } catch (e) {
      print('Ошибка получения списка шаблонов: $e');
      return [];
    }
  }
}
