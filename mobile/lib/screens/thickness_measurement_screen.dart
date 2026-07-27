import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'dart:io';
import 'package:image/image.dart' as img;
import '../models/vessel_checklist.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/photo_annotation_service.dart';
import '../services/bluetooth_measurement_service.dart';
import '../models/equipment.dart';
import '../models/drawing_template.dart';
import '../widgets/bluetooth_measurement_widget.dart';

class ThicknessMeasurementScreen extends StatefulWidget {
  final File? schemeImage;
  final List<ThicknessMeasurement>? existingMeasurements;
  final Function(List<ThicknessMeasurement>, File?)? onSave;
  final Equipment? equipment;

  const ThicknessMeasurementScreen({
    super.key,
    this.schemeImage,
    this.existingMeasurements,
    this.onSave,
    this.equipment,
  });

  @override
  State<ThicknessMeasurementScreen> createState() => _ThicknessMeasurementScreenState();
}

class _ThicknessMeasurementScreenState extends State<ThicknessMeasurementScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();
  final PhotoAnnotationService _photoAnnotationService = PhotoAnnotationService();
  File? _schemeImage;
  Size? _imageSize; // размер изображения для координат при зуме/сдвиге
  List<ThicknessMeasurement> _measurements = [];
  ThicknessMeasurement? _selectedPoint;
  bool _loadingTemplate = false;
  Offset? _pendingTapPosition;
  int? _activePointIndex;

  void _onBluetoothMeasurement(MeasurementResult result) {
    if (_measurements.isEmpty) return;
    final target = _activePointIndex != null &&
            _activePointIndex! < _measurements.length
        ? _measurements[_activePointIndex!]
        : _measurements.last;
    setState(() {
      target.thickness = result.value;
    });
  }

  @override
  void initState() {
    super.initState();
    _schemeImage = widget.schemeImage;
    _measurements = widget.existingMeasurements ?? [];
    if (_schemeImage != null) _loadImageSize();
    // Если нет фото схемы и оборудование - сосуд/ресивер, загружаем шаблон
    if (_schemeImage == null && _isVessel()) {
      _loadTemplate();
    }
  }

  Future<void> _loadImageSize() async {
    if (_schemeImage == null) return;
    try {
      final bytes = await _schemeImage!.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null && mounted) {
        setState(() {
          _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
        });
      }
    } catch (_) {}
  }

  bool _isVessel() {
    if (widget.equipment == null) return false;
    final typeCode = widget.equipment!.typeCode?.toUpperCase() ?? '';
    final typeName = widget.equipment!.typeName?.toUpperCase() ?? '';
    return typeCode.contains('VESSEL') || 
           typeName.contains('СОСУД') || 
           typeName.contains('РЕСИВЕР');
  }

  Future<void> _loadTemplate() async {
    if (!_isVessel()) return;
    
    setState(() {
      _loadingTemplate = true;
    });

    try {
      final templatePath = await _apiService.getVesselTemplate('vessel_template.png');
      if (templatePath != null && mounted) {
        setState(() {
          _schemeImage = File(templatePath);
          _loadingTemplate = false;
        });
        _loadImageSize();
      } else {
        setState(() {
          _loadingTemplate = false;
        });
      }
    } catch (e) {
      print('Ошибка загрузки шаблона: $e');
      setState(() {
        _loadingTemplate = false;
      });
    }
  }

  Future<void> _pickSchemeImage() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _schemeImage = File(image.path);
        _imageSize = null;
      });
      _loadImageSize();
    }
  }

  /// Открывает экран выбора шаблона чертежа с сервера (П.2 ТЗ 2026-04).
  /// После выбора: подставляет локально кэшированное изображение и
  /// автоматически заполняет список точек замера на основе предопределённых.
  Future<void> _pickServerDrawingTemplate() async {
    if (widget.equipment == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Оборудование не задано — нельзя выбрать шаблон'),
      ));
      return;
    }
    final result = await GoRouter.of(context).push<DrawingTemplate>(
      '/drawing-template-picker',
      extra: {
        'equipment': widget.equipment,
        'title': 'Выбор шаблона',
      },
    );
    if (result == null || !mounted) return;

    if (result.localImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Изображение шаблона не скачано. Подключитесь к сети и синхронизируйтесь.'),
      ));
      return;
    }

    final file = File(result.localImagePath!);
    if (!await file.exists()) return;

    // Конвертируем предопределённые точки шаблона в ThicknessMeasurement,
    // сохраняя % координаты, чтобы они корректно отображались на любом экране.
    final converted = <ThicknessMeasurement>[];
    for (final p in result.points) {
      final m = ThicknessMeasurement(
        location: p.label,
        sectionNumber: p.label,
      );
      m.xPercent = p.xPercent;
      m.yPercent = p.yPercent;
      m.nominalThickness = p.expectedValue;
      converted.add(m);
    }

    setState(() {
      _schemeImage = file;
      _imageSize = null;
      if (_measurements.isEmpty && converted.isNotEmpty) {
        _measurements = converted;
      }
    });
    await _loadImageSize();
  }

  void _handleImageTapAtLocal(Offset localPosition, Size imageSize) {
    if (_schemeImage == null) return;

    final double xPercent = (localPosition.dx / imageSize.width) * 100;
    final double yPercent = (localPosition.dy / imageSize.height) * 100;

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

  void _showPointDialog(ThicknessMeasurement point) {
    final nominalThicknessController =
        TextEditingController(text: point.nominalThickness?.toString() ?? '');
    final thicknessController =
        TextEditingController(text: point.thickness?.toString() ?? '');
    final minThicknessController =
        TextEditingController(text: point.minAllowedThickness?.toString() ?? '');
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
                controller: nominalThicknessController,
                decoration: const InputDecoration(
                  labelText: 'Номинальная толщина, мм',
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
                  point.nominalThickness = double.tryParse(value);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: thicknessController,
                readOnly: true,
                onTap: () async {
                  final v = await _showLargeThicknessKeypad(
                    initial: thicknessController.text,
                  );
                  if (v != null) {
                    thicknessController.text = v;
                    point.thickness = double.tryParse(v.replaceAll(',', '.'));
                    setState(() {});
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Фактическая толщина, мм (крупный ввод)',
                  labelStyle: TextStyle(color: Colors.white70),
                  suffixIcon: Icon(Icons.dialpad, color: Colors.white54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3b82f6)),
                  ),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 22),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  point.thickness = double.tryParse(value.replaceAll(',', '.'));
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: minThicknessController,
                decoration: const InputDecoration(
                  labelText: 'Отбраковочная толщина, мм',
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
              const SizedBox(height: 12),
              const Text(
                'Фото замеров (для отчёта)',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...point.photos.asMap().entries.map((e) => SizedBox(
                    width: 64,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(e.value),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 2),
                        InkWell(
                          onTap: () {
                            setState(() {
                              point.photos.removeAt(e.key);
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.close, color: Colors.red, size: 18),
                          ),
                        ),
                      ],
                    ),
                  )),
                  GestureDetector(
                    onTap: () async {
                      final img = await _imagePicker.pickImage(source: ImageSource.camera);
                      if (img != null && mounted) {
                        final path = await _maybeAddDateTimeGpsToPhoto(img.path);
                        setState(() {
                          point.photos.add(path);
                        });
                      }
                    },
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add_a_photo, color: Colors.white54, size: 28),
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


  Future<String?> _showLargeThicknessKeypad({String? initial}) async {
    var buf = initial ?? '';
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0f172a),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void tap(String s) {
              setLocal(() {
                if (s == 'DEL') {
                  if (buf.isNotEmpty) buf = buf.substring(0, buf.length - 1);
                } else if (s == '.' || s == ',') {
                  if (!buf.contains('.') && !buf.contains(',')) {
                    buf = buf.isEmpty ? '0.' : (buf + '.');
                  }
                } else {
                  buf = buf + s;
                }
              });
            }

            Widget keyBtn(String label, {Color? color}) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(
                    height: 64,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color ?? const Color(0xFF1e293b),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => tap(label == '<' ? 'DEL' : label),
                      child: Text(label == '<' ? '⌫' : label),
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Толщина, мм',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      buf.isEmpty ? '0' : buf,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [keyBtn('1'), keyBtn('2'), keyBtn('3')]),
                    Row(children: [keyBtn('4'), keyBtn('5'), keyBtn('6')]),
                    Row(children: [keyBtn('7'), keyBtn('8'), keyBtn('9')]),
                    Row(children: [
                      keyBtn('.'),
                      keyBtn('0'),
                      keyBtn('<', color: const Color(0xFF334155)),
                    ]),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Отмена'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3b82f6),
                              ),
                              onPressed: () =>
                                  Navigator.pop(ctx, buf.isEmpty ? null : buf),
                              child: const Text('OK'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _editPoint(ThicknessMeasurement point) {
    setState(() {
      _activePointIndex = _measurements.indexOf(point);
    });
    _showPointDialog(point);
  }

  Future<String> _maybeAddDateTimeGpsToPhoto(String imagePath) async {
    bool addMeta = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          backgroundColor: const Color(0xFF1e293b),
          title: const Text('Добавить на фото?', style: TextStyle(color: Colors.white)),
          content: CheckboxListTile(
            value: addMeta,
            onChanged: (v) => setInner(() => addMeta = v ?? true),
            title: const Text(
              'Добавить дату и GPS-координаты',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
            activeColor: const Color(0xFF3b82f6),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Пропустить', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, addMeta),
              child: const Text('ОК', style: TextStyle(color: Color(0xFF3b82f6))),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return imagePath;

    final now = DateTime.now();
    final dateStr = intl.DateFormat('dd.MM.yyyy HH:mm').format(now);
    Map<String, double>? coords;
    try {
      coords = await _locationService.getCurrentLocation();
    } catch (_) {}
    final gpsStr = coords != null
        ? '${coords['latitude']!.toStringAsFixed(6)}, ${coords['longitude']!.toStringAsFixed(6)}'
        : null;

    final result = await _photoAnnotationService.annotatePhotoWithDateTimeAndGps(
      imagePath: imagePath,
      dateTimeText: dateStr,
      gpsText: gpsStr,
    );
    return result ?? imagePath;
  }

  Widget _buildZoomableScheme() {
    final w = _imageSize?.width ?? MediaQuery.of(context).size.width - 32;
    final h = _imageSize?.height ?? (MediaQuery.of(context).size.height - 200) * 0.6;
    final imageSize = Size(w, h);

    Widget content = Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: w,
          height: h,
          child: Image.file(
            _schemeImage!,
            fit: BoxFit.fill,
          ),
        ),
        ..._measurements.map((point) {
          final hasBoth = point.thickness != null && point.minAllowedThickness != null;
          final isCritical = hasBoth && point.thickness! < point.minAllowedThickness!;
          final isOk = hasBoth && point.thickness! >= point.minAllowedThickness!;
          final color = isCritical
              ? Colors.red
              : isOk
                  ? const Color(0xFF3b82f6)
                  : Colors.grey;
          final left = point.xPercent != null ? (point.xPercent! / 100) * w - 12 : 0.0;
          final top = point.yPercent != null ? (point.yPercent! / 100) * h - 12 : 0.0;
          return Positioned(
            left: left.clamp(0.0, w - 24),
            top: top.clamp(0.0, h - 24),
            child: GestureDetector(
              onTap: () => _editPoint(point),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
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
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              _pendingTapPosition = details.localPosition;
            },
            onTap: () {
              if (_pendingTapPosition != null) {
                _handleImageTapAtLocal(_pendingTapPosition!, imageSize);
                _pendingTapPosition = null;
              }
            },
            onTapCancel: () => _pendingTapPosition = null,
          ),
        ),
      ],
    );

    if (_imageSize != null) {
      content = InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        panEnabled: true,
        scaleEnabled: true,
        child: content,
      );
    } else {
      content = content;
    }

    return content;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('УЗТ - Толщинометрия'),
            if (_schemeImage != null && _imageSize != null)
              const Text(
                'Масштаб и сдвиг: двумя пальцами',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              widget.onSave?.call(_measurements, _schemeImage);
              context.pop({
                'measurements': _measurements,
                'image': _schemeImage,
              });
            },
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: BluetoothMeasurementWidget(
              instrumentType: InstrumentType.thicknessGauge,
              onMeasurement: _onBluetoothMeasurement,
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1e293b),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: _loadingTemplate
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _schemeImage == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
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
                                  'Выберите или загрузите схему для нанесения точек',
                                  style: TextStyle(color: Colors.white70),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                if (widget.equipment != null)
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: _pickServerDrawingTemplate,
                                      icon: const Icon(Icons.inventory_2_outlined),
                                      label: const Text('Шаблон из библиотеки'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF3b82f6),
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                if (_isVessel()) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: _loadTemplate,
                                      icon: const Icon(Icons.download),
                                      label: const Text('Базовый шаблон сосуда'),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _pickSchemeImage,
                                    icon: const Icon(Icons.upload),
                                    label: const Text('Загрузить из галереи'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _buildZoomableScheme(),
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
                              final hasBoth = point.thickness != null && point.minAllowedThickness != null;
                              final isCritical = hasBoth && point.thickness! < point.minAllowedThickness!;
                              final isOk = hasBoth && point.thickness! >= point.minAllowedThickness!;
                              final bgColor = isCritical ? Colors.red : (isOk ? const Color(0xFF3b82f6) : Colors.grey);
                              return Card(
                                color: isCritical
                                    ? Colors.red.withValues(alpha: 0.2)
                                    : const Color(0xFF0f172a),
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: bgColor,
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
                                      if (point.nominalThickness != null)
                                        Text(
                                          'Номинальная: ${point.nominalThickness} мм',
                                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        ),
                                      if (point.thickness != null)
                                        Text(
                                          'Фактическая: ${point.thickness} мм',
                                          style: TextStyle(
                                            color: isCritical ? Colors.redAccent : Colors.white70,
                                          ),
                                        ),
                                      if (point.minAllowedThickness != null)
                                        Text(
                                          'Отбраковочная: ${point.minAllowedThickness} мм',
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

