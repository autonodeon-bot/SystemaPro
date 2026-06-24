import 'package:flutter/material.dart';
import '../../data/technical_report_form_registry.dart';
import '../../models/vessel_checklist.dart';
import 'inspection_form_fields.dart';

class InspectionSafetyDevicesSection extends StatelessWidget {
  final VesselChecklist checklist;
  final VoidCallback onStateChanged;

  const InspectionSafetyDevicesSection({
    super.key,
    required this.checklist,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final form = TechnicalReportFormRegistry.formForChecklist(checklist.reportFormId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionHeader(
          form.sectionHeader('zra', fallback: '5. ЗРА (Запорно-регулирующая арматура)'),
        ),
        buildAddItemButton('Добавить ЗРА', () => _showZraDialog(context)),
        ...checklist.zraItems.asMap().entries.map((e) {
          final idx = e.key;
          final item = e.value;
          return buildListItemCard(
            title: 'ЗРА №${idx + 1}',
            subtitle: [
              if (item.typeSize != null && item.typeSize!.isNotEmpty)
                'Тип/размер: ${item.typeSize}',
              if (item.serialNumber != null && item.serialNumber!.isNotEmpty)
                'Зав.№: ${item.serialNumber}',
              if (item.locationOnScheme != null &&
                  item.locationOnScheme!.isNotEmpty)
                'Место: ${item.locationOnScheme}',
            ].join(' • '),
            onDelete: () {
              checklist.zraItems.removeAt(idx);
              onStateChanged();
            },
            deleteContext: context,
          );
        }),
        const SizedBox(height: 24),
        buildSectionHeader(
          form.sectionHeader('sppk', fallback: '6. СППК (Система предохранительных клапанов)'),
        ),
        buildAddItemButton('Добавить СППК', () => _showSppkDialog(context)),
        ...checklist.sppkItems.asMap().entries.map((e) {
          final idx = e.key;
          final item = e.value;
          return buildListItemCard(
            title: 'СППК №${idx + 1}',
            subtitle: [
              if (item.typeSize != null && item.typeSize!.isNotEmpty)
                'Тип/размер: ${item.typeSize}',
              if (item.serialNumber != null && item.serialNumber!.isNotEmpty)
                'Зав.№: ${item.serialNumber}',
              if (item.locationOnScheme != null &&
                  item.locationOnScheme!.isNotEmpty)
                'Место: ${item.locationOnScheme}',
            ].join(' • '),
            onDelete: () {
              checklist.sppkItems.removeAt(idx);
              onStateChanged();
            },
            deleteContext: context,
          );
        }),
      ],
    );
  }

  Future<void> _showZraDialog(BuildContext context) async {
    final qty = TextEditingController();
    final typeSize = TextEditingController();
    final tech = TextEditingController();
    final serial = TextEditingController();
    final loc = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kInspectionDarkBg,
        title: const Text('Добавить ЗРА',
            style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildDialogTextField(qty, 'Кол-во'),
              buildDialogTextField(typeSize, 'Тип/размер'),
              buildDialogTextField(tech, 'Тех. №'),
              buildDialogTextField(serial, 'Зав. №'),
              buildDialogTextField(loc, 'Место на схеме'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Добавить')),
        ],
      ),
    );

    if (ok == true) {
      final item = ZraItem();
      item.quantity = qty.text.trim().isEmpty ? null : qty.text.trim();
      item.typeSize =
          typeSize.text.trim().isEmpty ? null : typeSize.text.trim();
      item.techNumber = tech.text.trim().isEmpty ? null : tech.text.trim();
      item.serialNumber =
          serial.text.trim().isEmpty ? null : serial.text.trim();
      item.locationOnScheme =
          loc.text.trim().isEmpty ? null : loc.text.trim();
      checklist.zraItems.add(item);
      onStateChanged();
    }
  }

  Future<void> _showSppkDialog(BuildContext context) async {
    final qty = TextEditingController();
    final typeSize = TextEditingController();
    final tech = TextEditingController();
    final serial = TextEditingController();
    final loc = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kInspectionDarkBg,
        title: const Text('Добавить СППК',
            style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildDialogTextField(qty, 'Кол-во'),
              buildDialogTextField(typeSize, 'Тип/размер'),
              buildDialogTextField(tech, 'Тех. №'),
              buildDialogTextField(serial, 'Зав. №'),
              buildDialogTextField(loc, 'Место на схеме'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Добавить')),
        ],
      ),
    );

    if (ok == true) {
      final item = SppkItem();
      item.quantity = qty.text.trim().isEmpty ? null : qty.text.trim();
      item.typeSize =
          typeSize.text.trim().isEmpty ? null : typeSize.text.trim();
      item.techNumber = tech.text.trim().isEmpty ? null : tech.text.trim();
      item.serialNumber =
          serial.text.trim().isEmpty ? null : serial.text.trim();
      item.locationOnScheme =
          loc.text.trim().isEmpty ? null : loc.text.trim();
      checklist.sppkItems.add(item);
      onStateChanged();
    }
  }
}
