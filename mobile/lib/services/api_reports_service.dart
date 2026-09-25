part of 'api_service.dart';

mixin ApiReportsMixin on ApiServiceBase {
  /// Returns the actual server-generated PDF, including the official Word form.
  Future<List<int>> generateInspectionPdf(String inspectionId) async {
    if (!await ensureValidToken()) throw Exception('Войдите в приложение');
    final token = await AuthService().getToken();
    final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
    final response = await http.post(Uri.parse('${ApiServiceBase.baseUrl}/api/reports/generate'),
      headers: headers, body: json.encode({'inspection_id': inspectionId,
        'report_type': 'TECHNICAL_REPORT', 'format': 'pdf', 'skip_validation': true}),
    ).timeout(const Duration(minutes: 5));
    if (response.statusCode != 200 && response.statusCode != 201) {
      final body = json.decode(response.body);
      throw Exception(body['detail'] ?? 'Не удалось сформировать PDF');
    }
    final reportId = json.decode(response.body)['id'];
    final pdf = await http.get(Uri.parse('${ApiServiceBase.baseUrl}/api/reports/$reportId/download?format=pdf'),
      headers: headers).timeout(ApiServiceBase.requestTimeout);
    if (pdf.statusCode != 200 || pdf.bodyBytes.length < 4 ||
        String.fromCharCodes(pdf.bodyBytes.take(4)) != '%PDF') {
      throw Exception('Сервер не вернул корректный PDF');
    }
    return pdf.bodyBytes;
  }

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
