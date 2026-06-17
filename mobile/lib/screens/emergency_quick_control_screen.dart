import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';

/// Аварийный внеплановый осмотр — минимальный набор полей, очередь офлайн.
class EmergencyQuickControlScreen extends StatefulWidget {
  const EmergencyQuickControlScreen({super.key});

  @override
  State<EmergencyQuickControlScreen> createState() =>
      _EmergencyQuickControlScreenState();
}

class _EmergencyQuickControlScreenState
    extends State<EmergencyQuickControlScreen> {
  final _api = ApiService();
  final _sync = SyncService();
  final _dateCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _objectCtrl = TextEditingController();
  final _situationCtrl = TextEditingController();
  final _actionsCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dateCtrl.text = intl.DateFormat('dd.MM.yyyy').format(DateTime.now());
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _locationCtrl.dispose();
    _objectCtrl.dispose();
    _situationCtrl.dispose();
    _actionsCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _payload() => {
        'mode': 'emergency',
        'date': _dateCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
        'object_name': _objectCtrl.text.trim(),
        'situation': _situationCtrl.text.trim(),
        'actions_taken': _actionsCtrl.text.trim(),
      };

  Future<void> _submit() async {
    if (_objectCtrl.text.trim().isEmpty ||
        _situationCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Укажите объект и описание ситуации'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final title = _objectCtrl.text.trim();
    try {
      final online = await _api.checkConnection();
      if (!online) {
        await _sync.saveStandaloneProtocolOffline(
          title: title,
          kind: 'emergency_inspection',
          payload: _payload(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Нет сети: запись сохранена локально. Отправьте на экране «Синхронизация».',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      await _api.submitStandaloneProtocol(
        title: title,
        kind: 'emergency_inspection',
        payload: _payload(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Аварийный осмотр отправлен на сервер'),
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
        title: const Text('Аварийный осмотр'),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field('Дата', _dateCtrl),
          _field('Место', _locationCtrl),
          _field('Объект *', _objectCtrl),
          _field('Описание ситуации *', _situationCtrl, maxLines: 4),
          _field('Принятые меры', _actionsCtrl, maxLines: 3),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить / отправить'),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.darkPrimary),
          ),
        ),
      ),
    );
  }
}
