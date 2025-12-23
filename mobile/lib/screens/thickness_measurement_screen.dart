import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/vessel_checklist.dart';

class ThicknessMeasurementScreen extends StatefulWidget {
  final File? schemeImage;
  final List<ThicknessMeasurement>? existingMeasurements;
  final Function(List<ThicknessMeasurement>, File?) onSave;

  const ThicknessMeasurementScreen({
    super.key,
    this.schemeImage,
    this.existingMeasurements,
    required this.onSave,
  });

  @override
  State<ThicknessMeasurementScreen> createState() => _ThicknessMeasurementScreenState();
}

class _ThicknessMeasurementScreenState extends State<ThicknessMeasurementScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  File? _schemeImage;
  List<ThicknessMeasurement> _measurements = [];
  ThicknessMeasurement? _selectedPoint;

  @override
  void initState() {
    super.initState();
    _schemeImage = widget.schemeImage;
    _measurements = widget.existingMeasurements ?? [];
  }

  Future<void> _pickSchemeImage() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _schemeImage = File(image.path);
      });
    }
  }

  void _handleImageTap(TapDownDetails details, Size imageSize) {
    if (_schemeImage == null) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
    
    // Находим контейнер изображения
    final imageContainer = _getImageContainerBounds();
    if (imageContainer == null) return;

    final double xPercent = ((localPosition.dx - imageContainer.left) / imageContainer.width) * 100;
    final double yPercent = ((localPosition.dy - imageContainer.top) / imageContainer.height) * 100;

    if (xPercent < 0 || xPercent > 100 || yPercent < 0 || yPercent > 100) return;

    final newPoint = ThicknessMeasurement(
      location: 'Точка ${_measurements.length + 1}',
      sectionNumber: '${_measurements.length + 1}',
    );
    newPoint.xPercent = xPercent;
    newPoint.yPercent = yPercent;

    setState(() {
      _measurements.add(newPoint);
    });

    _showPointDialog(newPoint);
  }

  Rect? _getImageContainerBounds() {
    // Упрощенная версия - используем размер экрана
    final size = MediaQuery.of(context).size;
    return Rect.fromLTWH(16, 100, size.width - 32, size.height - 400);
  }

  void _showPointDialog(ThicknessMeasurement point) {
    final thicknessController = TextEditingController();
    final minThicknessController = TextEditingController();
    final commentController = TextEditingController(text: point.comment ?? '');
    final locationController = TextEditingController(text: point.location);
    final sectionController = TextEditingController(text: point.sectionNumber);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text(
          'Параметры точки замера',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: 'Местоположение',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3b82f6)),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) => point.location = value,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: sectionController,
                decoration: const InputDecoration(
                  labelText: 'Номер участка',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3b82f6)),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) => point.sectionNumber = value,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: thicknessController,
                decoration: const InputDecoration(
                  labelText: 'Толщина, мм',
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
                  point.thickness = double.tryParse(value);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: minThicknessController,
                decoration: const InputDecoration(
                  labelText: 'Минимальная допустимая, мм',
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
                  point.minAllowedThickness = double.tryParse(value);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(
                  labelText: 'Комментарий',
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
                onChanged: (value) => point.comment = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _measurements.remove(point);
              });
              Navigator.pop(context);
            },
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _editPoint(ThicknessMeasurement point) {
    _showPointDialog(point);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('УЗТ - Толщинометрия'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              widget.onSave(_measurements, _schemeImage);
              Navigator.pop(context);
            },
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: Column(
        children: [
          // Схема с точками
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1e293b),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: _schemeImage == null
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
                            'Загрузите схему для нанесения точек',
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _pickSchemeImage,
                            icon: const Icon(Icons.upload),
                            label: const Text('Загрузить схему'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3b82f6),
                            ),
                          ),
                        ],
                      ),
                    )
                  : GestureDetector(
                      onTapDown: (details) {
                        final size = MediaQuery.of(context).size;
                        final containerWidth = size.width - 32;
                        final containerHeight = (size.height - 200) * 0.6;
                        _handleImageTap(details, Size(containerWidth, containerHeight));
                      },
                      child: Stack(
                        children: [
                          Center(
                            child: Image.file(
                              _schemeImage!,
                              fit: BoxFit.contain,
                            ),
                          ),
                          ..._measurements.map((point) {
                            final isCritical = point.thickness != null &&
                                point.minAllowedThickness != null &&
                                point.thickness! < point.minAllowedThickness!;
                            return Positioned(
                              left: point.xPercent != null
                                  ? (MediaQuery.of(context).size.width - 32) * (point.xPercent! / 100) - 12
                                  : 0,
                              top: point.yPercent != null
                                  ? ((MediaQuery.of(context).size.height - 200) * 0.6) * (point.yPercent! / 100) - 12
                                  : 0,
                              child: GestureDetector(
                                onTap: () => _editPoint(point),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isCritical ? Colors.red : const Color(0xFF3b82f6),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2.0),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${_measurements.indexOf(point) + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
            ),
          ),
          // Список точек
          Expanded(
            flex: 2,
            child: Container(
              color: const Color(0xFF1e293b),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Точки замера (${_measurements.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_schemeImage != null)
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: Color(0xFF3b82f6)),
                            onPressed: _pickSchemeImage,
                            tooltip: 'Изменить схему',
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _measurements.isEmpty
                        ? const Center(
                            child: Text(
                              'Нажмите на схему, чтобы добавить точку замера',
                              style: TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _measurements.length,
                            itemBuilder: (context, index) {
                              final point = _measurements[index];
                              final isCritical = point.thickness != null &&
                                  point.minAllowedThickness != null &&
                                  point.thickness! < point.minAllowedThickness!;
                              return Card(
                                color: isCritical
                                    ? Colors.red.withValues(alpha: 0.2)
                                    : const Color(0xFF0f172a),
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        isCritical ? Colors.red : const Color(0xFF3b82f6),
                                    child: Text('${index + 1}'),
                                  ),
                                  title: Text(
                                    '${point.location} (${point.sectionNumber})',
                                    style: TextStyle(
                                      color: isCritical ? Colors.red : Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (point.thickness != null)
                                        Text(
                                          'Толщина: ${point.thickness} мм',
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                      if (point.minAllowedThickness != null)
                                        Text(
                                          'Мин. допустимая: ${point.minAllowedThickness} мм',
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                      if (point.comment != null && point.comment!.isNotEmpty)
                                        Text(
                                          point.comment!,
                                          style: const TextStyle(color: Colors.white54),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.edit, color: Color(0xFF3b82f6)),
                                    onPressed: () => _editPoint(point),
                                  ),
                                  onTap: () => _editPoint(point),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

