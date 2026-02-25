import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Сервис для работы с аннотациями на фотографиях
class PhotoAnnotationService {
  /// Добавить дату и GPS-координаты на фото (оверлей внизу)
  Future<String?> annotatePhotoWithDateTimeAndGps({
    required String imagePath,
    required String dateTimeText,
    String? gpsText,
  }) async {
    try {
      final File imageFile = File(imagePath);
      if (!await imageFile.exists()) return null;

      final Uint8List imageBytes = await imageFile.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(imageBytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image image = frameInfo.image;

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

      canvas.drawImage(image, Offset.zero, Paint());

      // Требование UX: размер текста должен быть пропорционален фото (~1/15).
      final double minSide = imageSize.width < imageSize.height ? imageSize.width : imageSize.height;
      final double initialFontSize = (minSide / 15).clamp(16.0, 120.0);
      final double outerPadding = (minSide / 90).clamp(8.0, 24.0);
      final double innerPadding = (initialFontSize * 0.2).clamp(4.0, 14.0);
      final double lineGap = (initialFontSize * 0.22).clamp(4.0, 24.0);
      final double maxTextWidth = (imageSize.width - (outerPadding * 2) - (innerPadding * 2)).clamp(40.0, imageSize.width);

      TextPainter buildPainter(String text, double fontSize) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
                Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 1)),
              ],
            ),
          ),
          maxLines: 1,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(minWidth: 0, maxWidth: maxTextWidth);
        return textPainter;
      }

      final String dateLine = 'Дата: $dateTimeText';
      final String? gpsLine = (gpsText != null && gpsText.trim().isNotEmpty) ? 'GPS: ${gpsText.trim()}' : null;

      double fittedFontSize = initialFontSize;
      TextPainter datePainter = buildPainter(dateLine, fittedFontSize);
      TextPainter? gpsPainter = gpsLine != null ? buildPainter(gpsLine, fittedFontSize) : null;

      // Доп. защита: если строка не помещается по ширине, уменьшаем шрифт, сохраняя пропорции.
      while (fittedFontSize > 12 &&
          ((datePainter.width > maxTextWidth) || (gpsPainter != null && gpsPainter.width > maxTextWidth))) {
        fittedFontSize = (fittedFontSize * 0.92).clamp(12.0, initialFontSize);
        datePainter = buildPainter(dateLine, fittedFontSize);
        gpsPainter = gpsLine != null ? buildPainter(gpsLine, fittedFontSize) : null;
      }

      final double dateBlockHeight = datePainter.height + innerPadding * 2;
      final double gpsBlockHeight = gpsPainter != null ? (gpsPainter.height + innerPadding * 2) : 0;
      final double totalBlocksHeight = dateBlockHeight + (gpsPainter != null ? lineGap + gpsBlockHeight : 0);
      final double startY = imageSize.height - outerPadding - totalBlocksHeight;

      double currentY = startY;
      final Paint blockPaint = Paint()..color = Colors.black.withValues(alpha: 0.62);

      // Блок даты/времени.
      final Rect dateRect = Rect.fromLTWH(
        outerPadding,
        currentY,
        datePainter.width + innerPadding * 2,
        dateBlockHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(dateRect, Radius.circular((fittedFontSize * 0.22).clamp(4.0, 20.0))),
        blockPaint,
      );
      datePainter.paint(canvas, Offset(dateRect.left + innerPadding, dateRect.top + innerPadding));

      // Отдельный блок GPS, чтобы дата и координаты никогда не накладывались.
      if (gpsPainter != null) {
        currentY += dateBlockHeight + lineGap;
        final Rect gpsRect = Rect.fromLTWH(
          outerPadding,
          currentY,
          gpsPainter.width + innerPadding * 2,
          gpsBlockHeight,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(gpsRect, Radius.circular((fittedFontSize * 0.22).clamp(4.0, 20.0))),
          blockPaint,
        );
        gpsPainter.paint(canvas, Offset(gpsRect.left + innerPadding, gpsRect.top + innerPadding));
      }

      final ui.Picture picture = recorder.endRecording();
      final ui.Image annotatedImage = await picture.toImage(image.width, image.height);
      final ByteData? byteData = await annotatedImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final Directory appDir = await getApplicationDocumentsDirectory();
      final String fileName = 'with_meta_${path.basename(imagePath)}';
      final String newPath = path.join(appDir.path, fileName);
      await File(newPath).writeAsBytes(byteData.buffer.asUint8List());
      return newPath;
    } catch (e) {
      print('Ошибка наложения даты/GPS на фото: $e');
      return null;
    }
  }
  /// Добавить аннотацию (текст, стрелки) на фото
  Future<String?> annotatePhoto({
    required String imagePath,
    String? annotationText,
    List<Map<String, dynamic>>? arrows, // [{x: double, y: double, direction: String}]
    List<Map<String, dynamic>>? shapes, // [{type: 'circle'|'rectangle', x, y, width, height}]
  }) async {
    try {
      final File imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        return null;
      }

      final Uint8List imageBytes = await imageFile.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(imageBytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image image = frameInfo.image;

      // Создаем canvas для рисования
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

      // Рисуем оригинальное изображение
      canvas.drawImage(image, Offset.zero, Paint());

      // Рисуем стрелки
      if (arrows != null) {
        for (var arrow in arrows) {
          final x = arrow['x'] as double;
          final y = arrow['y'] as double;
          final direction = arrow['direction'] as String? ?? 'right';

          _drawArrow(canvas, Offset(x, y), direction, imageSize);
        }
      }

      // Рисуем фигуры
      if (shapes != null) {
        for (var shape in shapes) {
          final type = shape['type'] as String;
          final x = shape['x'] as double;
          final y = shape['y'] as double;
          final width = shape['width'] as double;
          final height = shape['height'] as double;

          if (type == 'circle') {
            canvas.drawCircle(
              Offset(x, y),
              width / 2,
              Paint()
                ..color = Colors.red
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3,
            );
          } else if (type == 'rectangle') {
            canvas.drawRect(
              Rect.fromLTWH(x, y, width, height),
              Paint()
                ..color = Colors.red
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3,
            );
          }
        }
      }

      // Добавляем текст
      if (annotationText != null && annotationText.isNotEmpty) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: annotationText,
            style: const TextStyle(
              color: Colors.red,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(20, imageSize.height - textPainter.height - 20),
        );
      }

      // Конвертируем в изображение
      final ui.Picture picture = recorder.endRecording();
      final ui.Image annotatedImage = await picture.toImage(
        image.width,
        image.height,
      );

      // Сохраняем аннотированное изображение
      final ByteData? byteData = await annotatedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return null;

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String fileName = 'annotated_${path.basename(imagePath)}';
      final String newPath = path.join(appDir.path, fileName);
      final File newFile = File(newPath);
      await newFile.writeAsBytes(pngBytes);

      return newPath;
    } catch (e) {
      print('Ошибка аннотации фото: $e');
      return null;
    }
  }

  void _drawArrow(Canvas canvas, Offset position, String direction, Size imageSize) {
    final Paint paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    double dx = 0;
    double dy = 0;
    switch (direction) {
      case 'up':
        dy = -30;
        break;
      case 'down':
        dy = 30;
        break;
      case 'left':
        dx = -30;
        break;
      case 'right':
      default:
        dx = 30;
        break;
    }

    // Рисуем линию
    canvas.drawLine(position, position + Offset(dx, dy), paint);

    // Рисуем наконечник стрелки
    final Path arrowPath = Path();
    if (direction == 'right') {
      arrowPath.moveTo(position.dx + dx, position.dy);
      arrowPath.lineTo(position.dx + dx - 10, position.dy - 5);
      arrowPath.lineTo(position.dx + dx - 10, position.dy + 5);
    } else if (direction == 'left') {
      arrowPath.moveTo(position.dx + dx, position.dy);
      arrowPath.lineTo(position.dx + dx + 10, position.dy - 5);
      arrowPath.lineTo(position.dx + dx + 10, position.dy + 5);
    } else if (direction == 'up') {
      arrowPath.moveTo(position.dx, position.dy + dy);
      arrowPath.lineTo(position.dx - 5, position.dy + dy + 10);
      arrowPath.lineTo(position.dx + 5, position.dy + dy + 10);
    } else if (direction == 'down') {
      arrowPath.moveTo(position.dx, position.dy + dy);
      arrowPath.lineTo(position.dx - 5, position.dy + dy - 10);
      arrowPath.lineTo(position.dx + 5, position.dy + dy - 10);
    }
    arrowPath.close();
    canvas.drawPath(arrowPath, paint..style = PaintingStyle.fill);
  }
}
