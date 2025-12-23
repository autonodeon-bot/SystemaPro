import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Сервис для интеграции с измерительными приборами через Bluetooth
class InstrumentService {
  static const String _serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
  static const String _characteristicUuid = '0000fff1-0000-1000-8000-00805f9b34fb';
  
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription<List<int>>? _dataSubscription;
  
  /// Поиск доступных приборов
  Future<List<BluetoothDevice>> scanForDevices({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      // Проверка поддержки Bluetooth
      if (await FlutterBluePlus.isSupported == false) {
        throw Exception('Bluetooth не поддерживается на этом устройстве');
      }
      
      // Проверка включенности Bluetooth
      if (await FlutterBluePlus.isOn == false) {
        throw Exception('Bluetooth выключен. Пожалуйста, включите Bluetooth');
      }
      
      // Начать сканирование
      await FlutterBluePlus.startScan(timeout: timeout);
      
      // Собрать найденные устройства
      final devices = <BluetoothDevice>[];
      await for (final scanResult in FlutterBluePlus.scanResults) {
        for (final result in scanResult) {
          if (!devices.contains(result.device)) {
            devices.add(result.device);
          }
        }
      }
      
      await FlutterBluePlus.stopScan();
      return devices;
    } catch (e) {
      await FlutterBluePlus.stopScan();
      throw Exception('Ошибка поиска устройств: $e');
    }
  }
  
  /// Подключиться к прибору
  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;
      
      // Найти сервис и характеристику
      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.toString().toLowerCase().contains('fff0')) {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase().contains('fff1')) {
              _characteristic = characteristic;
              break;
            }
          }
        }
      }
      
      if (_characteristic == null) {
        throw Exception('Не удалось найти характеристику для чтения данных');
      }
    } catch (e) {
      throw Exception('Ошибка подключения к устройству: $e');
    }
  }
  
  /// Отключиться от прибора
  Future<void> disconnect() async {
    try {
      await _dataSubscription?.cancel();
      _dataSubscription = null;
      
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        _connectedDevice = null;
      }
      
      _characteristic = null;
    } catch (e) {
      throw Exception('Ошибка отключения: $e');
    }
  }
  
  /// Читать данные с прибора
  Stream<List<int>> readData() {
    if (_characteristic == null) {
      throw Exception('Не подключено к устройству');
    }
    
    // Подписаться на уведомления
    _characteristic!.setNotifyValue(true);
    
    return _characteristic!.value;
  }
  
  /// Парсить данные толщиномера (пример для ультразвукового толщиномера)
  Map<String, dynamic>? parseThicknessMeterData(List<int> data) {
    try {
      if (data.length < 4) return null;
      
      // Пример парсинга (зависит от протокола прибора)
      // Обычно данные приходят в формате: [header, value_high, value_low, checksum]
      final value = (data[1] << 8) | data[2];
      final thickness = value / 100.0; // Предполагаем формат XX.XX мм
      
      return {
        'thickness': thickness,
        'unit': 'mm',
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return null;
    }
  }
  
  /// Парсить данные дефектоскопа (пример)
  Map<String, dynamic>? parseDefectoscopeData(List<int> data) {
    try {
      if (data.length < 6) return null;
      
      // Пример парсинга для дефектоскопа
      final amplitude = data[1];
      final depth = ((data[2] << 8) | data[3]) / 10.0;
      
      return {
        'amplitude': amplitude,
        'depth': depth,
        'unit': 'mm',
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return null;
    }
  }
  
  /// Проверить подключение
  bool isConnected() {
    return _connectedDevice != null && _characteristic != null;
  }
  
  /// Получить имя подключенного устройства
  String? getConnectedDeviceName() {
    return _connectedDevice?.name;
  }
}



