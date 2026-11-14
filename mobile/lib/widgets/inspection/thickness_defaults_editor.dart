import 'package:flutter/material.dart';
import '../../models/vessel_checklist.dart';

/// Reference thicknesses belong to the vessel, measured thickness belongs to a point.
class ThicknessDefaultsEditor extends StatefulWidget {
  final ThicknessDefaults settings;
  final ValueChanged<ThicknessDefaults> onChanged;
  const ThicknessDefaultsEditor(
      {super.key, required this.settings, required this.onChanged});

  @override
  State<ThicknessDefaultsEditor> createState() =>
      _ThicknessDefaultsEditorState();
}

class _ThicknessDefaultsEditorState extends State<ThicknessDefaultsEditor> {
  late final nominal = TextEditingController(
      text: widget.settings.nominalThickness?.toString() ?? '');
  late final minimum = TextEditingController(
      text: widget.settings.minAllowedThickness?.toString() ?? '');
  late final basis = TextEditingController(text: widget.settings.basis ?? '');
  @override
  void didUpdateWidget(covariant ThicknessDefaultsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.nominalThickness !=
            widget.settings.nominalThickness &&
        ThicknessDefaults.parse(nominal.text) !=
            widget.settings.nominalThickness)
      nominal.text = widget.settings.nominalThickness?.toString() ?? '';
    if (oldWidget.settings.minAllowedThickness !=
            widget.settings.minAllowedThickness &&
        ThicknessDefaults.parse(minimum.text) !=
            widget.settings.minAllowedThickness)
      minimum.text = widget.settings.minAllowedThickness?.toString() ?? '';
    if (basis.text != (widget.settings.basis ?? ''))
      basis.text = widget.settings.basis ?? '';
  }

  String? error(TextEditingController controller) =>
      controller.text.trim().isNotEmpty &&
              ThicknessDefaults.parse(controller.text) == null
          ? 'Введите положительное число, например 12,5'
          : null;
  void changed() {
    setState(() {});
    if (error(nominal) != null || error(minimum) != null) return;
    widget.onChanged(ThicknessDefaults(
        nominalThickness: ThicknessDefaults.parse(nominal.text),
        minAllowedThickness: ThicknessDefaults.parse(minimum.text),
        basis: basis.text));
  }

  @override
  void dispose() {
    nominal.dispose();
    minimum.dispose();
    basis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Общие толщины сосуда',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
            'Задайте один раз. В точках вводится только измеренная толщина. Индивидуальные значения элементов сохраняются.'),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('shared-nominal-thickness'),
          controller: nominal,
          decoration: InputDecoration(
              errorText: error(nominal),
              labelText: 'Номинальная толщина сосуда, мм',
              border: const OutlineInputBorder()),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => changed(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('shared-min-allowed-thickness'),
          controller: minimum,
          decoration: InputDecoration(
              errorText: error(minimum),
              labelText: 'Минимально допустимая толщина, мм',
              helperText: 'Из паспорта или расчёта на прочность',
              border: const OutlineInputBorder()),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => changed(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('shared-thickness-basis'),
          controller: basis,
          decoration: const InputDecoration(
              labelText: 'Паспорт / норматив / номер расчёта',
              border: OutlineInputBorder()),
          onChanged: (_) => changed(),
        ),
      ]);
}
