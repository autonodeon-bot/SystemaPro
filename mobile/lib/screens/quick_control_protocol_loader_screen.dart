import 'package:flutter/material.dart';
import '../services/quick_control_template_service.dart';
import '../theme/app_colors.dart';
import 'custom_protocol_screen.dart';

/// Загрузка шаблона быстрого контроля и открытие формы конструктора.
class QuickControlProtocolLoaderScreen extends StatefulWidget {
  final String quickControlCode;
  final String screenTitle;

  const QuickControlProtocolLoaderScreen({
    super.key,
    required this.quickControlCode,
    required this.screenTitle,
  });

  @override
  State<QuickControlProtocolLoaderScreen> createState() =>
      _QuickControlProtocolLoaderScreenState();
}

class _QuickControlProtocolLoaderScreenState
    extends State<QuickControlProtocolLoaderScreen> {
  final _service = QuickControlTemplateService();
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final template =
          await _service.getTemplate(widget.quickControlCode);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CustomProtocolScreen(
            template: template,
            protocolKind: 'quick_control',
            quickControlCode: widget.quickControlCode,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: Text(widget.screenTitle),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.accent),
                    SizedBox(height: 16),
                    Text(
                      'Загрузка шаблона протокола…',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.orange, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _error ?? 'Шаблон недоступен',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
