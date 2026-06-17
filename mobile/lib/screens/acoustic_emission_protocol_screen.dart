import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../models/equipment.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';

/// Протокол акустико-эмиссионного контроля (АЭ) — отдельный сценарий из матрицы xlsx.
class AcousticEmissionProtocolScreen extends StatefulWidget {
  final Equipment? equipment;
  final String? assignmentId;

  const AcousticEmissionProtocolScreen({
    super.key,
    this.equipment,
    this.assignmentId,
  });

  @override
  State<AcousticEmissionProtocolScreen> createState() =>
      _AcousticEmissionProtocolScreenState();
}

class _AcousticEmissionProtocolScreenState
    extends State<AcousticEmissionProtocolScreen> {
  final _api = ApiService();
  final _sync = SyncService();
  final _dateCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _objectCtrl = TextEditingController();
  final _zonesCtrl = TextEditingController();
  final _sensorsCtrl = TextEditingController();
  final _activityCtrl = TextEditingController();
  final _resultCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dateCtrl.text = intl.DateFormat('dd.MM.yyyy').format(DateTime.now());
    final eq = widget.equipment;
    if (eq != null) {
      _objectCtrl.text = eq.name ?? '';
      final loc = eq.location;
      if (loc != null && loc.isNotEmpty) {
        _locationCtrl.text = loc;
      }
    }
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _locationCtrl.dispose();
    _objectCtrl.dispose();
    _zonesCtrl.dispose();
    _sensorsCtrl.dispose();
    _activityCtrl.dispose();
    _resultCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _payload() => {
        'date': _dateCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
        'object_name': _objectCtrl.text.trim(),
        'equipment_id': widget.equipment?.id,
        'assignment_id': widget.assignmentId,
        'control_zones': _zonesCtrl.text.trim(),
        'sensors_layout': _sensorsCtrl.text.trim(),
        'emission_activity': _activityCtrl.text.trim(),
        'conclusion': _resultCtrl.text.trim(),
        'method': 'AE',
      };

  Future<void> _submit() async {
    if (_objectCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Укажите объект'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final title = '${_objectCtrl.text.trim()} — АЭ';
    try {
      final online = await _api.checkConnection();
      if (!online) {
        await _sync.saveStandaloneProtocolOffline(
          title: title,
          kind: 'acoustic_emission',
          payload: _payload(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Нет сети: протокол в очереди синхронизации'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      await _api.submitStandaloneProtocol(
        title: title,
        kind: 'acoustic_emission',
        payload: _payload(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Протокол АЭ сохранён'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: const Text('Акустико-эмиссионный контроль (АЭ)'),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field('Дата', _dateCtrl),
          _field('Место', _locationCtrl),
          _field('Объект *', _objectCtrl),
          _field('Зоны контроля', _zonesCtrl, maxLines: 2),
          _field('Схема установки датчиков', _sensorsCtrl, maxLines: 2),
          _field('Активность АЭ / пороги', _activityCtrl, maxLines: 3),
          _field('Заключение', _resultCtrl, maxLines: 3),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.darkPrimary,
              minimumSize: const Size.fromHeight(48),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Сохранить протокол'),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.darkPrimary),
          ),
        ),
      ),
    );
  }
}
