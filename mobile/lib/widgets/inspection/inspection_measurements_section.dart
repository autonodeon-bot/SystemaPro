import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../models/vessel_checklist.dart';
import '../../models/equipment.dart';
import '../../data/checklist_constants.dart';
import '../../services/image_resize_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as Path;
import 'inspection_form_fields.dart';

class InspectionMeasurementsSection extends StatelessWidget {
  final VesselChecklist checklist;
  final File? controlSchemeImage;
  final Equipment equipment;
  final VoidCallback onStateChanged;
  final void Function(List<ThicknessMeasurement> measurements, File? image)
      onThicknessSave;
  final void Function(int schemeIndex, List<ThicknessMeasurement> measurements, File? image)?
      onUztSchemeSave;

  const InspectionMeasurementsSection({
    super.key,
    required this.checklist,
    required this.controlSchemeImage,
    required this.equipment,
    required this.onStateChanged,
    required this.onThicknessSave,
    this.onUztSchemeSave,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Раздел 7: Измерительный контроль ---
        buildSectionHeader('7. Измерительный контроль'),
        buildSubsectionHeader('Овальность'),
        buildAddItemButton('Добавить измерение овальности',
            () => _showOvalityDialog(context)),
        ...checklist.ovalityMeasurements.asMap().entries.map((e) {
          final idx = e.key;
          final m = e.value;
          return buildListItemCard(
            title: 'Овальность, сечение ${m.sectionNumber}',
            subtitle: [
              if (m.maxDiameter != null) 'Dmax=${m.maxDiameter}',
              if (m.minDiameter != null) 'Dmin=${m.minDiameter}',
              if (m.deviationPercent != null) 'Δ%=${m.deviationPercent}',
            ].join(' • '),
            onTap: () =>
                _showOvalityDialog(context, editM: m, editIndex: idx),
            onDelete: () {
              checklist.ovalityMeasurements.removeAt(idx);
              onStateChanged();
            },
            deleteContext: context,
          );
        }),
        buildSubsectionHeader('Прогиб'),
        buildAddItemButton('Добавить измерение прогиба',
            () => _showDeflectionDialog(context)),
        ...checklist.deflectionMeasurements.asMap().entries.map((e) {
          final idx = e.key;
          final m = e.value;
          return buildListItemCard(
            title: 'Прогиб, участок ${m.sectionNumber}',
            subtitle: [
              if (m.deflectionMm != null) 'мм=${m.deflectionMm}',
              if (m.deflectionPercent != null) '%=${m.deflectionPercent}',
            ].join(' • '),
            onDelete: () {
              checklist.deflectionMeasurements.removeAt(idx);
              onStateChanged();
            },
            deleteContext: context,
          );
        }),

        const SizedBox(height: 24),

        // --- Раздел 8: Твёрдость ---
        buildSectionHeader('8. Результаты контроля твердости'),
        buildAddItemButton('Добавить измерение твердости',
            () => _showHardnessDialog(context)),
        ...checklist.hardnessTests.asMap().entries.map((e) {
          final idx = e.key;
          final t = e.value;
          return buildListItemCard(
            title: 'Твердость, шов ${t.weldNumber}',
            subtitle: [
              if (t.areaNumber != null && t.areaNumber!.isNotEmpty)
                'Участок: ${t.areaNumber}',
              if (t.hardnessBase != null && t.hardnessBase!.isNotEmpty)
                'Осн: ${t.hardnessBase}',
              if (t.hardnessWeld != null && t.hardnessWeld!.isNotEmpty)
                'Шов: ${t.hardnessWeld}',
              if (t.hardnessHaz != null && t.hardnessHaz!.isNotEmpty)
                'ЗТВ: ${t.hardnessHaz}',
            ].join(' • '),
            onDelete: () {
              checklist.hardnessTests.removeAt(idx);
              onStateChanged();
            },
            deleteContext: context,
          );
        }),

        const SizedBox(height: 24),

        // --- Раздел 9: ПВК (МК) и УЗК ---
        buildSectionHeader('9. Результаты ПВК (МК) и УЗК'),
        buildAddItemButton('Добавить сварное соединение',
            () => _showWeldInspectionDialog(context)),
        ...checklist.weldInspections.asMap().entries.map((e) {
          final idx = e.key;
          final w = e.value;
          return buildListItemCard(
            title: 'Сварное соединение ${w.weldNumber}',
            subtitle: [
              if (w.pvkDefect != null && w.pvkDefect!.isNotEmpty)
                'ПВК/МК: ${w.pvkDefect}',
              if (w.uzkDefect != null && w.uzkDefect!.isNotEmpty)
                'УЗК: ${w.uzkDefect}',
              if (w.xPercent != null && w.yPercent != null)
                'Схема: ${w.xPercent!.toStringAsFixed(0)}%, ${w.yPercent!.toStringAsFixed(0)}%',
              if (w.conclusion != null && w.conclusion!.isNotEmpty)
                'Заключение: ${w.conclusion}',
            ].where((s) => s.isNotEmpty).join(' • '),
            onTap: () => _showWeldInspectionDialog(context,
                editWeld: w, editIndex: idx),
            onDelete: () {
              checklist.weldInspections.removeAt(idx);
              onStateChanged();
            },
            deleteContext: context,
          );
        }),

        const SizedBox(height: 24),

        // --- Раздел 10: УЗТ (множественные схемы контроля, П.3.2) ---
        buildSectionHeader('10. УЗТ (Ультразвуковая толщинометрия)'),
        // Существующая одиночная схема (обратная совместимость)
        if (checklist.uztSchemes.isEmpty) ...[
          _buildControlSchemePhoto(context),
          buildAddItemButton('Открыть карту замеров', () async {
            final result = await context.push<Map<String, dynamic>>(
              '/thickness-measurement',
              extra: {
                'schemeImage': controlSchemeImage,
                'existingMeasurements': checklist.thicknessMeasurements,
                'equipment': equipment,
              },
            );
            if (result != null) {
              final measurements =
                  result['measurements'] as List<ThicknessMeasurement>?;
              final image = result['image'] as File?;
              if (measurements != null) {
                onThicknessSave(measurements, image);
              }
            }
          }),
          const SizedBox(height: 8),
          buildAddItemButton(
              '+ Добавить ещё одну схему контроля УЗТ',
              () => _addUztScheme(context)),
        ] else ...[
          // Режим множественных схем
          ...checklist.uztSchemes.asMap().entries.map((e) {
            final idx = e.key;
            final scheme = e.value;
            return _buildUztSchemeCard(context, idx, scheme);
          }),
          const SizedBox(height: 8),
          buildAddItemButton(
              '+ Добавить схему контроля УЗТ',
              () => _addUztScheme(context)),
        ],
      ],
    );
  }

  /// Добавить новую схему УЗТ
  Future<void> _addUztScheme(BuildContext context) async {
    // Если есть данные в старом поле — переносим в первую схему
    if (checklist.uztSchemes.isEmpty && checklist.thicknessMeasurements.isNotEmpty) {
      final first = UztScheme(label: 'Схема 1');
      first.schemeImagePath = checklist.controlSchemeImage;
      first.measurements = List.from(checklist.thicknessMeasurements);
      checklist.uztSchemes.add(first);
      checklist.thicknessMeasurements = [];
      checklist.controlSchemeImage = null;
    }
    final newScheme = UztScheme(label: 'Схема ${checklist.uztSchemes.length + 1}');
    checklist.uztSchemes.add(newScheme);
    onStateChanged();
  }

  /// Карточка одной схемы УЗТ
  Widget _buildUztSchemeCard(BuildContext context, int idx, UztScheme scheme) {
    final schemeFile = scheme.schemeImagePath != null
        ? File(scheme.schemeImagePath!)
        : null;
    final fileExists = schemeFile != null && schemeFile.existsSync();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kInspectionDarkBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  scheme.label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ),
              // Переименовать схему
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
                tooltip: 'Переименовать',
                onPressed: () => _renameUztScheme(context, idx, scheme),
              ),
              // Удалить схему
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                tooltip: 'Удалить схему',
                onPressed: () async {
                  final ok = await showConfirmDeleteDialog(context,
                      message: 'Удалить схему "${scheme.label}" со всеми замерами?');
                  if (ok) {
                    checklist.uztSchemes.removeAt(idx);
                    onStateChanged();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Фото/схема
          if (fileExists)
            GestureDetector(
              onTap: () => _showFullImage(context, schemeFile!),
              child: Container(
                height: 150,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kInspectionBorderColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(schemeFile!, fit: BoxFit.cover),
                ),
              ),
            ),
          // Кнопки для схемы
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickSchemeImage(context, idx, scheme),
                icon: const Icon(Icons.image, size: 16),
                label: Text(fileExists ? 'Заменить схему' : 'Добавить схему'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kInspectionAccentBlue,
                  side: const BorderSide(color: kInspectionAccentBlue),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await context.push<Map<String, dynamic>>(
                    '/thickness-measurement',
                    extra: {
                      'schemeImage': fileExists ? schemeFile : null,
                      'existingMeasurements': scheme.measurements,
                      'equipment': equipment,
                    },
                  );
                  if (result != null) {
                    final measurements =
                        result['measurements'] as List<ThicknessMeasurement>?;
                    final image = result['image'] as File?;
                    if (measurements != null) {
                      scheme.measurements = measurements;
                    }
                    if (image != null) {
                      scheme.schemeImagePath = image.path;
                    }
                    onStateChanged();
                    if (onUztSchemeSave != null) {
                      onUztSchemeSave!(idx, measurements ?? [], image);
                    }
                  }
                },
                icon: const Icon(Icons.grid_on, size: 16),
                label: Text('Карта замеров (${scheme.measurements.length})'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _renameUztScheme(BuildContext context, int idx, UztScheme scheme) async {
    final controller = TextEditingController(text: scheme.label);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kInspectionDarkBg,
        title: const Text('Название схемы', style: TextStyle(color: Colors.white)),
        content: buildDialogTextField(controller, 'Название'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      scheme.label = controller.text.trim();
      onStateChanged();
    }
  }

  Future<void> _pickSchemeImage(BuildContext context, int idx, UztScheme scheme) async {
    final picker = ImagePicker();
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kInspectionDarkBg,
        title: const Text('Источник схемы', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: const Text('Камера'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const Text('Галерея'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (source == null) return;
    try {
      final picked = await picker.pickImage(source: source, imageQuality: 80);
      if (picked == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final storageDir = Directory(Path.join(dir.path, 'offline_documents'));
      if (!await storageDir.exists()) await storageDir.create(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final resized = await ImageResizeService.resizeIfNeeded(picked.path);
      final target = Path.join(storageDir.path, 'uzt_scheme_${idx}_$ts.jpg');
      await File(resized).copy(target);
      scheme.schemeImagePath = target;
      onStateChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки схемы: $e')),
        );
      }
    }
  }

  void _showFullImage(BuildContext context, File image) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.file(image, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 8,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlSchemePhoto(BuildContext context) {
    if (controlSchemeImage == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Схема контроля',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              if (!controlSchemeImage!.existsSync()) return;
              showDialog(
                context: context,
                barrierColor: Colors.black87,
                builder: (ctx) => Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: EdgeInsets.zero,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: Center(
                          child: Image.file(controlSchemeImage!,
                              fit: BoxFit.contain),
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.of(ctx).padding.top + 8,
                        right: 16,
                        child: IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 28),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            child: Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kInspectionBorderColor),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(controlSchemeImage!, fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Диалоги ---

  Future<void> _showOvalityDialog(BuildContext context,
      {OvalityMeasurement? editM, int? editIndex}) async {
    final section = TextEditingController(
        text: editM?.sectionNumber ??
            '${checklist.ovalityMeasurements.length + 1}');
    final maxD = TextEditingController(
        text:
            editM?.maxDiameter != null ? editM!.maxDiameter!.toString() : '');
    final minD = TextEditingController(
        text:
            editM?.minDiameter != null ? editM!.minDiameter!.toString() : '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kInspectionDarkBg,
        title: Text(
            editM != null
                ? 'Редактировать овальность'
                : 'Овальность (сечение)',
            style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildDialogTextField(
                  section, 'Номер сечения (I, II, III, 1, 2...)'),
              buildDialogTextField(maxD, 'Макс. диаметр (мм)',
                  keyboard: TextInputType.number),
              buildDialogTextField(minD, 'Мин. диаметр (мм)',
                  keyboard: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(editM != null ? 'Сохранить' : 'Добавить')),
        ],
      ),
    );

    if (ok == true) {
      final maxVal = double.tryParse(maxD.text.replaceAll(',', '.'));
      final minVal = double.tryParse(minD.text.replaceAll(',', '.'));
      double? dev;
      if (maxVal != null && minVal != null && maxVal != 0) {
        dev = ((maxVal - minVal) / maxVal) * 100.0;
      }
      final m = OvalityMeasurement(
        sectionNumber: section.text.trim().isEmpty
            ? '${checklist.ovalityMeasurements.length + 1}'
            : section.text.trim(),
        maxDiameter: maxVal,
        minDiameter: minVal,
        deviationPercent: dev,
      );
      if (editIndex != null) {
        checklist.ovalityMeasurements[editIndex] = m;
      } else {
        checklist.ovalityMeasurements.add(m);
      }
      onStateChanged();
    }
  }

  Future<void> _showDeflectionDialog(BuildContext context) async {
    final section = TextEditingController(
        text: '${checklist.deflectionMeasurements.length + 1}');
    final mm = TextEditingController();
    final pct = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kInspectionDarkBg,
        title:
            const Text('Прогиб', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildDialogTextField(section, 'Номер участка'),
              buildDialogTextField(mm, 'Прогиб (мм)',
                  keyboard: TextInputType.number),
              buildDialogTextField(pct, 'Прогиб (%)',
                  keyboard: TextInputType.number),
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
      checklist.deflectionMeasurements.add(
        DeflectionMeasurement(
          sectionNumber: section.text.trim().isEmpty
              ? '${checklist.deflectionMeasurements.length + 1}'
              : section.text.trim(),
          deflectionMm: double.tryParse(mm.text.replaceAll(',', '.')),
          deflectionPercent:
              double.tryParse(pct.text.replaceAll(',', '.')),
        ),
      );
      onStateChanged();
    }
  }

  Future<void> _showHardnessDialog(BuildContext context) async {
    final weld = TextEditingController();
    final area = TextEditingController();
    final allowedBase = TextEditingController();
    final allowedWeld = TextEditingController();
    final base = TextEditingController();
    final w = TextEditingController();
    final haz = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kInspectionDarkBg,
        title: const Text('Твердость',
            style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildDialogTextField(weld, 'Номер шва *'),
              buildDialogTextField(area, 'Номер участка'),
              buildDialogTextField(
                  allowedBase, 'Допустимая твердость (осн.)'),
              buildDialogTextField(
                  allowedWeld, 'Допустимая твердость (шов)'),
              buildDialogTextField(base, 'Твердость (осн.)'),
              buildDialogTextField(w, 'Твердость (шов)'),
              buildDialogTextField(haz, 'Твердость (ЗТВ)'),
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

    if (ok == true && weld.text.trim().isNotEmpty) {
      final t = HardnessTest(weldNumber: weld.text.trim());
      t.areaNumber = area.text.trim().isEmpty ? null : area.text.trim();
      t.allowedHardnessBase =
          allowedBase.text.trim().isEmpty ? null : allowedBase.text.trim();
      t.allowedHardnessWeld =
          allowedWeld.text.trim().isEmpty ? null : allowedWeld.text.trim();
      t.hardnessBase = base.text.trim().isEmpty ? null : base.text.trim();
      t.hardnessWeld = w.text.trim().isEmpty ? null : w.text.trim();
      t.hardnessHaz = haz.text.trim().isEmpty ? null : haz.text.trim();
      checklist.hardnessTests.add(t);
      onStateChanged();
    }
  }

  Future<void> _showWeldInspectionDialog(BuildContext context,
      {WeldInspection? editWeld, int? editIndex}) async {
    final weld = TextEditingController(text: editWeld?.weldNumber ?? '');
    final loc =
        TextEditingController(text: editWeld?.locationOnControlMap ?? '');
    final pvk = TextEditingController(text: editWeld?.pvkDefect ?? '');
    final uzk = TextEditingController(text: editWeld?.uzkDefect ?? '');
    final xPercent = TextEditingController(
        text: editWeld?.xPercent != null
            ? editWeld!.xPercent!.toStringAsFixed(1)
            : '');
    final yPercent = TextEditingController(
        text: editWeld?.yPercent != null
            ? editWeld!.yPercent!.toStringAsFixed(1)
            : '');
    String conclusion =
        editWeld?.conclusion ?? ChecklistConstants.weldConclusions.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kInspectionDarkBg,
        title: Text(
            editWeld != null
                ? 'Редактировать сварное соединение'
                : 'Сварное соединение',
            style: const TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (context, setInner) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildDialogTextField(weld, 'Номер шва *'),
                buildDialogTextField(loc, 'Место на карте контроля'),
                buildDialogTextField(pvk, 'Дефект (ПВК/МК)'),
                buildDialogTextField(uzk, 'Дефект (УЗК)'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: buildDialogTextField(xPercent, 'X % на схеме',
                          keyboard: TextInputType.number),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: buildDialogTextField(yPercent, 'Y % на схеме',
                          keyboard: TextInputType.number),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: conclusion,
                  decoration: const InputDecoration(
                    labelText: 'Заключение',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue)),
                  ),
                  dropdownColor: kInspectionDarkBg,
                  items: ChecklistConstants.weldConclusions
                      .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c,
                              style:
                                  const TextStyle(color: Colors.white))))
                      .toList(),
                  onChanged: (v) =>
                      setInner(() => conclusion = v ?? conclusion),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  Text(editWeld != null ? 'Сохранить' : 'Добавить')),
        ],
      ),
    );

    if (ok == true && weld.text.trim().isNotEmpty) {
      final w = editWeld ?? WeldInspection(weldNumber: weld.text.trim());
      w.weldNumber = weld.text.trim();
      w.locationOnControlMap =
          loc.text.trim().isEmpty ? null : loc.text.trim();
      w.pvkDefect = pvk.text.trim().isEmpty ? null : pvk.text.trim();
      w.uzkDefect = uzk.text.trim().isEmpty ? null : uzk.text.trim();
      w.conclusion = conclusion;
      final xVal =
          double.tryParse(xPercent.text.trim().replaceAll(',', '.'));
      final yVal =
          double.tryParse(yPercent.text.trim().replaceAll(',', '.'));
      w.xPercent = (xVal != null && xVal >= 0 && xVal <= 100) ? xVal : null;
      w.yPercent = (yVal != null && yVal >= 0 && yVal <= 100) ? yVal : null;
      if (editIndex != null) {
        checklist.weldInspections[editIndex] = w;
      } else {
        checklist.weldInspections.add(w);
      }
      onStateChanged();
    }
  }
}
