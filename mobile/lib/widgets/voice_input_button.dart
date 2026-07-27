import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../theme/app_colors.dart';

/// Кнопка голосового ввода (микрофон) для текстовых полей.
/// При недоступности STT показывает SnackBar с подсказкой.
class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.onResult,
    this.localeId = 'ru_RU',
    this.tooltip = 'Голосовой ввод',
  });

  final void Function(String text) onResult;
  final String localeId;
  final String tooltip;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  bool _available = false;
  bool _inited = false;

  Future<void> _ensureInit() async {
    if (_inited) return;
    _available = await _speech.initialize(
      onError: (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Голос: ${e.errorMsg}')),
          );
        }
        if (mounted) setState(() => _listening = false);
      },
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _listening = false);
        }
      },
    );
    _inited = true;
  }

  Future<void> _toggle() async {
    await _ensureInit();
    if (!_available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Распознавание речи недоступно. Проверьте разрешение микрофона.',
            ),
          ),
        );
      }
      return;
    }
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      localeId: widget.localeId,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: false,
      onResult: (r) {
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          widget.onResult(r.recognizedWords.trim());
        }
      },
    );
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: Icon(
        _listening ? Icons.mic : Icons.mic_none,
        color: _listening ? AppColors.danger : AppColors.accent,
        size: 22,
      ),
      onPressed: _toggle,
    );
  }
}
