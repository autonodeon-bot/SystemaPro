import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Сервис для работы с GPS координатами
class LocationService {
  /// Получить текущие GPS координаты
  Future<Map<String, double>?> getCurrentLocation() async {
    try {
      // Проверяем разрешения
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
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
