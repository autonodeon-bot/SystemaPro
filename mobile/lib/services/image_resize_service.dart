import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

/// Сжатие фото для отчётов: ограничение размера и объёма файла.
class ImageResizeService {
  /// Максимальная длина длинной стороны в пикселях (для отчётов).
  static const int maxLongSide = 1920;

  /// Целевой максимальный размер файла в байтах (примерно 500 КБ).
  static const int maxFileSizeBytes = 512 * 1024;

  /// Качество JPEG при сохранении (0–100).
  static const int jpegQuality = 85;

  /// Если файл — изображение и превышает лимиты, сжимает и возвращает путь к новому файлу.
  /// Иначе возвращает исходный путь.
  static Future<String> resizeIfNeeded(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return filePath;

    final ext = path.extension(filePath).toLowerCase();
    if (ext != '.jpg' && ext != '.jpeg' && ext != '.png') return filePath;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return filePath;

    img.Image? image;
    try {
      if (ext == '.png') {
        image = img.decodePng(bytes);
      } else {
        image = img.decodeImage(bytes);
      }
    } catch (_) {
      return filePath;
    }
    if (image == null) return filePath;

    int w = image.width;
    int h = image.height;
    if (w <= 0 || h <= 0) return filePath;

    final int longSide = w > h ? w : h;
    if (longSide <= maxLongSide && bytes.length <= maxFileSizeBytes) {
      return filePath;
    }

    // Уменьшаем по длинной стороне
    if (longSide > maxLongSide) {
      final scale = maxLongSide / longSide;
      image = img.copyResize(image, width: (w * scale).round(), height: (h * scale).round());
      w = image.width;
      h = image.height;
    }

    // Сохраняем в JPEG для экономии места (PNG тоже конвертируем)
    List<int> outBytes = img.encodeJpg(image, quality: jpegQuality);
    int quality = jpegQuality;
    while (outBytes.length > maxFileSizeBytes && quality > 20) {
      quality -= 10;
      outBytes = img.encodeJpg(image, quality: quality);
    }

    final dir = await getTemporaryDirectory();
    final outPath = path.join(dir.path, 'resized_${path.basenameWithoutExtension(filePath)}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    final outFile = File(outPath);
    await outFile.writeAsBytes(outBytes, flush: true);
    return outPath;
  }

  /// Создаёт сжатую копию файла в указанной директории с заданным именем.
  /// Для изображений применяет resizeIfNeeded; для остальных — просто копирует.
  static Future<String> copyResizedIfImage(String sourcePath, String targetDir, String targetFileName) async {
    final ext = path.extension(sourcePath).toLowerCase();
    final isImage = ext == '.jpg' || ext == '.jpeg' || ext == '.png';
    final resizedPath = isImage ? await resizeIfNeeded(sourcePath) : sourcePath;
    final dir = Directory(targetDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final targetPath = path.join(targetDir, targetFileName);
    await File(resizedPath).copy(targetPath);
    return targetPath;
  }
}
