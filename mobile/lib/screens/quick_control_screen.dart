import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as Path;
import '../services/image_resize_service.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/auto_save_service.dart';
import '../models/vessel_checklist.dart';
import '../theme/app_colors.dart';
import 'defect_statement_screen.dart';

/// Дефект ВИК для быстрого контроля
class _VikDefect {
  String? type;
  String location = '';
  String size = '';
  String description = '';

  _VikDefect();
}

/// Экран «Быстрый контроль ВИК/УЗТ» (П.1.1.1)
/// Структура протокола по образцу с фото:
///   Шапка: Дата | Место | Объект | Заказчик | Исполнитель | Приборы
///   ВИК:  Фото/схема + Таблица дефектов
///   УЗТ:  Фото/схема (с тапом → карта замеров) + Таблица замеров
class QuickControlScreen extends StatefulWidget {
  /// При возобновлении черновика — сохранённые данные
  final Map<String, dynamic>? savedDraft;
  /// Заголовок AppBar (например, «Экспресс-диагностика НК» с хаба быстрого контроля)
  final String? appBarTitle;
  /// 0 — вкладка ВИК, 1 — УЗТ (экспресс-диагностика по методу).
  final int initialTabIndex;
  const QuickControlScreen({
    super.key,
    this.savedDraft,
    this.appBarTitle,
    this.initialTabIndex = 0,
  });

  @override
  State<QuickControlScreen> createState() => _QuickControlScreenState();
}

class _QuickControlScreenState extends State<QuickControlScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _apiService = ApiService();
  final _syncService = SyncService();
  final _autoSaveService = AutoSaveService();
  final _imagePicker = ImagePicker();
  late final String _draftId;

  // ---- Общие поля ----
  final _dateCtrl = TextEditingController(
      text: intl.DateFormat('dd.MM.yyyy').format(DateTime.now()));
  final _locationCtrl = TextEditingController();
  final _objectCtrl = TextEditingController();
  final _customerCtrl = TextEditingController();
  final _executorCtrl = TextEditingController();
  final _devicesCtrl = TextEditingController();

  // ---- ВИК ----
  final List<File> _vikPhotos = [];
  final List<_VikDefect> _vikDefects = [];

  // ---- УЗТ (связка схема + ThicknessMeasurement) ----
  File? _uztSchemeFile;
  List<ThicknessMeasurement> _uztMeasurements = [
    ThicknessMeasurement(location: '', sectionNumber: '1'),
    ThicknessMeasurement(location: '', sectionNumber: '2'),
    ThicknessMeasurement(location: '', sectionNumber: '3'),
  ];
  final List<File> _uztPhotos = []; // доп. фото помимо схемы

  bool _loadingInstruments = false;

  @override
  void initState() {
    super.initState();
    _draftId = widget.savedDraft?['id'] as String? ??
        'qc_${DateTime.now().millisecondsSinceEpoch}';
    final tab = widget.initialTabIndex.clamp(0, 1);
    _tabController = TabController(length: 2, vsync: this, initialIndex: tab);

    // Восстанавливаем черновик если передан
    if (widget.savedDraft != null) {
      _restoreFromDraft(widget.savedDraft!);
    } else {
      _loadMyInstruments();
    }
  }

  void _restoreFromDraft(Map<String, dynamic> draft) {
    final data = draft['checklist_data'] as Map<String, dynamic>? ?? {};
    _dateCtrl.text = data['date'] as String? ?? _dateCtrl.text;
    _locationCtrl.text = data['location'] as String? ?? '';
    _objectCtrl.text = data['object_name'] as String? ?? '';
    _customerCtrl.text = data['customer'] as String? ?? '';
    _executorCtrl.text = data['executor'] as String? ?? '';
    _devicesCtrl.text = data['devices'] as String? ?? '';

    // ВИК дефекты
    final vikRaw = data['vik_defects'] as List? ?? [];
    for (final d in vikRaw) {
      if (d is Map) {
        _vikDefects.add(_VikDefect()
          ..type = d['type']?.toString()
          ..location = d['location']?.toString() ?? ''
          ..size = d['size']?.toString() ?? ''
          ..description = d['description']?.toString() ?? '');
      }
    }

    // УЗТ замеры
    final uztRaw = data['uzt_measurements'] as List? ?? [];
    if (uztRaw.isNotEmpty) {
      _uztMeasurements = uztRaw
          .whereType<Map>()
          .map((m) =>
              ThicknessMeasurement.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    // Схема
    final schemePath = data['uzt_scheme'] as String?;
    if (schemePath != null) {
      final f = File(schemePath);
      if (f.existsSync()) _uztSchemeFile = f;
    }

    _loadMyInstruments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dateCtrl.dispose();
    _locationCtrl.dispose();
    _objectCtrl.dispose();
    _customerCtrl.dispose();
    _executorCtrl.dispose();
    _devicesCtrl.dispose();
    super.dispose();
  }

  /// П.4.5 — Автоматически подтягивает закреплённые приборы в поле «Приборы»
  Future<void> _loadMyInstruments() async {
    setState(() => _loadingInstruments = true);
    try {
      final data = await _apiService.getMyInstruments();
      if (mounted && data.isNotEmpty) {
        final names = data
            .map((i) => '${i['name'] ?? ''}${(i['type'] ?? '').isNotEmpty ? ' (${i['type']})' : ''}')
            .where((s) => s.trim().isNotEmpty)
            .join(', ');
        if (_devicesCtrl.text.trim().isEmpty) {
          setState(() => _devicesCtrl.text = names);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingInstruments = false);
    }
  }

  // ============================================================
  //  Общие утилиты
  // ============================================================

  Future<void> _pickPhoto(List<File> target, ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      final resized = await ImageResizeService.resizeIfNeeded(picked.path);
      final dir = await getApplicationDocumentsDirectory();
      final storageDir = Directory(Path.join(dir.path, 'quick_control'));
      if (!await storageDir.exists()) await storageDir.create(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final dest = Path.join(storageDir.path, 'photo_$ts.jpg');
      await File(resized).copy(dest);
      setState(() => target.add(File(dest)));
    } catch (e) {
      _showError('Ошибка загрузки фото: $e');
    }
  }

  Future<ImageSource?> _askPhotoSource() => showDialog<ImageSource>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Добавить фото/схему'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ImageSource.camera),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.camera_alt, size: 16),
                  SizedBox(width: 4),
                  Text('Камера'),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library, size: 16),
                  SizedBox(width: 4),
                  Text('Галерея'),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
          ],
        ),
      );

  Future<void> _confirmDelete(VoidCallback onConfirm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтверждение'),
        content: const Text('Вы уверены? Данные будут удалены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    if (ok == true) onConfirm();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ============================================================
  //  OPEN ThicknessMeasurementScreen (связка точка на схеме = точка в таблице, П.1.1.1)
  // ============================================================

  Future<void> _openThicknessMap() async {
    final result = await context.push<Map<String, dynamic>>(
      '/thickness-measurement',
      extra: {
        'schemeImage': _uztSchemeFile,
        'existingMeasurements': _uztMeasurements,
        'equipment': null,
      },
    );
    if (result != null) {
      final measurements = result['measurements'] as List<ThicknessMeasurement>?;
      final image = result['image'] as File?;
      setState(() {
        if (measurements != null) _uztMeasurements = measurements;
        if (image != null) _uztSchemeFile = image;
      });
    }
  }

  // ============================================================
  //  Добавить дефект ВИК
  // ============================================================

  Future<void> _addVikDefect({_VikDefect? existing, int? editIndex}) async {
    final defect = existing ?? _VikDefect();
    String? type = defect.type;
    final locCtrl = TextEditingController(text: defect.location);
    final sizeCtrl = TextEditingController(text: defect.size);
    final descCtrl = TextEditingController(text: defect.description);
    final defectTypes = [
      'Коррозия', 'Вмятина', 'Трещина', 'Разрыв', 'Скол',
      'Потеря металла', 'Расслоение', 'Другое'
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing != null ? 'Редактировать дефект' : 'Добавить дефект ВИК'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Тип дефекта *'),
                  items: defectTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setLocal(() => type = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: locCtrl,
                  decoration: const InputDecoration(labelText: 'Место/узел'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: sizeCtrl,
                  decoration: const InputDecoration(labelText: 'Размер (мм)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Описание'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                if (type == null) return;
                defect.type = type;
                defect.location = locCtrl.text;
                defect.size = sizeCtrl.text;
                defect.description = descCtrl.text;
                setState(() {
                  if (editIndex != null) {
                    _vikDefects[editIndex] = defect;
                  } else {
                    _vikDefects.add(defect);
                  }
                });
                Navigator.pop(ctx);
              },
              child: Text(existing != null ? 'Сохранить' : 'Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  //  Выбрать приборы из реестра (П.4.6/4.7)
  // ============================================================

  Future<void> _pickInstrumentsFromRegistry() async {
    try {
      final data = await _apiService.getInstruments();
      if (!mounted) return;
      final List<Map<String, dynamic>> instruments =
          List<Map<String, dynamic>>.from(data);
      if (instruments.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Реестр приборов пуст')),
        );
        return;
      }
      final selected = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        builder: (ctx) => _InstrumentPickerDialog(instruments: instruments),
      );
      if (selected != null && selected.isNotEmpty) {
        final names = selected
            .map((i) => '${i['name'] ?? ''}${(i['type'] ?? '').isNotEmpty ? ' (${i['type']})' : ''}')
            .join(', ');
        setState(() {
          _devicesCtrl.text = _devicesCtrl.text.trim().isEmpty
              ? names
              : '${_devicesCtrl.text}, $names';
        });
      }
    } catch (e) {
      _showError('Ошибка загрузки реестра: $e');
    }
  }

  // ============================================================
  //  BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: Text(widget.appBarTitle ?? 'Быстрый контроль ВИК/УЗТ'),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.darkPrimary,
          labelColor: AppColors.darkPrimary,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.visibility, size: 18), text: 'ВИК'),
            Tab(icon: Icon(Icons.waves, size: 18), text: 'УЗТ'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildHeaderFields(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildVikTab(), _buildUztTab()],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        child: _buildBottomButtons(),
      ),
    );
  }

  // ---- Шапка протокола ----
  Widget _buildHeaderFields() {
    return Container(
      color: const Color(0xFF1e293b),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _field(_dateCtrl, 'Дата')),
              const SizedBox(width: 8),
              Expanded(child: _field(_locationCtrl, 'Место проведения')),
            ],
          ),
          const SizedBox(height: 6),
          _field(_objectCtrl, 'Объект'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _field(_customerCtrl, 'Заказчик')),
              const SizedBox(width: 8),
              Expanded(child: _field(_executorCtrl, 'Исполнитель')),
            ],
          ),
          const SizedBox(height: 6),
          // Поле «Приборы» с кнопками выбора из реестра
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _devicesCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Приборы',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF0f172a),
                    suffixIcon: _loadingInstruments
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppColors.darkPrimary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Кнопка выбора из реестра (П.4.6/4.7)
              Tooltip(
                message: 'Выбрать из реестра приборов',
                child: IconButton(
                  icon: Icon(Icons.build_circle_outlined,
                      color: AppColors.darkPrimary),
                  onPressed: _pickInstrumentsFromRegistry,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF0f172a),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: AppColors.darkPrimary),
        ),
      ),
    );
  }

  // ============================================================
  //  ВИК TAB
  // ============================================================
  Widget _buildVikTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Заголовок раздела ----
        _sectionLabel('ВИК — Визуально-измерительный контроль'),
        const SizedBox(height: 8),

        // ---- Фото/схема ----
        _subLabel('Фото / схема объекта'),
        const SizedBox(height: 6),
        _buildPhotoGrid(_vikPhotos, onDelete: (i) {
          _confirmDelete(() => setState(() => _vikPhotos.removeAt(i)));
        }),
        OutlinedButton.icon(
          onPressed: () async {
            final src = await _askPhotoSource();
            if (src != null) await _pickPhoto(_vikPhotos, src);
          },
          icon: const Icon(Icons.add_a_photo, size: 16),
          label: const Text('Добавить фото / схему'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.darkPrimary,
            side: BorderSide(color: AppColors.darkPrimary),
          ),
        ),
        const SizedBox(height: 16),

        // ---- Таблица дефектов ----
        _subLabel('Результаты контроля (обнаруженные дефекты)'),
        const SizedBox(height: 6),
        _buildVikDefectsTable(),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () => _addVikDefect(),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Добавить дефект'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.darkPrimary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildVikDefectsTable() {
    if (_vikDefects.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1e293b),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text('Дефекты не обнаружены',
            style: TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(const Color(0xFF0f172a)),
          dataRowColor:
              WidgetStateProperty.all(const Color(0xFF1e293b)),
          columnSpacing: 10,
          headingTextStyle: const TextStyle(
              color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
          dataTextStyle:
              const TextStyle(color: Colors.white, fontSize: 11),
          columns: const [
            DataColumn(label: Text('Тип дефекта')),
            DataColumn(label: Text('Место / узел')),
            DataColumn(label: Text('Размер, мм')),
            DataColumn(label: Text('Описание')),
            DataColumn(label: Text('')),
          ],
          rows: _vikDefects.asMap().entries.map((e) {
            final idx = e.key;
            final d = e.value;
            return DataRow(cells: [
              DataCell(Text(d.type ?? '')),
              DataCell(Text(d.location)),
              DataCell(Text(d.size)),
              DataCell(SizedBox(
                  width: 120,
                  child: Text(d.description,
                      overflow: TextOverflow.ellipsis))),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: const Icon(Icons.edit,
                        color: Colors.white54, size: 15),
                    onPressed: () =>
                        _addVikDefect(existing: d, editIndex: idx),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: const Icon(Icons.delete,
                        color: Colors.redAccent, size: 15),
                    onPressed: () => _confirmDelete(
                        () => setState(() => _vikDefects.removeAt(idx))),
                  ),
                ],
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ============================================================
  //  УЗТ TAB — связка точка на схеме = точка в таблице
  // ============================================================
  Widget _buildUztTab() {
    final hasScheme = _uztSchemeFile != null && _uztSchemeFile!.existsSync();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionLabel('УЗТ — Ультразвуковая толщинометрия'),
        const SizedBox(height: 8),

        // ---- Фото/схема + тап → карта замеров ----
        _subLabel('Фото / схема объекта'),
        const SizedBox(height: 6),
        if (hasScheme)
          _buildSchemePreview(),
        const SizedBox(height: 6),
        // Доп. фото
        _buildPhotoGrid(_uztPhotos, onDelete: (i) {
          _confirmDelete(() => setState(() => _uztPhotos.removeAt(i)));
        }),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final src = await _askPhotoSource();
                if (src != null) await _pickPhoto(_uztPhotos, src);
              },
              icon: const Icon(Icons.add_a_photo, size: 14),
              label: const Text('Доп. фото'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white60,
                side: const BorderSide(color: Colors.white24),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _openThicknessMap,
              icon: const Icon(Icons.touch_app, size: 16),
              label: Text(
                _uztMeasurements.isEmpty
                    ? 'Открыть карту замеров'
                    : 'Карта замеров (${_uztMeasurements.length} точек)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkPrimary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),
        // Подсказка про тап на схему
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.darkPrimary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.darkPrimary.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.white54),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'В карте замеров: тап на схему = автоматически создаётся точка в таблице',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ---- Таблица замеров (согласно образцу на фото) ----
        _subLabel('Результаты замеров УЗТ'),
        const SizedBox(height: 6),
        _buildUztResultsTable(),
      ],
    );
  }

  Widget _buildSchemePreview() {
    return GestureDetector(
      onTap: _openThicknessMap,
      child: Stack(
        children: [
          Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.darkPrimary.withOpacity(0.6)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(_uztSchemeFile!, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, color: Colors.white70, size: 14),
                  SizedBox(width: 4),
                  Text('Тап → карта замеров',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Таблица замеров УЗТ — соответствует образцу на фото протокола
  Widget _buildUztResultsTable() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(const Color(0xFF0f172a)),
          dataRowColor:
              WidgetStateProperty.all(const Color(0xFF1e293b)),
          columnSpacing: 8,
          headingTextStyle: const TextStyle(
              color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
          dataTextStyle:
              const TextStyle(color: Colors.white, fontSize: 12),
          columns: const [
            DataColumn(label: Text('№\nточки')),
            DataColumn(label: Text('Наименование\nэлемента')),
            DataColumn(label: Text('Номинальная\nтолщина')),
            DataColumn(label: Text('Фактич.\nтолщина')),
            DataColumn(label: Text('Отбраковочная\nтолщина')),
            DataColumn(label: Text('')),
          ],
          rows: _uztMeasurements.asMap().entries.map((e) {
            final idx = e.key;
            final m = e.value;
            return DataRow(cells: [
              DataCell(Text(m.sectionNumber)),
              DataCell(SizedBox(
                width: 100,
                child: Text(m.location, overflow: TextOverflow.ellipsis),
              )),
              DataCell(Text(m.nominalThickness?.toStringAsFixed(1) ?? '')),
              DataCell(Text(m.thickness?.toStringAsFixed(1) ?? '')),
              DataCell(Text(m.minAllowedThickness?.toStringAsFixed(1) ?? '')),
              DataCell(
                idx >= 3
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 28, minHeight: 28),
                        icon: const Icon(Icons.delete,
                            color: Colors.redAccent, size: 15),
                        onPressed: () => _confirmDelete(
                            () => setState(() => _uztMeasurements.removeAt(idx))),
                      )
                    : const SizedBox.shrink(),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ============================================================
  //  Сетка фотографий
  // ============================================================

  Widget _buildPhotoGrid(List<File> photos,
      {required void Function(int) onDelete}) {
    if (photos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: photos.asMap().entries.map((e) {
          final idx = e.key;
          final f = e.value;
          return Stack(
            children: [
              GestureDetector(
                onTap: () => _showFullImage(f),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(f, width: 80, height: 80, fit: BoxFit.cover),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => onDelete(idx),
                  child: Container(
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child:
                        const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _showFullImage(File f) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              child: Center(child: Image.file(f, fit: BoxFit.contain)),
            ),
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 8,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  //  Вспомогательные виджеты
  // ============================================================

  Widget _sectionLabel(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.darkPrimary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.darkPrimary.withOpacity(0.4)),
        ),
        child: Text(
          text,
          style: TextStyle(
              color: AppColors.darkPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14),
        ),
      );

  Widget _subLabel(String text) => Text(
        text,
        style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 13),
      );

  // ============================================================
  //  Сохранение черновика
  // ============================================================

  Map<String, dynamic> _toDraftData() => {
        'date': _dateCtrl.text,
        'location': _locationCtrl.text,
        'object_name': _objectCtrl.text,
        'customer': _customerCtrl.text,
        'executor': _executorCtrl.text,
        'devices': _devicesCtrl.text,
        'vik_defects': _vikDefects.map((d) => {
              'type': d.type,
              'location': d.location,
              'size': d.size,
              'description': d.description,
            }).toList(),
        'uzt_measurements':
            _uztMeasurements.map((m) => m.toJson()).toList(),
        'uzt_photos': _uztPhotos.map((f) => f.path).toList(),
        'vik_photos': _vikPhotos.map((f) => f.path).toList(),
        'uzt_scheme': _uztSchemeFile?.path,
      };

  Future<void> _submitStandaloneToServer() async {
    final title = _objectCtrl.text.trim().isNotEmpty
        ? _objectCtrl.text.trim()
        : 'Быстрый контроль ВИК/УЗТ';
    await _apiService.submitStandaloneProtocol(
      title: title,
      kind: 'quick_control',
      payload: _toDraftData(),
    );
  }

  Future<void> _saveDraft({bool showMessage = true}) async {
    try {
      await _autoSaveService.saveGenericDraft(
        id: _draftId,
        screenType: AutoSaveService.screenTypeQuickControl,
        data: _toDraftData(),
        meta: {
          'objectName': _objectCtrl.text.trim().isNotEmpty
              ? _objectCtrl.text.trim()
              : 'Быстрый контроль',
          'controlType': 'НК - быстрый контроль (ВИК/УЗТ)',
        },
      );
      if (showMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Черновик сохранён'),
              backgroundColor: Colors.blueGrey),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    }
  }

  // Ведомость дефектов из быстрого контроля
  void _openDefectStatement() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DefectStatementScreen(
        objectName: _objectCtrl.text,
        date: _dateCtrl.text,
        executor: _executorCtrl.text,
        customer: _customerCtrl.text,
        devices: _devicesCtrl.text,
        normDoc: 'ГОСТ Р 55614-2013, РД 03-606-03',
        controlMethods: const ['ВИК', 'УЗТ'],
        vikDefects: _vikDefects
            .map((d) => {
                  'defect_type': d.type ?? '',
                  'location': d.location,
                  'size': d.size,
                  'description': d.description,
                })
            .toList(),
        uztMeasurements: _uztMeasurements,
      ),
    ));
  }

  // ============================================================
  //  Кнопки сохранения
  // ============================================================

  Widget _buildBottomButtons() {
    final hasVikDefects = _vikDefects.isNotEmpty;
    return Container(
      color: const Color(0xFF1e293b),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Кнопка ведомости (если есть дефекты)
          if (hasVikDefects) ...[
            OutlinedButton.icon(
              onPressed: _openDefectStatement,
              icon: const Icon(Icons.assignment_outlined, size: 14),
              label: const Text('Ведомость дефектов'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                minimumSize: const Size.fromHeight(38),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _saveDraft(),
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Сохранить (черновик)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white30),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _saveDraft(showMessage: false);
                    var ok = false;
                    var queuedOffline = false;
                    final title = _objectCtrl.text.trim().isNotEmpty
                        ? _objectCtrl.text.trim()
                        : 'Быстрый контроль ВИК/УЗТ';
                    try {
                      final online = await _apiService.checkConnection();
                      if (!online) {
                        await _syncService.saveStandaloneProtocolOffline(
                          title: title,
                          kind: 'quick_control',
                          payload: _toDraftData(),
                        );
                        ok = true;
                        queuedOffline = true;
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Нет сети: протокол в очереди. Отправьте на экране «Синхронизация».',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      } else {
                        await _submitStandaloneToServer();
                        ok = true;
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Сервер: $e'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    }
                    if (!mounted) return;
                    if (ok && !queuedOffline) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Протокол на сервере. Веб → Генерация отчётов → мобильные протоколы.',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Подписать / Завершить'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkPrimary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  Диалог выбора приборов из реестра (П.4.6/4.7)
// ============================================================

class _InstrumentPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> instruments;
  const _InstrumentPickerDialog({required this.instruments});

  @override
  State<_InstrumentPickerDialog> createState() =>
      _InstrumentPickerDialogState();
}

class _InstrumentPickerDialogState extends State<_InstrumentPickerDialog> {
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Выбрать приборы из реестра'),
      content: SizedBox(
        width: 340,
        height: 360,
        child: ListView.builder(
          itemCount: widget.instruments.length,
          itemBuilder: (ctx, idx) {
            final inst = widget.instruments[idx];
            final name = (inst['name'] as String?) ?? 'Прибор';
            final type = (inst['type'] as String?) ?? '';
            final spec = (inst['specialist_name'] as String?) ?? '';
            final verUntil = (inst['verification_until'] as String?) ?? '';
            return CheckboxListTile(
              dense: true,
              value: _selected.contains(idx),
              onChanged: (v) =>
                  setState(() => v! ? _selected.add(idx) : _selected.remove(idx)),
              title: Text('$name${type.isNotEmpty ? ' ($type)' : ''}',
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                [
                  if (spec.isNotEmpty) 'У: $spec',
                  if (verUntil.isNotEmpty) 'Поверка: $verUntil',
                ].join(' · '),
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _selected
                        .map((i) => widget.instruments[i])
                        .toList(),
                  ),
          child: Text('Выбрать (${_selected.length})'),
        ),
      ],
    );
  }
}
