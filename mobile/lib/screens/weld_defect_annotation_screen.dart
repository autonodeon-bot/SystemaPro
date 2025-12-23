import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class WeldDefect {
  Offset position;
  String defectType;
  String? description;
  String? size;
  String? location;
  Color color;

  WeldDefect({
    required this.position,
    required this.defectType,
    this.description,
    this.size,
    this.location,
    this.color = Colors.red,
  });
}

class WeldDefectAnnotationScreen extends StatefulWidget {
  final File? initialImage;
  final Function(File annotatedImage, List<WeldDefect> defects)? onSave;

  const WeldDefectAnnotationScreen({
    super.key,
    this.initialImage,
    this.onSave,
  });

  @override
  State<WeldDefectAnnotationScreen> createState() => _WeldDefectAnnotationScreenState();
}

class _WeldDefectAnnotationScreenState extends State<WeldDefectAnnotationScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  File? _imageFile;
  List<WeldDefect> _defects = [];

  static const List<Map<String, String>> DEFECT_TYPES = [
    {'code': 'POROSITY', 'name': 'Пористость'},
    {'code': 'CRACK', 'name': 'Трещина'},
    {'code': 'INCLUSION', 'name': 'Включение'},
    {'code': 'UNDERCUT', 'name': 'Подрез'},
    {'code': 'LACK_OF_FUSION', 'name': 'Непровар'},
    {'code': 'LACK_OF_PENETRATION', 'name': 'Непроплав'},
    {'code': 'OVERLAP', 'name': 'Наплыв'},
    {'code': 'BURN_THROUGH', 'name': 'Прожог'},
    {'code': 'OTHER', 'name': 'Прочее'},
  ];

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
        _defects.clear();
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
        _defects.clear();
      });
    }
  }

  void _handleImageTap(TapDownDetails details) {
    if (_imageFile == null) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset localPosition = renderBox.globalToLocal(details.globalPosition);

    final imageContainer = _getImageContainerBounds();
    if (imageContainer == null) return;

    final double x = localPosition.dx - imageContainer.left;
    final double y = localPosition.dy - imageContainer.top;

    if (x < 0 || x > imageContainer.width || y < 0 || y > imageContainer.height) {
      return;
    }

    // Проверяем, не нажали ли на существующий дефект
    for (var defect in _defects) {
      final distance = (Offset(x, y) - defect.position).distance;
      if (distance < 30) {
        _showDefectDialog(defect);
        return;
      }
    }

    // Создаем новый дефект
    final newDefect = WeldDefect(
      position: Offset(x, y),
      defectType: DEFECT_TYPES[0]['code']!,
      color: Colors.red,
    );

    setState(() {
      _defects.add(newDefect);
    });

    _showDefectDialog(newDefect);
  }

  Rect? _getImageContainerBounds() {
    final size = MediaQuery.of(context).size;
    return Rect.fromLTWH(0, 100, size.width, size.height - 300);
  }

  void _showDefectDialog(WeldDefect defect) {
    String? selectedType = defect.defectType;
    final descriptionController = TextEditingController(text: defect.description ?? '');
    final sizeController = TextEditingController(text: defect.size ?? '');
    final locationController = TextEditingController(text: defect.location ?? '');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1e293b),
          title: const Text(
            'Характеристики дефекта сварного шва',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Тип дефекта *',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                  dropdownColor: const Color(0xFF1e293b),
                  style: const TextStyle(color: Colors.white),
                  items: DEFECT_TYPES.map((type) {
                    return DropdownMenuItem(
                      value: type['code'],
                      child: Text('${type['code']} - ${type['name']}'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedType = value;
                        defect.defectType = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
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
                    defect.description = value;
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: sizeController,
                  decoration: const InputDecoration(
                    labelText: 'Размер дефекта (мм)',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF3b82f6)),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    defect.size = value;
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: 'Местоположение на шве',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF3b82f6)),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  onChanged: (value) {
                    defect.location = value;
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
                          _buildColorButton(Colors.red, defect, setDialogState),
                          _buildColorButton(Colors.blue, defect, setDialogState),
                          _buildColorButton(Colors.green, defect, setDialogState),
                          _buildColorButton(Colors.yellow, defect, setDialogState),
                          _buildColorButton(Colors.orange, defect, setDialogState),
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
                  _defects.remove(defect);
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
      ),
    );
  }

  Widget _buildColorButton(Color color, WeldDefect defect, StateSetter setDialogState) {
    return GestureDetector(
      onTap: () {
        setDialogState(() {
          defect.color = color;
        });
        setState(() {});
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: defect.color == color ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }

  String _getDefectTypeName(String code) {
    return DEFECT_TYPES.firstWhere(
      (type) => type['code'] == code,
      orElse: () => {'name': code},
    )['name']!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Дефекты сварного шва'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              if (_imageFile == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Сначала загрузите изображение'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (widget.onSave != null) {
                widget.onSave!(_imageFile!, _defects);
              }
              Navigator.pop(context, _imageFile);
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
                    if (_defects.isNotEmpty) {
                      setState(() {
                        _defects.removeLast();
                      });
                    }
                  },
                  tooltip: 'Отменить',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _defects.clear();
                    });
                  },
                  tooltip: 'Очистить все',
                ),
              ],
            ),
          ),
          // Область изображения с дефектами
          Expanded(
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
                            'Загрузите схему сварного шва',
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
                      onTapDown: _handleImageTap,
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
                            painter: WeldDefectPainter(_defects),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          // Список дефектов
          if (_defects.isNotEmpty)
            Container(
              height: 150,
              color: const Color(0xFF1e293b),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Дефекты (${_defects.length})',
                      style: const TextStyle(
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
                      itemCount: _defects.length,
                      itemBuilder: (context, index) {
                        final defect = _defects[index];
                        return GestureDetector(
                          onTap: () => _showDefectDialog(defect),
                          child: Container(
                            width: 150,
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0f172a),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: defect.color,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: defect.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _getDefectTypeName(defect.defectType),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (defect.size != null && defect.size!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Размер: ${defect.size} мм',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                if (defect.description != null && defect.description!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      defect.description!,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
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

class WeldDefectPainter extends CustomPainter {
  final List<WeldDefect> defects;

  WeldDefectPainter(this.defects);

  @override
  void paint(Canvas canvas, Size size) {
    for (var defect in defects) {
      final paint = Paint()
        ..color = defect.color
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;

      // Рисуем круг вокруг дефекта
      canvas.drawCircle(defect.position, 25, paint);
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(defect.position, 8, paint);

      // Рисуем текст с типом дефекта
      final textPainter = TextPainter(
        text: TextSpan(
          text: defect.defectType,
          style: TextStyle(
            color: defect.color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black.withOpacity(0.7),
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          defect.position.dx - textPainter.width / 2,
          defect.position.dy - textPainter.height - 30,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(WeldDefectPainter oldDelegate) {
    return oldDelegate.defects != defects;
  }
}

