import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'image_resize_service.dart';

/// Формат архива обследования для отправки на сервер.
/// В архиве: manifest.json, checklist.json, photos/*.jpg
class InspectionArchiveService {
  static const String manifestName = 'manifest.json';
  static const String checklistName = 'checklist.json';
  static const String photosDir = 'photos';

  /// Собирает один ZIP-архив по данным обследования (сжатые фото + JSON).
  /// Возвращает путь к созданному файлу.
  static Future<String> buildArchive({
    required Map<String, dynamic> inspectionData,
  }) async {
    final archive = Archive();
    final data = inspectionData['data'] as Map<String, dynamic>? ?? {};
    final documentFiles = inspectionData['document_files'] as Map<String, dynamic>? ?? {};

    // Собираем путь -> имя в архиве
    final pathToArcName = <String, String>{};
    void addPath(String? filePath, String archiveName) {
      if (filePath == null || filePath.trim().isEmpty) return;
      final f = File(filePath);
      if (!f.existsSync()) return;
      pathToArcName[filePath] = archiveName;
    }

    addPath(data['factory_plate_photo'] as String?, 'factory_plate.jpg');
    addPath(data['control_scheme_image'] as String?, 'control_scheme.jpg');
    for (var i = 1; i <= 17; i++) {
      final v = documentFiles[i.toString()];
      String? fp;
      if (v is Map) fp = v['file_path'] as String?;
      if (v is String) fp = v;
      addPath(fp, 'doc_$i.jpg');
    }
    final vd = data['visual_defects'];
    if (vd is List) {
      for (var i = 0; i < vd.length; i++) {
        final d = vd[i];
        if (d is Map && d['photos'] is List) {
          for (var j = 0; j < (d['photos'] as List).length; j++) {
            addPath((d['photos'] as List)[j]?.toString(), 'vd_${i}_$j.jpg');
          }
        }
      }
    }
    // Фото замеров УЗТ (точки замера толщины)
    for (final entry in documentFiles.entries) {
      final key = entry.key.toString();
      if (key.startsWith('uzt_point_')) {
        final v = entry.value;
        String? fp;
        if (v is Map) fp = v['file_path'] as String?;
        if (v is String) fp = v;
        addPath(fp, '$key.jpg');
      }
    }

    // Добавляем фото в архив (сжатые)
    for (final entry in pathToArcName.entries) {
      final resized = await ImageResizeService.resizeIfNeeded(entry.key);
      final bytes = await File(resized).readAsBytes();
      archive.addFile(ArchiveFile('$photosDir/${entry.value}', bytes.length, bytes));
    }

    // Копия data с путями, заменёнными на имена в архиве (photos/xxx)
    final dataCopy = Map<String, dynamic>.from(data);
    void replacePath(String key, String? pathVal) {
      if (pathVal == null || pathVal.isEmpty) return;
      final name = pathToArcName[pathVal];
      if (name != null) dataCopy[key] = '$photosDir/$name';
    }
    replacePath('factory_plate_photo', data['factory_plate_photo'] as String?);
    replacePath('control_scheme_image', data['control_scheme_image'] as String?);
    if (dataCopy['visual_defects'] is List) {
      final vdList = List<Map<String, dynamic>>.from((dataCopy['visual_defects'] as List).map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}));
      for (var i = 0; i < vdList.length; i++) {
        final photos = vdList[i]['photos'] as List? ?? [];
        final newPhotos = <String>[];
        for (var j = 0; j < photos.length; j++) {
          final p = photos[j]?.toString();
          final name = p != null ? pathToArcName[p] : null;
          newPhotos.add(name != null ? '$photosDir/$name' : (p ?? ''));
        }
        vdList[i]['photos'] = newPhotos;
      }
      dataCopy['visual_defects'] = vdList;
    }
    // Заменяем пути фото в thickness_measurements на имена в архиве
    final tm = dataCopy['thickness_measurements'] ?? dataCopy['thicknessMeasurements'];
    if (tm is List) {
      final tmList = List<Map<String, dynamic>>.from(tm.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}));
      for (var i = 0; i < tmList.length; i++) {
        final photos = tmList[i]['photos'] as List? ?? [];
        final newPhotos = <String>[];
        for (var j = 0; j < photos.length; j++) {
          final p = photos[j]?.toString();
          final name = p != null ? pathToArcName[p] : null;
          newPhotos.add(name != null ? '$photosDir/$name' : (p ?? ''));
        }
        tmList[i]['photos'] = newPhotos;
      }
      dataCopy['thickness_measurements'] = tmList;
    }

    // 1) Manifest
    final manifest = {
      'equipment_id': inspectionData['equipment_id'],
      'assignment_id': inspectionData['assignment_id'],
      'status': inspectionData['status'] ?? 'DRAFT',
      'date_performed': inspectionData['date_performed'],
      'conclusion': inspectionData['conclusion'],
      'verification_equipment_ids': inspectionData['verification_equipment_ids'] ?? [],
    };
    final manifestBytes = utf8.encode(json.encode(manifest));
    archive.addFile(ArchiveFile(manifestName, manifestBytes.length, manifestBytes));

    // 2) Checklist
    final checklistPayload = {
      'data': dataCopy,
      'equipment_id': inspectionData['equipment_id'],
      'conclusion': inspectionData['conclusion'],
      'status': inspectionData['status'],
      'date_performed': inspectionData['date_performed'],
      'assignment_id': inspectionData['assignment_id'],
      'verification_equipment_ids': inspectionData['verification_equipment_ids'] ?? [],
    };
    final checklistBytes = utf8.encode(json.encode(checklistPayload));
    archive.addFile(ArchiveFile(checklistName, checklistBytes.length, checklistBytes));

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) throw Exception('Не удалось создать архив');

    final dir = await getTemporaryDirectory();
    final zipPath = path.join(dir.path, 'inspection_${DateTime.now().millisecondsSinceEpoch}.zip');
    await File(zipPath).writeAsBytes(zipBytes, flush: true);
    return zipPath;
  }
}
