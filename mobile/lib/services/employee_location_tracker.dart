import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'auth_service.dart';
import 'location_service.dart';

/// Фоновая отправка GPS координат на сервер раз в 5 минут (при наличии сети).
class EmployeeLocationTracker {
  EmployeeLocationTracker._();
  static final EmployeeLocationTracker instance = EmployeeLocationTracker._();

  static const Duration pingInterval = Duration(minutes: 5);

  final LocationService _location = LocationService();
  final AuthService _auth = AuthService();
  Timer? _timer;
  bool _inFlight = false;
  bool _started = false;

  bool get isRunning => _started;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    // Первый пинг сразу (не ждём 5 минут)
    unawaited(pingNow(force: true));
    _timer?.cancel();
    _timer = Timer.periodic(pingInterval, (_) {
      unawaited(pingNow());
    });
    debugPrint('EmployeeLocationTracker started (every ${pingInterval.inMinutes} min)');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    debugPrint('EmployeeLocationTracker stopped');
  }

  /// Отправить координаты, если есть токен и интернет.
  Future<bool> pingNow({bool force = false}) async {
    if (_inFlight) return false;
    _inFlight = true;
    try {
      final token = await _auth.getToken();
      if (token == null || token.isEmpty) return false;

      final online = await ApiService().checkConnection();
      if (!online) {
        debugPrint('EmployeeLocationTracker: нет сети — пропуск');
        return false;
      }

      // Экономия батареи: сначала lastKnown, при force — текущая позиция medium accuracy
      Map<String, double>? coords;
      if (force) {
        coords = await _location.getCurrentLocationMedium();
      }
      coords ??= await _location.getLastKnownLocation();
      coords ??= await _location.getCurrentLocationMedium();
      if (coords == null) {
        debugPrint('EmployeeLocationTracker: координаты недоступны');
        return false;
      }

      final uri = Uri.parse('${ApiService.baseUrl}/api/employee-locations/ping');
      final resp = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'latitude': coords['latitude'],
              'longitude': coords['longitude'],
              'accuracy': coords['accuracy'],
              'device_label': Platform.isAndroid
                  ? 'android'
                  : (Platform.isIOS ? 'ios' : 'mobile'),
            }),
          )
          .timeout(ApiService.requestTimeout);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        debugPrint('EmployeeLocationTracker: ping OK');
        return true;
      }
      debugPrint('EmployeeLocationTracker: ping HTTP ${resp.statusCode}');
      return false;
    } catch (e) {
      debugPrint('EmployeeLocationTracker: $e');
      return false;
    } finally {
      _inFlight = false;
    }
  }
}
