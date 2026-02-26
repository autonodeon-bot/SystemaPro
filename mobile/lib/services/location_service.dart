import 'package:geolocator/geolocator.dart';

/// Сервис для работы с GPS координатами
class LocationService {
  /// Проверка доступа к геолокации.
  /// Возвращает null, если всё готово; иначе человекочитаемую причину.
  Future<String?> ensureLocationAccess({bool openSettingsOnFailure = false}) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (openSettingsOnFailure) {
        await Geolocator.openLocationSettings();
      }
      return 'На устройстве выключена геолокация';
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Нет разрешения на доступ к геолокации';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (openSettingsOnFailure) {
        await Geolocator.openAppSettings();
      }
      return 'Доступ к геолокации запрещен навсегда (включите в настройках)';
    }

    return null;
  }

  /// Получить текущие GPS координаты
  Future<Map<String, double>?> getCurrentLocation() async {
    try {
      final issue = await ensureLocationAccess();
      if (issue != null) {
        return null;
      }

      // Получаем координаты
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
      };
    } catch (e) {
      print('Ошибка получения координат: $e');
      return null;
    }
  }

  /// Получить последние известные координаты (быстрее, но менее точно)
  Future<Map<String, double>?> getLastKnownLocation() async {
    try {
      final issue = await ensureLocationAccess();
      if (issue != null) {
        return null;
      }
      Position? position = await Geolocator.getLastKnownPosition();
      if (position == null) {
        return await getCurrentLocation();
      }
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
      };
    } catch (e) {
      return null;
    }
  }

  /// Форматировать координаты для отображения
  String formatCoordinates(Map<String, double>? coords) {
    if (coords == null) return 'Не определено';
    return '${coords['latitude']!.toStringAsFixed(6)}, ${coords['longitude']!.toStringAsFixed(6)}';
  }
}
