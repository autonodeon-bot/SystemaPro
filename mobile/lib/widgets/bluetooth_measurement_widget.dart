import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp hide BluetoothConnectionState;
import '../services/bluetooth_measurement_service.dart';
import '../theme/app_colors.dart';

class BluetoothMeasurementWidget extends StatefulWidget {
  final InstrumentType instrumentType;
  final Function(MeasurementResult) onMeasurement;

  const BluetoothMeasurementWidget({
    super.key,
    this.instrumentType = InstrumentType.thicknessGauge,
    required this.onMeasurement,
  });

  @override
  State<BluetoothMeasurementWidget> createState() =>
      _BluetoothMeasurementWidgetState();
}

class _BluetoothMeasurementWidgetState
    extends State<BluetoothMeasurementWidget> {
  final _btService = BluetoothMeasurementService();
  BluetoothConnectionState _state = BluetoothConnectionState.disconnected;
  List<fbp.ScanResult> _devices = [];
  StreamSubscription? _stateSub;
  StreamSubscription? _devicesSub;
  StreamSubscription? _measurementSub;
  MeasurementResult? _lastMeasurement;

  @override
  void initState() {
    super.initState();
    _stateSub = _btService.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _devicesSub = _btService.devicesStream.listen((d) {
      if (mounted) setState(() => _devices = d);
    });
    _measurementSub = _btService.measurementStream.listen((m) {
      if (mounted) {
        setState(() => _lastMeasurement = m);
        widget.onMeasurement(m);
      }
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _devicesSub?.cancel();
    _measurementSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.darkSurface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _state == BluetoothConnectionState.connected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth,
                  color: _state == BluetoothConnectionState.connected
                      ? AppColors.success
                      : AppColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Bluetooth прибор',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                _buildActionButton(),
              ],
            ),
            if (_state == BluetoothConnectionState.connected &&
                _lastMeasurement != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.straighten,
                        color: AppColors.accent, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Последнее: ${_lastMeasurement!.value} ${_lastMeasurement!.unit}',
                      style: const TextStyle(
                          color: AppColors.accent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            if (_state == BluetoothConnectionState.scanning)
              ..._devices.map((d) => ListTile(
                    dense: true,
                    title: Text(
                      d.device.platformName.isNotEmpty
                          ? d.device.platformName
                          : 'Устройство ${d.device.remoteId}',
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                    ),
                    subtitle: Text(
                      'RSSI: ${d.rssi} dBm',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                    trailing: TextButton(
                      onPressed: () => _btService.connect(d.device,
                          type: widget.instrumentType),
                      child: const Text('Подключить'),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    switch (_state) {
      case BluetoothConnectionState.disconnected:
        return TextButton.icon(
          onPressed: () => _btService.startScan(),
          icon: const Icon(Icons.search, size: 16),
          label: const Text('Поиск'),
        );
      case BluetoothConnectionState.scanning:
        return TextButton.icon(
          onPressed: () => _btService.stopScan(),
          icon: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          label: const Text('Остановить'),
        );
      case BluetoothConnectionState.connecting:
        return const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2));
      case BluetoothConnectionState.connected:
        return TextButton.icon(
          onPressed: () => _btService.disconnect(),
          icon: const Icon(Icons.bluetooth_disabled, size: 16),
          label: const Text('Отключить'),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
        );
      case BluetoothConnectionState.error:
        return TextButton.icon(
          onPressed: () => _btService.startScan(),
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Повторить'),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
