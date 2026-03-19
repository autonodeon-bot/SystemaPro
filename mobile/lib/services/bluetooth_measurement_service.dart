import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Поддерживаемые типы приборов
enum InstrumentType {
  thicknessGauge, // Толщиномер (УЗТ)
  hardnessTester, // Твердомер
  generic, // Универсальный
}

/// Результат измерения
class MeasurementResult {
  final double value;
  final String unit;
  final DateTime timestamp;
  final String? instrumentName;
  final String? instrumentSerial;

  MeasurementResult({
    required this.value,
    required this.unit,
    DateTime? timestamp,
    this.instrumentName,
    this.instrumentSerial,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'value': value,
        'unit': unit,
        'timestamp': timestamp.toIso8601String(),
        'instrument_name': instrumentName,
        'instrument_serial': instrumentSerial,
      };
}

/// Состояние подключения
enum BluetoothConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

/// Сервис интеграции с измерительными приборами по Bluetooth.
/// Поддерживает толщиномеры (УЗТ), твердомеры и универсальные приборы.
class BluetoothMeasurementService {
  static final BluetoothMeasurementService _instance =
      BluetoothMeasurementService._();
  factory BluetoothMeasurementService() => _instance;
  BluetoothMeasurementService._();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _dataCharacteristic;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _dataSubscription;

  final _stateController =
      StreamController<BluetoothConnectionState>.broadcast();
  final _measurementController = StreamController<MeasurementResult>.broadcast();
  final _devicesController = StreamController<List<ScanResult>>.broadcast();

  Stream<BluetoothConnectionState> get stateStream => _stateController.stream;
  Stream<MeasurementResult> get measurementStream =>
      _measurementController.stream;
  Stream<List<ScanResult>> get devicesStream => _devicesController.stream;

  BluetoothConnectionState _currentState = BluetoothConnectionState.disconnected;
  BluetoothConnectionState get currentState => _currentState;

  InstrumentType _instrumentType = InstrumentType.generic;

  final List<ScanResult> _discoveredDevices = [];

  /// Проверка доступности Bluetooth
  Future<bool> isAvailable() async {
    try {
      return await FlutterBluePlus.isSupported;
    } catch (e) {
      return false;
    }
  }

  /// Начать сканирование устройств
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (!await isAvailable()) {
      _updateState(BluetoothConnectionState.error);
      return;
    }

    _discoveredDevices.clear();
    _updateState(BluetoothConnectionState.scanning);

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (var r in results) {
        final idx = _discoveredDevices
            .indexWhere((d) => d.device.remoteId == r.device.remoteId);
        if (idx >= 0) {
          _discoveredDevices[idx] = r;
        } else {
          _discoveredDevices.add(r);
        }
      }
      _devicesController.add(List.from(_discoveredDevices));
    });

    await FlutterBluePlus.startScan(timeout: timeout);
    _updateState(BluetoothConnectionState.disconnected);
  }

  /// Остановить сканирование
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
  }

  /// Подключиться к устройству
  Future<bool> connect(BluetoothDevice device,
      {InstrumentType type = InstrumentType.generic}) async {
    try {
      _updateState(BluetoothConnectionState.connecting);
      _instrumentType = type;

      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;

      final services = await device.discoverServices();

      // Ищем характеристику с notify/indicate для приёма данных измерений
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.notify ||
              characteristic.properties.indicate) {
            _dataCharacteristic = characteristic;
            break;
          }
        }
        if (_dataCharacteristic != null) break;
      }

      if (_dataCharacteristic != null) {
        await _dataCharacteristic!.setNotifyValue(true);
        _dataSubscription =
            _dataCharacteristic!.onValueReceived.listen(_onDataReceived);
      }

      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState2.disconnected) {
          _updateState(BluetoothConnectionState.disconnected);
          _cleanup();
        }
      });

      _updateState(BluetoothConnectionState.connected);
      return true;
    } catch (e) {
      debugPrint('Bluetooth connection error: $e');
      _updateState(BluetoothConnectionState.error);
      return false;
    }
  }

  /// Отключиться
  Future<void> disconnect() async {
    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }
    _cleanup();
    _updateState(BluetoothConnectionState.disconnected);
  }

  /// Обработка данных от прибора
  void _onDataReceived(List<int> data) {
    try {
      final result = _parseData(data);
      if (result != null) {
        _measurementController.add(result);
      }
    } catch (e) {
      debugPrint('Data parse error: $e');
    }
  }

  /// Парсинг данных в зависимости от типа прибора
  MeasurementResult? _parseData(List<int> rawData) {
    if (rawData.isEmpty) return null;

    switch (_instrumentType) {
      case InstrumentType.thicknessGauge:
        return _parseThicknessGauge(rawData);
      case InstrumentType.hardnessTester:
        return _parseHardnessTester(rawData);
      case InstrumentType.generic:
        return _parseGeneric(rawData);
    }
  }

  /// Парсинг данных толщиномера.
  /// Большинство ультразвуковых толщиномеров передают значение как ASCII строку
  /// или как IEEE 754 float в 4 байтах.
  MeasurementResult? _parseThicknessGauge(List<int> data) {
    try {
      // ASCII строка (например, "12.45\r\n")
      final str = utf8.decode(data, allowMalformed: true).trim();
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(str);
      if (match != null) {
        final value = double.tryParse(match.group(1)!);
        if (value != null && value > 0 && value < 1000) {
          return MeasurementResult(
            value: value,
            unit: 'мм',
            instrumentName: _connectedDevice?.platformName,
          );
        }
      }

      // IEEE 754 float (4 bytes, little-endian)
      if (data.length >= 4) {
        final bytes = Uint8List.fromList(data.sublist(0, 4));
        final value = ByteData.view(bytes.buffer).getFloat32(0, Endian.little);
        if (value > 0 && value < 1000) {
          return MeasurementResult(
            value: double.parse(value.toStringAsFixed(2)),
            unit: 'мм',
            instrumentName: _connectedDevice?.platformName,
          );
        }
      }
    } catch (e) {
      debugPrint('Thickness gauge parse error: $e');
    }
    return null;
  }

  /// Парсинг данных твердомера
  MeasurementResult? _parseHardnessTester(List<int> data) {
    try {
      final str = utf8.decode(data, allowMalformed: true).trim();
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(str);
      if (match != null) {
        final value = double.tryParse(match.group(1)!);
        if (value != null && value > 0) {
          return MeasurementResult(
            value: value,
            unit: 'HB',
            instrumentName: _connectedDevice?.platformName,
          );
        }
      }
    } catch (e) {
      debugPrint('Hardness tester parse error: $e');
    }
    return null;
  }

  /// Универсальный парсинг
  MeasurementResult? _parseGeneric(List<int> data) {
    try {
      final str = utf8.decode(data, allowMalformed: true).trim();
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(str);
      if (match != null) {
        final value = double.tryParse(match.group(1)!);
        if (value != null) {
          return MeasurementResult(
            value: value,
            unit: '',
            instrumentName: _connectedDevice?.platformName,
          );
        }
      }
    } catch (e) {
      debugPrint('Generic parse error: $e');
    }
    return null;
  }

  void _updateState(BluetoothConnectionState state) {
    _currentState = state;
    _stateController.add(state);
  }

  void _cleanup() {
    _dataSubscription?.cancel();
    _connectionSubscription?.cancel();
    _dataCharacteristic = null;
    _connectedDevice = null;
  }

  void dispose() {
    _scanSubscription?.cancel();
    _dataSubscription?.cancel();
    _connectionSubscription?.cancel();
    _stateController.close();
    _measurementController.close();
    _devicesController.close();
  }
}
