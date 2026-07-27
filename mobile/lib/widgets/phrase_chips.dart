import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Быстрые формулировки для полей заключения / описания дефектов.
class PhraseChips extends StatelessWidget {
  const PhraseChips({
    super.key,
    required this.onSelected,
    this.phrases = kDefaultConclusionPhrases,
  });

  final void Function(String phrase) onSelected;
  final List<String> phrases;

  static const List<String> kDefaultConclusionPhrases = [
    'Дефектов не выявлено',
    'Коррозия локальная',
    'Коррозия сплошная',
    'Состояние удовлетворительное',
    'Требуется ремонт',
    'Следы предыдущих ремонтов',
    'Механические повреждения отсутствуют',
    'Изоляция в удовлетворительном состоянии',
  ];

  static const List<String> kDefectPhrases = [
    'Коррозия локальная',
    'Коррозия язвенная',
    'Механическое повреждение',
    'Трещина',
    'Деформация',
    'Потеря металла',
    'Свищ',
    'Расслоение',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: phrases.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final p = phrases[i];
          return ActionChip(
            label: Text(p, style: const TextStyle(fontSize: 11)),
            backgroundColor: AppColors.darkSurface,
            side: const BorderSide(color: AppColors.darkBorder),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onPressed: () => onSelected(p),
          );
        },
      ),
    );
  }
}
