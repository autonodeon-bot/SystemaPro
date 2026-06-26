import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as Path;
import 'package:path_provider/path_provider.dart';
import '../../data/technical_report_form_registry.dart';
import '../../models/vessel_checklist.dart';
import '../../services/api_service.dart';
import '../../services/image_resize_service.dart';
import '../../data/checklist_constants.dart';
import 'inspection_form_fields.dart';

class InspectionDocumentsSection extends StatelessWidget {
  final VesselChecklist checklist;
  final Map<String, String> documentFiles;
  final String? questionnaireId;
  final ApiService apiService;
  final ImagePicker imagePicker;
  final VoidCallback onStateChanged;

  const InspectionDocumentsSection({
    super.key,
    required this.checklist,
    required this.documentFiles,
    required this.questionnaireId,
    required this.apiService,
    required this.imagePicker,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final form = TechnicalReportFormRegistry.formForChecklist(checklist.reportFormId);
    final docs = form.documents.isNotEmpty
        ? form.documents
        : ChecklistConstants.documents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionHeader(
          form.sectionHeader('documents', fallback: '2. Перечень рассмотренных документов'),
        ),
        _buildOpoDataSwitch(),
        ...docs.where((doc) {
          final n = int.tryParse(doc['number'] ?? '0') ?? 0;
          if (checklist.includeOpoData) return true;
          return n >= 10;
        }).map((doc) {
          final num = doc['number'] ?? '';
          if (VesselChecklist.multiDocumentNumbers.contains(num)) {
            return _buildMultiDocumentSets(context, doc);
          }
          return _buildDocumentCheckbox(context, doc);
        }),
      ],
    );
  }

  Widget _buildOpoDataSwitch() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.25)),
      ),
      child: SwitchListTile.adaptive(
        value: checklist.includeOpoData,
        onChanged: (v) {
          checklist.includeOpoData = v;
          onStateChanged();
        },
        title: const Text(
          'Данные по ОПО (пункты 1–9)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          checklist.includeOpoData
              ? 'Включено: заполните весь опросный лист'
              : 'Выключено: чек-лист только по оборудованию (начиная с пункта 10)',
          style: const TextStyle(color: Colors.white70),
        ),
        activeColor: Colors.green,
      ),
    );
  }

  Widget _buildMultiDocumentSets(
      BuildContext context, Map<String, String> doc) {
    final documentNumber = doc['number']!;
    checklist.ensureAtLeastOneDocumentSet(documentNumber);
    final sets = checklist.getDocumentSets(documentNumber);
    final isChecked = checklist.documents[documentNumber] ?? false;
    final hasAnyFile = sets.asMap().entries.any((e) =>
        documentFiles.containsKey(
            VesselChecklist.documentFileKey(documentNumber, e.key)) ||
        (e.key == 0 && documentFiles.containsKey(documentNumber)));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: kInspectionDarkBg,
        child: Column(
          children: [
            CheckboxListTile(
              title: Text(
                '${doc['number']}. ${doc['name']}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle: const Text(
                'Можно добавить несколько комплектов (номер, дата, файл)',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: isChecked,
              onChanged: (value) {
                checklist.documents[documentNumber] = value ?? false;
                if (value == true) {
                  checklist.ensureAtLeastOneDocumentSet(documentNumber);
                }
                onStateChanged();
              },
              activeColor: kInspectionAccentBlue,
              secondary: hasAnyFile
                  ? const Icon(Icons.attach_file, color: Colors.green, size: 20)
                  : null,
            ),
            if (isChecked)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    ...sets.asMap().entries.map((entry) {
                      final setIndex = entry.key;
                      final info = entry.value;
                      final fileKey =
                          VesselChecklist.documentFileKey(documentNumber, setIndex);
                      final hasFile = documentFiles.containsKey(fileKey) ||
                          (setIndex == 0 &&
                              documentFiles.containsKey(documentNumber));
                      DateTime? infoDate;
                      if ((info['date'] ?? '').isNotEmpty) {
                        try {
                          infoDate = DateTime.parse(info['date']!);
                        } catch (_) {}
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Комплект ${setIndex + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                if (sets.length > 1)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red, size: 20),
                                    onPressed: () {
                                      final updated =
                                          List<Map<String, String>>.from(sets);
                                      updated.removeAt(setIndex);
                                      checklist.setDocumentSets(
                                          documentNumber, updated);
                                      documentFiles.remove(fileKey);
                                      if (setIndex == 0) {
                                        documentFiles.remove(documentNumber);
                                      }
                                      onStateChanged();
                                    },
                                    tooltip: 'Удалить комплект',
                                  ),
                              ],
                            ),
                            FormBuilderTextField(
                              name: 'doc_number_${documentNumber}_$setIndex',
                              initialValue: info['number'],
                              decoration: const InputDecoration(
                                labelText: 'Номер документа',
                                labelStyle: TextStyle(color: Colors.white70),
                              ),
                              style: const TextStyle(color: Colors.white),
                              onChanged: (value) {
                                final updated =
                                    List<Map<String, String>>.from(sets);
                                updated[setIndex] = {
                                  'number': value ?? '',
                                  'date': updated[setIndex]['date'] ?? '',
                                };
                                checklist.setDocumentSets(
                                    documentNumber, updated);
                                onStateChanged();
                              },
                            ),
                            const SizedBox(height: 8),
                            FormBuilderDateTimePicker(
                              name: 'doc_date_${documentNumber}_$setIndex',
                              inputType: InputType.date,
                              initialValue: infoDate,
                              decoration: const InputDecoration(
                                labelText: 'Дата документа',
                                labelStyle: TextStyle(color: Colors.white70),
                              ),
                              style: const TextStyle(color: Colors.white),
                              onChanged: (value) {
                                final updated =
                                    List<Map<String, String>>.from(sets);
                                updated[setIndex] = {
                                  'number': updated[setIndex]['number'] ?? '',
                                  'date': value != null
                                      ? value.toIso8601String().split('T')[0]
                                      : '',
                                };
                                checklist.setDocumentSets(
                                    documentNumber, updated);
                                onStateChanged();
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _pickDocumentFile(
                                      context,
                                      documentNumber,
                                      fileStorageKey: fileKey,
                                    ),
                                    icon: Icon(hasFile
                                        ? Icons.edit
                                        : Icons.attach_file),
                                    label: Text(hasFile
                                        ? 'Изменить файл'
                                        : 'Прикрепить файл'),
                                  ),
                                ),
                                if (hasFile)
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () {
                                      documentFiles.remove(fileKey);
                                      documentFiles.remove(documentNumber);
                                      onStateChanged();
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          final updated =
                              List<Map<String, String>>.from(sets);
                          updated.add({'number': '', 'date': ''});
                          checklist.setDocumentSets(documentNumber, updated);
                          onStateChanged();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Добавить комплект документов'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentCheckbox(
      BuildContext context, Map<String, String> doc) {
    final documentNumber = doc['number']!;
    final hasFile = documentFiles.containsKey(documentNumber);
    final isChecked = checklist.documents[documentNumber] ?? false;
    final info =
        checklist.documentsInfo[documentNumber] ?? {'number': '', 'date': '', 'pages': ''};
    DateTime? infoDate;
    if ((info['date'] ?? '').isNotEmpty) {
      try {
        infoDate = DateTime.parse(info['date']!);
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: kInspectionDarkBg,
        child: Column(
          children: [
            CheckboxListTile(
              title: Text(
                '${doc['number']}. ${doc['name']}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              value: isChecked,
              onChanged: (value) {
                checklist.documents[documentNumber] = value ?? false;
                if ((value ?? false) &&
                    !checklist.documentsInfo.containsKey(documentNumber)) {
                  checklist.documentsInfo[documentNumber] = {
                    'number': '',
                    'date': '',
                    'pages': '',
                  };
                }
                if (value == false && hasFile) {
                  documentFiles.remove(documentNumber);
                  if (questionnaireId != null) {
                    apiService
                        .deleteDocumentFile(
                      questionnaireId: questionnaireId!,
                      documentNumber: documentNumber,
                    )
                        .catchError((e) {});
                  }
                }
                onStateChanged();
              },
              activeColor: kInspectionAccentBlue,
              secondary: hasFile
                  ? const Icon(Icons.attach_file,
                      color: Colors.green, size: 20)
                  : null,
            ),
            if (isChecked)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    FormBuilderTextField(
                      name: 'doc_number_$documentNumber',
                      initialValue: info['number'],
                      decoration: const InputDecoration(
                        labelText: 'Номер документа',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: kInspectionAccentBlue),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onChanged: (value) {
                        final current =
                            checklist.documentsInfo[documentNumber] ?? {};
                        checklist.documentsInfo[documentNumber] = {
                          'number': value ?? '',
                          'date': current['date'] ?? '',
                          'pages': current['pages'] ?? '',
                        };
                        onStateChanged();
                      },
                    ),
                    const SizedBox(height: 8),
                    FormBuilderTextField(
                      name: 'doc_pages_$documentNumber',
                      initialValue: info['pages'],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Количество страниц',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: kInspectionAccentBlue),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onChanged: (value) {
                        final current =
                            checklist.documentsInfo[documentNumber] ?? {};
                        checklist.documentsInfo[documentNumber] = {
                          'number': current['number'] ?? '',
                          'date': current['date'] ?? '',
                          'pages': value ?? '',
                        };
                        onStateChanged();
                      },
                    ),
                    const SizedBox(height: 8),
                    FormBuilderDateTimePicker(
                      name: 'doc_date_$documentNumber',
                      inputType: InputType.date,
                      initialValue: infoDate,
                      decoration: const InputDecoration(
                        labelText: 'Дата документа',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: kInspectionAccentBlue),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onChanged: (value) {
                        final current =
                            checklist.documentsInfo[documentNumber] ?? {};
                        checklist.documentsInfo[documentNumber] = {
                          'number': current['number'] ?? '',
                          'date': value != null
                              ? value.toIso8601String().split('T')[0]
                              : '',
                          'pages': current['pages'] ?? '',
                        };
                        onStateChanged();
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _pickDocumentFile(context, documentNumber),
                            icon: Icon(
                                hasFile ? Icons.edit : Icons.attach_file),
                            label: Text(hasFile
                                ? 'Изменить файл'
                                : 'Прикрепить файл'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              side: const BorderSide(color: Colors.blue),
                            ),
                          ),
                        ),
                        if (hasFile) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon:
                                const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              documentFiles.remove(documentNumber);
                              if (questionnaireId != null) {
                                apiService
                                    .deleteDocumentFile(
                                  questionnaireId: questionnaireId!,
                                  documentNumber: documentNumber,
                                )
                                    .catchError((e) {});
                              }
                              onStateChanged();
                            },
                            tooltip: 'Удалить файл',
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDocumentFile(
    BuildContext context,
    String documentNumber, {
    String? fileStorageKey,
  }) async {
    final storageKey = fileStorageKey ?? documentNumber;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: kInspectionDarkBg,
          title: const Text('Выберите файл',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt,
                    color: Colors.blue, size: 28),
                title: const Text('Камера',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(context);
                  final image = await imagePicker.pickImage(
                      source: ImageSource.camera);
                  if (image != null) {
                    _handleDocumentFile(
                        context, storageKey, image.path, image.name);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library,
                    color: Colors.green, size: 28),
                title: const Text('Галерея',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(context);
                  final image = await imagePicker.pickImage(
                      source: ImageSource.gallery);
                  if (image != null) {
                    _handleDocumentFile(
                        context, storageKey, image.path, image.name);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf,
                    color: Colors.red),
                title: const Text('PDF файл',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf'],
                    withData: true,
                  );
                  if (result != null) {
                    final picked = result.files.single;
                    String? pickedPath = picked.path;
                    if (pickedPath == null && picked.bytes != null) {
                      pickedPath = await _persistPickedBytes(
                        fileName: picked.name,
                        bytes: picked.bytes!,
                        documentNumber: documentNumber,
                      );
                    }
                    if (pickedPath != null && context.mounted) {
                      _handleDocumentFile(
                          context, storageKey, pickedPath, picked.name);
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Не удалось получить путь к файлу PDF'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора файла: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String> _persistPickedBytes({
    required String fileName,
    required Uint8List bytes,
    required String documentNumber,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final storageDir = Directory(Path.join(dir.path, 'offline_documents'));
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    final safeName =
        fileName.isNotEmpty ? fileName : 'document_$documentNumber.pdf';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final targetPath =
        Path.join(storageDir.path, '${documentNumber}_${ts}_$safeName');
    final f = File(targetPath);
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
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

  Future<void> _handleDocumentFile(BuildContext context, String fileStorageKey,
      String filePath, String fileName) async {
    String persistedPath = filePath;
    try {
      if (await File(filePath).exists()) {
        persistedPath = await _persistPickedFile(
          sourcePath: filePath,
          fileName: fileName,
          documentNumber: fileStorageKey,
        );
      }
    } catch (_) {}

    documentFiles[fileStorageKey] = persistedPath;
    onStateChanged();

    if (questionnaireId != null) {
      try {
        await apiService.uploadDocumentFile(
          questionnaireId: questionnaireId!,
          documentNumber: fileStorageKey.split('_').first,
          filePath: persistedPath,
          fileName: fileName,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Файл успешно загружен'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки файла: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
