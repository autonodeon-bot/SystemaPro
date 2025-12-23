import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'dart:async';

class AnnotationPoint {
  Offset position;
  String? text;
  Color color;
  double strokeWidth;
  AnnotationType type;

  AnnotationPoint({
    required this.position,
    this.text,
    this.color = Colors.red,
    this.strokeWidth = 3.0,
    this.type = AnnotationType.point,
  });
}

enum AnnotationType {
  point,
  circle,
  arrow,
  text,
}

class ImageAnnotationScreen extends StatefulWidget {
  final File? initialImage;
  final String? title;
  final Function(File annotatedImage, List<AnnotationPoint> annotations)? onSave;

  const ImageAnnotationScreen({
    super.key,
    this.initialImage,
    this.title,
    this.onSave,
  });

  @override
  State<ImageAnnotationScreen> createState() => _ImageAnnotationScreenState();
}

class _ImageAnnotationScreenState extends State<ImageAnnotationScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  File? _imageFile;
  List<AnnotationPoint> _annotations = [];
  AnnotationType _currentType = AnnotationType.point;
  Color _currentColor = Colors.red;
  double _currentStrokeWidth = 3.0;
  final GlobalKey _repaintBoundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _imageFile = widget.initialImage;
  }

  Future<void> _pickImage() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
        _annotations.clear();
      });
    }
  }

  Future<void> _pickImageFromGallery() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
        _annotations.clear();
      });
    }
  }

  void _handleTapDown(TapDownDetails details, Size imageSize) {
    if (_imageFile == null) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset localPosition = renderBox.globalToLocal(details.globalPosition);

    // Находим контейнер изображения
    final imageContainer = _getImageContainerBounds();
    if (imageContainer == null) return;

    final double x = localPosition.dx - imageContainer.left;
    final double y = localPosition.dy - imageContainer.top;

    if (x < 0 || x > imageContainer.width || y < 0 || y > imageContainer.height) {
      return;
    }

    // Проверяем, не нажали ли на существующую аннотацию
    for (var annotation in _annotations) {
      final distance = (Offset(x, y) - annotation.position).distance;
      if (distance < 30) {
        _showAnnotationDialog(annotation);
        return;
      }
    }

    // Создаем новую аннотацию
    final newAnnotation = AnnotationPoint(
      position: Offset(x, y),
      color: _currentColor,
      strokeWidth: _currentStrokeWidth,
      type: _currentType,
    );

    setState(() {
      _annotations.add(newAnnotation);
    });

    _showAnnotationDialog(newAnnotation);
  }

  Rect? _getImageContainerBounds() {
    final size = MediaQuery.of(context).size;
    return Rect.fromLTWH(0, 100, size.width, size.height - 300);
  }

  void _showAnnotationDialog(AnnotationPoint annotation) {
    final textController = TextEditingController(text: annotation.text ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text(
          'Аннотация дефекта',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                decoration: const InputDecoration(
                  labelText: 'Описание дефекта',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3b82f6)),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                onChanged: (value) {
                  annotation.text = value;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AnnotationType>(
                value: annotation.type,
                decoration: const InputDecoration(
                  labelText: 'Тип аннотации',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                dropdownColor: const Color(0xFF1e293b),
                style: const TextStyle(color: Colors.white),
                items: AnnotationType.values.map((type) {
                  String label;
                  switch (type) {
                    case AnnotationType.point:
                      label = 'Точка';
                      break;
                    case AnnotationType.circle:
                      label = 'Круг';
                      break;
                    case AnnotationType.arrow:
                      label = 'Стрелка';
                      break;
                    case AnnotationType.text:
                      label = 'Текст';
                      break;
                  }
                  return DropdownMenuItem(
                    value: type,
                    child: Text(label),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      annotation.type = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Цвет:', style: TextStyle(color: Colors.white70)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Row(
                      children: [
                        _buildColorButton(Colors.red, annotation),
                        _buildColorButton(Colors.blue, annotation),
                        _buildColorButton(Colors.green, annotation),
                        _buildColorButton(Colors.yellow, annotation),
                        _buildColorButton(Colors.orange, annotation),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _annotations.remove(annotation);
              });
              Navigator.pop(context);
            },
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {});
              Navigator.pop(context);
            },
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _buildColorButton(Color color, AnnotationPoint annotation) {
    return GestureDetector(
      onTap: () {
        setState(() {
          annotation.color = color;
          _currentColor = color;
        });
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: annotation.color == color ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }

  Future<File?> _saveAnnotatedImage() async {
    if (_imageFile == null) return null;

    try {
      final RenderRepaintBoundary boundary =
          _repaintBoundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = await Directory.systemTemp.createTemp();
      final file = File('${directory.path}/annotated_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);

      return file;
    } catch (e) {
      print('Error saving annotated image: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Аннотирование изображения'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              if (_imageFile == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Сначала загрузите изображение'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final annotatedFile = await _saveAnnotatedImage();
              if (annotatedFile != null) {
                if (widget.onSave != null) {
                  widget.onSave!(annotatedFile, _annotations);
                }
                Navigator.pop(context, annotatedFile);
              } else {
                // Если не удалось сохранить аннотированное изображение, возвращаем оригинал
                Navigator.pop(context, _imageFile);
              }
            },
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: Column(
        children: [
          // Панель инструментов
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF1e293b),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  onPressed: _pickImage,
                  tooltip: 'Сфотографировать',
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library, color: Colors.white),
                  onPressed: _pickImageFromGallery,
                  tooltip: 'Выбрать из галереи',
                ),
                IconButton(
                  icon: const Icon(Icons.undo, color: Colors.white),
                  onPressed: () {
                    if (_annotations.isNotEmpty) {
                      setState(() {
                        _annotations.removeLast();
                      });
                    }
                  },
                  tooltip: 'Отменить',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _annotations.clear();
                    });
                  },
                  tooltip: 'Очистить все',
                ),
              ],
            ),
          ),
          // Область изображения с аннотациями
          Expanded(
            child: RepaintBoundary(
              key: _repaintBoundaryKey,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1e293b),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: _imageFile == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.image,
                              size: 64,
                              color: Colors.white38,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Загрузите изображение для аннотирования',
                              style: TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Сфотографировать'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3b82f6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _pickImageFromGallery,
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Выбрать из галереи'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3b82f6),
                              ),
                            ),
                          ],
                        ),
                      )
                    : GestureDetector(
                        onTapDown: (details) => _handleTapDown(details, Size.zero),
                        child: Stack(
                          children: [
                            Center(
                              child: Image.file(
                                _imageFile!,
                                fit: BoxFit.contain,
                              ),
                            ),
                            CustomPaint(
                              size: Size.infinite,
                              painter: AnnotationPainter(_annotations),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          // Список аннотаций
          if (_annotations.isNotEmpty)
            Container(
              height: 120,
              color: const Color(0xFF1e293b),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Аннотации',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _annotations.length,
                      itemBuilder: (context, index) {
                        final annotation = _annotations[index];
                        return GestureDetector(
                          onTap: () => _showAnnotationDialog(annotation),
                          child: Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0f172a),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: annotation.color,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: annotation.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  annotation.text ?? 'Дефект ${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class AnnotationPainter extends CustomPainter {
  final List<AnnotationPoint> annotations;

  AnnotationPainter(this.annotations);

  @override
  void paint(Canvas canvas, Size size) {
    for (var annotation in annotations) {
      final paint = Paint()
        ..color = annotation.color
        ..strokeWidth = annotation.strokeWidth
        ..style = PaintingStyle.stroke;

      switch (annotation.type) {
        case AnnotationType.point:
          canvas.drawCircle(annotation.position, 15, paint);
          paint.style = PaintingStyle.fill;
          canvas.drawCircle(annotation.position, 5, paint);
          break;
        case AnnotationType.circle:
          canvas.drawCircle(annotation.position, 30, paint);
          break;
        case AnnotationType.arrow:
          _drawArrow(canvas, annotation.position, paint);
          break;
        case AnnotationType.text:
          canvas.drawCircle(annotation.position, 10, paint);
          break;
      }

      // Рисуем текст, если есть
      if (annotation.text != null && annotation.text!.isNotEmpty) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: annotation.text,
            style: TextStyle(
              color: annotation.color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            annotation.position.dx + 20,
            annotation.position.dy - textPainter.height - 5,
          ),
        );
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset position, Paint paint) {
    final path = Path();
    path.moveTo(position.dx, position.dy - 20);
    path.lineTo(position.dx, position.dy + 20);
    path.moveTo(position.dx, position.dy - 20);
    path.lineTo(position.dx - 10, position.dy - 10);
    path.moveTo(position.dx, position.dy - 20);
    path.lineTo(position.dx + 10, position.dy - 10);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(AnnotationPainter oldDelegate) {
    return oldDelegate.annotations != annotations;
  }
}

