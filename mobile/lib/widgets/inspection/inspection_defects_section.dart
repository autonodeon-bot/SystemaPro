import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as Path;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../data/technical_report_form_registry.dart';
import '../../models/vessel_checklist.dart';
import '../../services/image_resize_service.dart';
import 'inspection_form_fields.dart';

class InspectionDefectsSection extends StatelessWidget {
  final VesselChecklist checklist;
  final ImagePicker imagePicker;
  final VoidCallback onStateChanged;
  final Future<String> Function(String imagePath, {bool force}) maybeAddDateTimeGpsToPhoto;

  const InspectionDefectsSection({
    super.key,
    required this.checklist,
    required this.imagePicker,
    required this.onStateChanged,
    required this.maybeAddDateTimeGpsToPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final form = TechnicalReportFormRegistry.formForChecklist(checklist.reportFormId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionHeader(
          form.sectionHeader('defects', fallback: '11. Дефекты'),
        ),
        buildYesNoField(
            'has_local_deformations', 'Локально деформированные зоны',
            (value) {
          checklist.hasLocalDeformations = value == 'yes';
        }),
        buildYesNoField(
            'has_external_defects', 'Дефекты при наружном осмотре', (value) {
          checklist.hasExternalDefects = value == 'yes';
        }),
        buildYesNoField(
            'has_internal_defects', 'Дефекты при внутреннем осмотре',
            (value) {
          checklist.hasInternalDefects = value == 'yes';
        }),
        buildYesNoField('has_armature_defects', 'Дефекты арматуры', (value) {
          checklist.hasArmatureDefects = value == 'yes';
        }),
        const SizedBox(height: 12),
        _buildVisualDefectsSection(context),
      ],
    );
  }

  Widget _buildVisualDefectsSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kInspectionDarkBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Дефекты ВИК (фото/замеры)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (checklist.visualDefects.isEmpty)
            const Text(
              'Дефекты не добавлены',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            )
          else
            Column(
              children:
                  checklist.visualDefects.asMap().entries.map((entry) {
                final idx = entry.key;
                final d = entry.value;
                return ListTile(
                  dense: true,
                  title: Text(
                    d.defectType ?? 'Дефект',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    [
                      if (d.zone != null && d.zone!.isNotEmpty)
                        d.zone == 'internal' ? 'Внутренний осмотр' : 'Наружный осмотр',
                      if (d.location != null && d.location!.isNotEmpty)
                        'Место: ${d.location}',
                      if (d.size != null && d.size!.isNotEmpty)
                        'Размер: ${d.size}',
                      if (d.description != null &&
                          d.description!.isNotEmpty)
                        d.description,
                      if (d.assessment != null && d.assessment!.isNotEmpty)
                        'Оценка: ${d.assessment}',
                    ].join(' | '),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon:
                        const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () async {
                      final confirmed = await showConfirmDeleteDialog(
                        context,
                        message: 'Вы уверены? Дефект и все его данные будут удалены.',
                      );
                      if (confirmed) {
                        checklist.visualDefects.removeAt(idx);
                        onStateChanged();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: () => _addVisualDefectDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Добавить дефект'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kInspectionAccentBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addVisualDefectDialog(BuildContext context) async {
    String? defectType;
    String? location;
    String? size;
    String? description;
    String? photoPath;
    String zone = 'external';
    String assessment = 'Годен';
    final locationController = TextEditingController();

    final defectTypes = [
      'Коррозия',
      'Вмятина',
      'Трещина',
      'Разрыв',
      'Скол',
      'Потеря металла',
      'Другое',
    ];

    // Часто встречающиеся объекты контроля ВИК — для быстрого выбора,
    // чтобы техник мог добавлять произвольные объекты, а не только
    // 2 предустановленные в отчёте категории («фундаменты», «сварные соединения»).
    const commonObjects = [
      'фундаментов',
      'сварных соединений',
      'опор сосуда',
      'запорной арматуры',
      'трубопроводов обвязки',
      'штуцеров',
      'предохранительных клапанов',
      'КИП',
    ];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Объект контроля / дефект ВИК'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: zone,
                  decoration: const InputDecoration(labelText: 'Зона осмотра'),
                  items: const [
                    DropdownMenuItem(value: 'external', child: Text('Наружный осмотр')),
                    DropdownMenuItem(value: 'internal', child: Text('Внутренний осмотр')),
                  ],
                  onChanged: (v) => setLocalState(() => zone = v ?? 'external'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: -8,
                  children: commonObjects
                      .map((o) => ActionChip(
                            label: Text(o, style: const TextStyle(fontSize: 12)),
                            onPressed: () {
                              locationController.text = o;
                              setLocalState(() => location = o);
                            },
                          ))
                      .toList(),
                ),
                TextFormField(
                  controller: locationController,
                  decoration: const InputDecoration(
                      labelText: 'Объект контроля / место'),
                  onChanged: (v) => location = v,
                ),
                DropdownButtonFormField<String>(
                  value: defectType,
                  decoration:
                      const InputDecoration(labelText: 'Тип дефекта (если есть)'),
                  items: defectTypes
                      .map(
                          (t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setLocalState(() => defectType = v),
                ),
                TextFormField(
                  decoration:
                      const InputDecoration(labelText: 'Размер (мм)'),
                  onChanged: (v) => size = v,
                ),
                TextFormField(
                  decoration: const InputDecoration(
                      labelText: 'Описание дефектов (пусто — «Дефектов не обнаружено»)'),
                  onChanged: (v) => description = v,
                ),
                DropdownButtonFormField<String>(
                  value: assessment,
                  decoration: const InputDecoration(labelText: 'Оценка качества'),
                  items: const [
                    DropdownMenuItem(value: 'Годен', child: Text('Годен')),
                    DropdownMenuItem(value: 'Не годен', child: Text('Не годен')),
                  ],
                  onChanged: (v) => setLocalState(() => assessment = v ?? 'Годен'),
                ),
                const SizedBox(height: 8),
                if (photoPath != null)
                  Text(
                    'Фото: ${Path.basename(photoPath!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final p =
                            await _pickDefectPhoto(ImageSource.camera);
                        if (p != null) {
                          setLocalState(() => photoPath = p);
                        }
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Камера'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final p =
                            await _pickDefectPhoto(ImageSource.gallery);
                        if (p != null) {
                          setLocalState(() => photoPath = p);
                        }
                      },
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Галерея'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                final d = VisualDefect();
                d.defectType = defectType;
                d.location = location;
                d.size = size;
                d.description = description;
                d.zone = zone;
                d.assessment = assessment;
                d.scope = '100%';
                if (photoPath != null) {
                  d.photos = [photoPath!];
                }
                checklist.visualDefects.add(d);
                onStateChanged();
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickDefectPhoto(ImageSource source) async {
    try {
      final picked =
          await imagePicker.pickImage(source: source, imageQuality: 80);
      if (picked == null) return null;
      final withMeta =
          await maybeAddDateTimeGpsToPhoto(picked.path, force: true);
      final persistedPath = await _persistPickedFile(
        sourcePath: withMeta,
        fileName: Path.basename(withMeta),
        documentNumber: 'vik_defect',
      );
      return persistedPath;
    } catch (_) {
      return null;
    }
  }

  Future<String> _persistPickedFile({
    required String sourcePath,
    required String fileName,
    required String documentNumber,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final storageDir = Directory(Path.join(dir.path, 'offline_documents'));
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = Path.extension(fileName).toLowerCase();
    final isImage = ext == '.jpg' || ext == '.jpeg' || ext == '.png';
    final outFileName = isImage
        ? '${documentNumber}_${ts}_${Path.basenameWithoutExtension(fileName)}.jpg'
        : '${documentNumber}_${ts}_$fileName';
    final targetPath = Path.join(storageDir.path, outFileName);
    final pathToWrite = isImage
        ? await ImageResizeService.resizeIfNeeded(sourcePath)
        : sourcePath;
    await File(pathToWrite).copy(targetPath);
    return targetPath;
  }
}
