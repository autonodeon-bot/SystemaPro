import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';

/// Опрессовка ГИ/ПИ — компактная форма; kind `pressure_test` для сервера.
class PressureTestQuickScreen extends StatefulWidget {
  /// Начальное значение: `ГИ` или `ПИ` (из мастера «Новый протокол»).
  final String? initialTestType;

  const PressureTestQuickScreen({super.key, this.initialTestType});

  @override
  State<PressureTestQuickScreen> createState() =>
      _PressureTestQuickScreenState();
}

class _PressureTestQuickScreenState extends State<PressureTestQuickScreen> {
  final _api = ApiService();
  final _sync = SyncService();
  final _dateCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _objectCtrl = TextEditingController();
  final _mediumCtrl = TextEditingController();
  final _pressureCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _resultCtrl = TextEditingController();
  String _testType = 'ГИ';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initialTestType?.trim();
    if (init == 'ПИ' || init == 'ГИ' || init == 'ПС/ГПМ') {
      _testType = init!;
    }
    _dateCtrl.text = intl.DateFormat('dd.MM.yyyy').format(DateTime.now());
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _locationCtrl.dispose();
    _objectCtrl.dispose();
    _mediumCtrl.dispose();
    _pressureCtrl.dispose();
    _durationCtrl.dispose();
    _resultCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _payload() => {
        'date': _dateCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
        'object_name': _objectCtrl.text.trim(),
        'test_type': _testType,
        'medium': _mediumCtrl.text.trim(),
        'pressure_mpa': _pressureCtrl.text.trim(),
        'duration': _durationCtrl.text.trim(),
        'result': _resultCtrl.text.trim(),
      };

  Future<void> _submit() async {
    if (_objectCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Укажите объект / линию'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final title =
        '${_objectCtrl.text.trim()} — опрессовка ($_testType)';
    try {
      final online = await _api.checkConnection();
      if (!online) {
        await _sync.saveStandaloneProtocolOffline(
          title: title,
          kind: 'pressure_test',
          payload: _payload(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Нет сети: протокол в очереди. Отправьте на экране «Синхронизация».',
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
        kind: 'pressure_test',
        payload: _payload(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Опрессовка записана на сервере'),
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
        title: const Text('Опрессовка'),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field('Дата', _dateCtrl),
          _field('Место', _locationCtrl),
          _field('Объект / линия *', _objectCtrl),
          DropdownButtonFormField<String>(
            value: _testType,
            dropdownColor: const Color(0xFF1e293b),
            decoration: InputDecoration(
              labelText: 'Тип испытания',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'ГИ', child: Text('Гидравлические (ГИ)')),
              DropdownMenuItem(value: 'ПИ', child: Text('Пневматические (ПИ)')),
              DropdownMenuItem(
                value: 'ПС/ГПМ',
                child: Text('Испытание ПС и ГПМ (статика и динамика)'),
              ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _testType = v);
            },
          ),
          const SizedBox(height: 12),
          _field('Среда (вода, воздух…)', _mediumCtrl),
          _field('Давление (МПа или по месту)', _pressureCtrl),
          _field('Длительность', _durationCtrl),
          _field('Результат / вывод', _resultCtrl, maxLines: 3),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.darkPrimary,
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
