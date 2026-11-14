import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../models/vessel_checklist.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/photo_annotation_service.dart';
import '../services/bluetooth_measurement_service.dart';
import '../models/equipment.dart';
import '../models/drawing_template.dart';
import '../widgets/bluetooth_measurement_widget.dart';
import '../widgets/inspection/thickness_defaults_editor.dart';

class ThicknessMeasurementScreen extends StatefulWidget {
  final File? schemeImage;
  final List<ThicknessMeasurement>? existingMeasurements;
  final Function(List<ThicknessMeasurement>, File?)? onSave;
  final Equipment? equipment;
  final ThicknessDefaults? thicknessDefaults;

  const ThicknessMeasurementScreen({
    super.key,
    this.schemeImage,
    this.existingMeasurements,
    this.onSave,
    this.equipment,
    this.thicknessDefaults,
  });

  @override
  State<ThicknessMeasurementScreen> createState() =>
      _ThicknessMeasurementScreenState();
}

class _ThicknessMeasurementScreenState
    extends State<ThicknessMeasurementScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final ApiService _apiService = const ApiService();
  final LocationService _locationService = LocationService();
  final PhotoAnnotationService _photoAnnotationService =
      PhotoAnnotationService();
  File? _schemeImage;
  Size? _imageSize; // размер изображения для координат при зуме/сдвиге
  List<ThicknessMeasurement> _measurements = [];
  bool _loadingTemplate = false;
  Offset? _pendingTapPosition;
  int? _activePointIndex;
  late ThicknessDefaults _defaults;
  bool _focusScheme = false;
  bool _canClose = false;
  bool _closing = false;

  void _finishEditing() {
    if (_closing) return;
    _closing = true;
    _defaults.applyTo(_measurements);
    widget.onSave?.call(_measurements, _schemeImage);
    setState(() => _canClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        context.pop({
          'measurements': _measurements,
          'image': _schemeImage,
          'thicknessDefaults': _defaults
        });
    });
  }

  Future<void> _editDefaults() async {
    var value = _defaults;
    final updated = await showDialog<ThicknessDefaults>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (context, updateDialog) => AlertDialog(
                title: const Text('Параметры всего сосуда'),
                content: SingleChildScrollView(
                    child: ThicknessDefaultsEditor(
                        settings: value,
                        onChanged: (settings) =>
                            updateDialog(() => value = settings))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, value),
                      child: const Text('Применить'))
                ],
              ),
            ));
    if (updated != null && mounted)
      setState(() {
        updated.applyTo(_measurements, previous: _defaults);
        _defaults = updated;
      });
  }

  void _onBluetoothMeasurement(MeasurementResult result) {
    if (_measurements.isEmpty) return;
    final target =
        _activePointIndex != null && _activePointIndex! < _measurements.length
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
    _measurements = (widget.existingMeasurements ?? [])
        .map((point) => ThicknessMeasurement.fromJson(point.toJson()))
        .toList();
    double? uniform(double? Function(ThicknessMeasurement) get) {
      final values = _measurements.map(get).whereType<double>().toSet();
      return values.length == 1 ? values.single : null;
    }

    _defaults = widget.thicknessDefaults ??
        ThicknessDefaults(
          nominalThickness: ThicknessDefaults.parse(
                  widget.equipment?.attributes?['wall_thickness']) ??
              uniform((point) => point.nominalThickness),
          minAllowedThickness: ThicknessDefaults.parse(
                  widget.equipment?.attributes?['min_wall_thickness']) ??
              uniform((point) => point.minAllowedThickness),
        );
    _defaults.applyTo(_measurements);
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
          _imageSize =
              Size(decoded.width.toDouble(), decoded.height.toDouble());
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
      final templatePath =
          await _apiService.getVesselTemplate('vessel_template.png');
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
        content: Text(
            'Изображение шаблона не скачано. Подключитесь к сети и синхронизируйтесь.'),
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
    if (_measurements.length >= 150) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Достигнут лимит 150 точек УЗТ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final double xPercent = (localPosition.dx / imageSize.width) * 100;
    final double yPercent = (localPosition.dy / imageSize.height) * 100;

    if (xPercent < 0 || xPercent > 100 || yPercent < 0 || yPercent > 100)
      return;

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

  Future<void> _massAddGrid() async {
    final countCtrl = TextEditingController(text: '30');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Text('Массовое добавление точек',
            style: TextStyle(color: AppColors.onSurface(context))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Точки будут расставлены сеткой по схеме (без наездов). Максимум 150.',
              style:
                  TextStyle(color: AppColors.mutedText(context), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: countCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppColors.onSurface(context)),
              decoration: InputDecoration(
                labelText: 'Количество точек',
                labelStyle: TextStyle(color: AppColors.mutedText(context)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Добавить')),
        ],
      ),
    );
    if (ok != true) return;
    final want = int.tryParse(countCtrl.text.trim()) ?? 0;
    if (want <= 0) return;
    final room = 150 - _measurements.length;
    if (room <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Достигнут лимит 150 точек УЗТ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final n = want > room ? room : want;
    final cols =
        (n <= 4) ? n : math.max(4, math.min(20, math.sqrt(n * 1.6).ceil()));
    final rows = ((n + cols - 1) / cols).ceil();
    final start = _measurements.length;
    final added = <ThicknessMeasurement>[];
    for (var i = 0; i < n; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final xp = 12.0 + 76.0 * ((col + 0.5) / cols);
      final yp = 22.0 + 56.0 * ((row + 0.5) / rows);
      final num = start + i + 1;
      final m = ThicknessMeasurement(
        location: 'Точка $num',
        sectionNumber: '$num',
      );
      m.xPercent = double.parse(xp.toStringAsFixed(2));
      m.yPercent = double.parse(yp.toStringAsFixed(2));
      added.add(m);
    }
    setState(() => _measurements.addAll(added));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Добавлено $n точек сеткой ($cols×$rows)'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showPointDialog(ThicknessMeasurement point) {
    _defaults.applyTo([point]);
    final nominalThicknessController =
        TextEditingController(text: point.nominalThickness?.toString() ?? '');
    final thicknessController =
        TextEditingController(text: point.thickness?.toString() ?? '');
    final minThicknessController = TextEditingController(
        text: point.minAllowedThickness?.toString() ?? '');
    final commentController = TextEditingController(text: point.comment ?? '');
    final locationController = TextEditingController(text: point.location);
    final sectionController = TextEditingController(text: point.sectionNumber);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Text(
          'Параметры точки замера',
          style: TextStyle(color: AppColors.onSurface(context)),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: locationController,
                decoration: InputDecoration(
                  labelText: 'Местоположение',
                  labelStyle: TextStyle(color: AppColors.mutedText(context)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border(context)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3b82f6)),
                  ),
                ),
                style: TextStyle(color: AppColors.onSurface(context)),
                onChanged: (value) => point.location = value,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: sectionController,
                decoration: InputDecoration(
                  labelText: 'Номер участка',
                  labelStyle: TextStyle(color: AppColors.mutedText(context)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border(context)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3b82f6)),
                  ),
                ),
                style: TextStyle(color: AppColors.onSurface(context)),
                onChanged: (value) => point.sectionNumber = value,
              ),
              const SizedBox(height: 8),
              Text(
                  'Номинальная: ${point.nominalThickness ?? "не задана"} мм · Минимальная: ${point.minAllowedThickness ?? "не задана"} мм',
                  style: TextStyle(color: AppColors.mutedText(context))),
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
                decoration: InputDecoration(
                  labelText: 'Фактическая толщина, мм (крупный ввод)',
                  labelStyle: TextStyle(color: AppColors.mutedText(context)),
                  suffixIcon:
                      Icon(Icons.dialpad, color: AppColors.mutedText(context)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border(context)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3b82f6)),
                  ),
                ),
                style: TextStyle(
                    color: AppColors.onSurface(context), fontSize: 22),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  point.thickness = double.tryParse(value.replaceAll(',', '.'));
                },
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                  title: const Text('Индивидуальные нормативы элемента'),
                  children: [
                    TextField(
                      controller: nominalThicknessController,
                      decoration: InputDecoration(
                        labelText: 'Номинальная толщина, мм',
                        labelStyle:
                            TextStyle(color: AppColors.mutedText(context)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: AppColors.border(context)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF3b82f6)),
                        ),
                      ),
                      style: TextStyle(color: AppColors.onSurface(context)),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        point.nominalThickness = ThicknessDefaults.parse(value);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: minThicknessController,
                      decoration: InputDecoration(
                        labelText: 'Отбраковочная толщина, мм',
                        labelStyle:
                            TextStyle(color: AppColors.mutedText(context)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: AppColors.border(context)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF3b82f6)),
                        ),
                      ),
                      style: TextStyle(color: AppColors.onSurface(context)),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        point.minAllowedThickness =
                            ThicknessDefaults.parse(value);
                      },
                    ),
                    const SizedBox(height: 8),
                  ]),
              TextField(
                controller: commentController,
                decoration: InputDecoration(
                  labelText: 'Комментарий',
                  labelStyle: TextStyle(color: AppColors.mutedText(context)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border(context)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3b82f6)),
                  ),
                ),
                style: TextStyle(color: AppColors.onSurface(context)),
                maxLines: 3,
                onChanged: (value) => point.comment = value,
              ),
              const SizedBox(height: 12),
              Text(
                'Фото замеров (для отчёта)',
                style: TextStyle(
                    color: AppColors.mutedText(context), fontSize: 14),
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
                                child: Icon(Icons.close,
                                    color: Colors.red, size: 18),
                              ),
                            ),
                          ],
                        ),
                      )),
                  GestureDetector(
                    onTap: () async {
                      final img = await _imagePicker.pickImage(
                          source: ImageSource.camera);
                      if (img != null && mounted) {
                        final path =
                            await _maybeAddDateTimeGpsToPhoto(img.path);
                        setState(() {
                          point.photos.add(path);
                        });
                      }
                    },
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border(context)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.add_a_photo,
                          color: AppColors.mutedText(context), size: 28),
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
      backgroundColor: AppColors.scaffold(context),
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
                        backgroundColor: color ?? AppColors.surface(context),
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
                    Text(
                      'Толщина, мм',
                      style: TextStyle(
                          color: AppColors.mutedText(context), fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      buf.isEmpty ? '0' : buf,
                      style: TextStyle(
                        color: AppColors.onSurface(context),
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
          backgroundColor: AppColors.surface(context),
          title: Text('Добавить на фото?',
              style: TextStyle(color: AppColors.onSurface(context))),
          content: CheckboxListTile(
            value: addMeta,
            onChanged: (v) => setInner(() => addMeta = v ?? true),
            title: Text(
              'Добавить дату и GPS-координаты',
              style:
                  TextStyle(color: AppColors.onSurface(context), fontSize: 15),
            ),
            activeColor: const Color(0xFF3b82f6),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Пропустить',
                  style: TextStyle(color: AppColors.mutedText(context))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, addMeta),
              child:
                  const Text('ОК', style: TextStyle(color: Color(0xFF3b82f6))),
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

    final result =
        await _photoAnnotationService.annotatePhotoWithDateTimeAndGps(
      imagePath: imagePath,
      dateTimeText: dateStr,
      gpsText: gpsStr,
    );
    return result ?? imagePath;
  }

  Widget _buildZoomableScheme() {
    return LayoutBuilder(builder: (context, constraints) {
      final fitted = applyBoxFit(BoxFit.contain,
              _imageSize ?? constraints.biggest, constraints.biggest)
          .destination;
      final w = fitted.width;
      final h = fitted.height;
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
          // Слой добавления точки лежит под маркерами: иначе тап по готовому
          // маркеру перехватывался им и создавал новую точку поверх старой.
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
          ..._measurements.map((point) {
            final hasBoth =
                point.thickness != null && point.minAllowedThickness != null;
            final isCritical =
                hasBoth && point.thickness! < point.minAllowedThickness!;
            final isOk =
                hasBoth && point.thickness! >= point.minAllowedThickness!;
            final color = isCritical
                ? Colors.red
                : isOk
                    ? const Color(0xFF3b82f6)
                    : Colors.grey;
            final left =
                point.xPercent != null ? (point.xPercent! / 100) * w - 22 : 0.0;
            final top =
                point.yPercent != null ? (point.yPercent! / 100) * h - 22 : 0.0;
            return Positioned(
              left: left.clamp(0.0, math.max(0, w - 44)),
              top: top.clamp(0.0, math.max(0, h - 44)),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _editPoint(point),
                child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
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
                    ))),
              ),
            );
          }),
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

      return Center(child: SizedBox(width: w, height: h, child: content));
    });
  }

  @override
  Widget build(BuildContext context) {
    _defaults.applyTo(_measurements);
    return PopScope(
        canPop: _canClose,
        onPopInvoked: (didPop) {
          if (!didPop) _finishEditing();
        },
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('УЗТ - Толщинометрия',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (_schemeImage != null &&
                    _imageSize != null &&
                    MediaQuery.textScalerOf(context).scale(12) <= 16)
                  Text(
                    'Масштаб и сдвиг: двумя пальцами',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: AppColors.mutedText(context)),
                  ),
              ],
            ),
            backgroundColor: AppColors.scaffold(context),
            foregroundColor: AppColors.onSurface(context),
            actions: [
              IconButton(
                icon: Icon(
                    _focusScheme ? Icons.fullscreen_exit : Icons.fullscreen),
                tooltip: _focusScheme
                    ? 'Показать точки и параметры'
                    : 'Развернуть схему',
                onPressed: () => setState(() => _focusScheme = !_focusScheme),
              ),
              IconButton(
                icon: const Icon(Icons.grid_on),
                tooltip: 'Массовое добавление сеткой',
                onPressed: _massAddGrid,
              ),
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'Сохранить замеры',
                onPressed: _finishEditing,
              ),
            ],
          ),
          backgroundColor: AppColors.scaffold(context),
          body: SafeArea(
              top: false,
              child: Column(
                children: [
                  if (!_focusScheme)
                    ListTile(
                      title: const Text('Общие толщины сосуда'),
                      subtitle: Text(
                          'Номинальная: ${_defaults.nominalThickness ?? 'не задана'} мм · Минимальная: ${_defaults.minAllowedThickness ?? 'не задана'} мм'),
                      trailing: IconButton(
                          icon: const Icon(Icons.settings),
                          tooltip: 'Общие параметры толщины',
                          onPressed: _editDefaults),
                    ),
                  if (!_focusScheme)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: BluetoothMeasurementWidget(
                        instrumentType: InstrumentType.thicknessGauge,
                        onMeasurement: _onBluetoothMeasurement,
                      ),
                    ),
                  Expanded(
                      child: LayoutBuilder(builder: (context, constraints) {
                    final wide = constraints.maxWidth > 600;
                    return Flex(
                        direction: wide ? Axis.horizontal : Axis.vertical,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Container(
                              margin: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surface(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.border(context)),
                              ),
                              child: _loadingTemplate
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : _schemeImage == null
                                      ? Center(
                                          child: SingleChildScrollView(
                                              child: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.image,
                                                  size: 64,
                                                  color: AppColors.mutedText(
                                                      context),
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  'Выберите или загрузите схему для нанесения точек',
                                                  style: TextStyle(
                                                      color:
                                                          AppColors.mutedText(
                                                              context)),
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 16),
                                                if (widget.equipment != null)
                                                  SizedBox(
                                                    width: double.infinity,
                                                    child: ElevatedButton.icon(
                                                      onPressed:
                                                          _pickServerDrawingTemplate,
                                                      icon: const Icon(Icons
                                                          .inventory_2_outlined),
                                                      label: const Text(
                                                          'Шаблон из библиотеки'),
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            const Color(
                                                                0xFF3b82f6),
                                                        foregroundColor:
                                                            Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                if (_isVessel()) ...[
                                                  const SizedBox(height: 8),
                                                  SizedBox(
                                                    width: double.infinity,
                                                    child: OutlinedButton.icon(
                                                      onPressed: _loadTemplate,
                                                      icon: const Icon(
                                                          Icons.download),
                                                      label: const Text(
                                                          'Базовый шаблон сосуда'),
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(height: 8),
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: OutlinedButton.icon(
                                                    onPressed: _pickSchemeImage,
                                                    icon: const Icon(
                                                        Icons.upload),
                                                    label: const Text(
                                                        'Загрузить из галереи'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )),
                                        )
                                      : _buildZoomableScheme(),
                            ),
                          ),
                          if (!_focusScheme)
                            Expanded(
                              flex: 2,
                              child: Container(
                                color: AppColors.surface(context),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                              child: Text(
                                            'Точки замера (${_measurements.length})',
                                            style: TextStyle(
                                              color:
                                                  AppColors.onSurface(context),
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )),
                                          if (_schemeImage != null)
                                            IconButton(
                                              icon: const Icon(Icons.add_circle,
                                                  color: Color(0xFF3b82f6)),
                                              onPressed: _pickSchemeImage,
                                              tooltip: 'Изменить схему',
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: _measurements.isEmpty
                                          ? Center(
                                              child: Text(
                                                'Нажмите на схему, чтобы добавить точку замера',
                                                style: TextStyle(
                                                    color: AppColors.mutedText(
                                                        context)),
                                                textAlign: TextAlign.center,
                                              ),
                                            )
                                          : ListView.builder(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16),
                                              itemCount: _measurements.length,
                                              itemBuilder: (context, index) {
                                                final point =
                                                    _measurements[index];
                                                final hasBoth = point
                                                            .thickness !=
                                                        null &&
                                                    point.minAllowedThickness !=
                                                        null;
                                                final isCritical = hasBoth &&
                                                    point.thickness! <
                                                        point
                                                            .minAllowedThickness!;
                                                final isOk = hasBoth &&
                                                    point.thickness! >=
                                                        point
                                                            .minAllowedThickness!;
                                                final bgColor = isCritical
                                                    ? Colors.red
                                                    : (isOk
                                                        ? const Color(
                                                            0xFF3b82f6)
                                                        : Colors.grey);
                                                return Card(
                                                  color: isCritical
                                                      ? Colors.red.withValues(
                                                          alpha: 0.2)
                                                      : AppColors.scaffold(
                                                          context),
                                                  margin: const EdgeInsets.only(
                                                      bottom: 8),
                                                  child: ListTile(
                                                    leading: CircleAvatar(
                                                      backgroundColor: bgColor,
                                                      child:
                                                          Text('${index + 1}'),
                                                    ),
                                                    title: Text(
                                                      '${point.location} (${point.sectionNumber})',
                                                      style: TextStyle(
                                                        color: isCritical
                                                            ? Colors.red
                                                            : AppColors
                                                                .onSurface(
                                                                    context),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    subtitle: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        if (point
                                                                .nominalThickness !=
                                                            null)
                                                          Text(
                                                            'Номинальная: ${point.nominalThickness} мм',
                                                            style: TextStyle(
                                                                color: AppColors
                                                                    .mutedText(
                                                                        context),
                                                                fontSize: 11),
                                                          ),
                                                        if (point.thickness !=
                                                            null)
                                                          Text(
                                                            'Фактическая: ${point.thickness} мм',
                                                            style: TextStyle(
                                                              color: isCritical
                                                                  ? Colors
                                                                      .redAccent
                                                                  : AppColors
                                                                      .mutedText(
                                                                          context),
                                                            ),
                                                          ),
                                                        if (point
                                                                .minAllowedThickness !=
                                                            null)
                                                          Text(
                                                            'Отбраковочная: ${point.minAllowedThickness} мм',
                                                            style: TextStyle(
                                                                color: AppColors
                                                                    .mutedText(
                                                                        context)),
                                                          ),
                                                        if (point.comment !=
                                                                null &&
                                                            point.comment!
                                                                .isNotEmpty)
                                                          Text(
                                                            point.comment!,
                                                            style: TextStyle(
                                                                color: AppColors
                                                                    .mutedText(
                                                                        context)),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                      ],
                                                    ),
                                                    trailing: IconButton(
                                                      icon: const Icon(
                                                          Icons.edit,
                                                          color: Color(
                                                              0xFF3b82f6)),
                                                      onPressed: () =>
                                                          _editPoint(point),
                                                    ),
                                                    onTap: () =>
                                                        _editPoint(point),
                                                  ),
                                                );
                                              },
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ]);
                  })),
                ],
              )),
        ));
  }
}
