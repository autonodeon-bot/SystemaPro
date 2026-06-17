import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

/// Добавление записи в опытную базу.
class ExperienceBaseAddEntryScreen extends StatefulWidget {
  final String categoryCode;
  final String equipmentKind;
  final String equipmentMark;
  final String? equipmentId;
  final String? assignmentId;

  const ExperienceBaseAddEntryScreen({
    super.key,
    required this.categoryCode,
    required this.equipmentKind,
    this.equipmentMark = '',
    this.equipmentId,
    this.assignmentId,
  });

  @override
  State<ExperienceBaseAddEntryScreen> createState() =>
      _ExperienceBaseAddEntryScreenState();
}

class _ExperienceBaseAddEntryScreenState extends State<ExperienceBaseAddEntryScreen> {
  final _api = ApiService();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _entryType = 'note';
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_bodyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите текст записи'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.createExperienceBaseEntry(
        categoryCode: widget.categoryCode,
        equipmentKind: widget.equipmentKind,
        equipmentMark: widget.equipmentMark.isEmpty ? null : widget.equipmentMark,
        body: _bodyCtrl.text.trim(),
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        entryType: _entryType,
        equipmentId: widget.equipmentId,
        assignmentId: widget.assignmentId,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Запись добавлена в опытную базу'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
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
        title: const Text('Новая запись'),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${widget.equipmentKind} ${widget.equipmentMark}'.trim(),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _entryType,
            dropdownColor: const Color(0xFF1e293b),
            style: const TextStyle(color: Colors.white),
            decoration: _decoration('Тип записи'),
            items: const [
              DropdownMenuItem(value: 'note', child: Text('Заметка')),
              DropdownMenuItem(
                value: 'recommendation',
                child: Text('Рекомендация'),
              ),
              DropdownMenuItem(
                value: 'operator_feedback',
                child: Text('Отзыв эксплуатации'),
              ),
            ],
            onChanged: (v) => setState(() => _entryType = v ?? 'note'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _decoration('Заголовок (необязательно)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            style: const TextStyle(color: Colors.white),
            maxLines: 8,
            decoration: _decoration('Текст *'),
          ),
          if (widget.equipmentId != null) ...[
            const SizedBox(height: 12),
            Text(
              'Привязка к объекту: ${widget.equipmentId}',
              style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
      filled: true,
      fillColor: const Color(0xFF1e293b),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
  }
}
