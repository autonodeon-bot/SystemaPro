import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path_pkg;
import '../services/auto_save_service.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/image_resize_service.dart';
import '../models/vessel_checklist.dart';
import '../theme/app_colors.dart';
import 'defect_statement_screen.dart';

// ─── Доступные методы НК ───────────────────────────────────────────────────

class _NdtMethod {
  final String code;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final bool available; // false = запланировано, база данных будет добавлена позже

  const _NdtMethod({
    required this.code,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    this.available = true,
  });
}

const _ndtMethods = [
  _NdtMethod(
    code: 'VIK',
    label: 'ВИК',
    description: 'Визуально-измерительный контроль',
    icon: Icons.visibility_outlined,
    color: Colors.blueAccent,
  ),
  _NdtMethod(
    code: 'UZT',
    label: 'УЗТ',
    description: 'Ультразвуковая толщинометрия',
    icon: Icons.waves,
    color: Colors.greenAccent,
  ),
  _NdtMethod(
    code: 'UZK',
    label: 'УЗК',
    description: 'Ультразвуковой контроль',
    icon: Icons.graphic_eq,
    color: Colors.purpleAccent,
    available: false,
  ),
  _NdtMethod(
    code: 'PVK',
    label: 'ПВК/МПД',
    description: 'Проникающие вещества / магнитопорошковый',
    icon: Icons.blur_circular,
    color: Colors.orangeAccent,
    available: false,
  ),
];

// ─── Дефект ВИК ────────────────────────────────────────────────────────────

class _VikDefect {
  String? defectType;
  String location = '';
  String size = '';
  String description = '';
}

// ─── Экран ─────────────────────────────────────────────────────────────────

/// Новый протокол НК (П.1.1.2).
/// Шаг 1 — выбор методов контроля.
/// Шаг 2 — динамическая форма под выбранные методы.
/// Сохраняет черновик через AutoSaveService.
class NewNdkProtocolScreen extends StatefulWidget {
  /// При возобновлении черновика — передаём сохранённые данные
  final Map<String, dynamic>? savedDraft;
  /// Подпись из мастера «Новый протокол» (тип объекта · направление).
  final String? wizardSubtitle;
  /// Предвыбор методов НК (VIK, UZT, UZK, PVK) — из меню экспресс-диагностики.
  final List<String>? preselectedMethodCodes;

  const NewNdkProtocolScreen({
    super.key,
    this.savedDraft,
    this.wizardSubtitle,
    this.preselectedMethodCodes,
  });

  @override
  State<NewNdkProtocolScreen> createState() => _NewNdkProtocolScreenState();
}

class _NewNdkProtocolScreenState extends State<NewNdkProtocolScreen> {
  final _apiService = ApiService();
  final _syncService = SyncService();
  final _autoSaveService = AutoSaveService();
  final _imagePicker = ImagePicker();

  // Шаг: 0 = выбор методов, 1 = заполнение протокола
  int _step = 0;

  // Выбранные методы
  final Set<String> _selectedMethods = {};

  // Уникальный id черновика
  late String _draftId;

  // ── Общие поля ──
  final _dateCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _objectCtrl = TextEditingController();
  final _customerCtrl = TextEditingController();
  final _executorCtrl = TextEditingController();
  final _devicesCtrl = TextEditingController();
  final _normDocCtrl = TextEditingController(); // нормативный документ

  // ── ВИК ──
  final List<File> _vikPhotos = [];
  final List<_VikDefect> _vikDefects = [];

  // ── УЗТ ──
  File? _uztSchemeFile;
  List<ThicknessMeasurement> _uztMeasurements = [
    ThicknessMeasurement(location: '', sectionNumber: '1'),
    ThicknessMeasurement(location: '', sectionNumber: '2'),
    ThicknessMeasurement(location: '', sectionNumber: '3'),
  ];
  final List<File> _uztPhotos = [];

  bool _loadingInstruments = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _draftId = 'ndk_${DateTime.now().millisecondsSinceEpoch}';
    _dateCtrl.text = intl.DateFormat('dd.MM.yyyy').format(DateTime.now());

    // Если возобновляем черновик
    if (widget.savedDraft != null) {
      _restoreFromDraft(widget.savedDraft!);
    } else {
      final pre = widget.preselectedMethodCodes;
      if (pre != null && pre.isNotEmpty) {
        _selectedMethods.addAll(pre.map((c) => c.toUpperCase()));
        _step = 1;
      }
      _loadMyInstruments();
    }
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _locationCtrl.dispose();
    _objectCtrl.dispose();
    _customerCtrl.dispose();
    _executorCtrl.dispose();
    _devicesCtrl.dispose();
    _normDocCtrl.dispose();
    super.dispose();
  }

  void _restoreFromDraft(Map<String, dynamic> draft) {
    final id = draft['id'] as String?;
    if (id != null) _draftId = id;

    final data = draft['checklist_data'] as Map<String, dynamic>? ?? {};

    // Методы
    final methods = data['selected_methods'] as List? ?? [];
    _selectedMethods.addAll(methods.map((m) => m.toString()));
    if (_selectedMethods.isNotEmpty) _step = 1;

    // Общие поля
    _dateCtrl.text = (data['date'] as String?) ?? _dateCtrl.text;
    _locationCtrl.text = (data['location'] as String?) ?? '';
    _objectCtrl.text = (data['object_name'] as String?) ?? '';
    _customerCtrl.text = (data['customer'] as String?) ?? '';
    _executorCtrl.text = (data['executor'] as String?) ?? '';
    _devicesCtrl.text = (data['devices'] as String?) ?? '';
    _normDocCtrl.text = (data['norm_doc'] as String?) ?? '';

    // ВИК дефекты
    final vikRaw = data['vik_defects'] as List? ?? [];
    for (final d in vikRaw) {
      if (d is Map) {
        final def = _VikDefect()
          ..defectType = d['defect_type']?.toString()
          ..location = d['location']?.toString() ?? ''
          ..size = d['size']?.toString() ?? ''
          ..description = d['description']?.toString() ?? '';
        _vikDefects.add(def);
      }
    }

    // УЗТ замеры
    final uztRaw = data['uzt_measurements'] as List? ?? [];
    if (uztRaw.isNotEmpty) {
      _uztMeasurements = uztRaw
          .whereType<Map>()
          .map((m) => ThicknessMeasurement.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    _loadMyInstruments();
  }

  Map<String, dynamic> _toDraftData() => {
        'selected_methods': _selectedMethods.toList(),
        'date': _dateCtrl.text,
        'location': _locationCtrl.text,
        'object_name': _objectCtrl.text,
        'customer': _customerCtrl.text,
        'executor': _executorCtrl.text,
        'devices': _devicesCtrl.text,
        'norm_doc': _normDocCtrl.text,
        'vik_defects': _vikDefects.map((d) => {
              'defect_type': d.defectType,
              'location': d.location,
              'size': d.size,
              'description': d.description,
            }).toList(),
        'uzt_measurements': _uztMeasurements.map((m) => m.toJson()).toList(),
        'uzt_photos': _uztPhotos.map((f) => f.path).toList(),
        'vik_photos': _vikPhotos.map((f) => f.path).toList(),
      };

  Future<void> _submitStandaloneToServer() async {
    final title = _objectCtrl.text.trim().isNotEmpty
        ? _objectCtrl.text.trim()
        : 'Протокол НК';
    await _apiService.submitStandaloneProtocol(
      title: title,
      kind: 'ndk_protocol',
      payload: _toDraftData(),
    );
  }

  // ── Автозаполнение приборов ────────────────────────────────────────────────

  Future<void> _loadMyInstruments() async {
    setState(() => _loadingInstruments = true);
    try {
      final data = await _apiService.getMyInstruments();
      if (mounted && data.isNotEmpty && _devicesCtrl.text.trim().isEmpty) {
        final names = data
            .map((i) => (i['name'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .join(', ');
        setState(() => _devicesCtrl.text = names);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingInstruments = false);
    }
  }

  // ── Фото ──────────────────────────────────────────────────────────────────

  Future<void> _pickPhoto(List<File> target) async {
    final src = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить фото'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, ImageSource.camera),
              child: const Text('Камера')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
              child: const Text('Галерея')),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        ],
      ),
    );
    if (src == null) return;
    try {
      final picked = await _imagePicker.pickImage(source: src, imageQuality: 85);
      if (picked == null) return;
      final resized = await ImageResizeService.resizeIfNeeded(picked.path);
      final dir = await getApplicationDocumentsDirectory();
      final destDir = Directory(path_pkg.join(dir.path, 'ndk_protocols'));
      if (!await destDir.exists()) await destDir.create(recursive: true);
      final dest = path_pkg.join(destDir.path,
          'photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(resized).copy(dest);
      setState(() => target.add(File(dest)));
    } catch (e) {
      _showError('Ошибка загрузки фото: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmDelete(VoidCallback onConfirm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтверждение'),
        content: const Text('Удалить?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Нет')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Да')),
        ],
      ),
    );
    if (ok == true) onConfirm();
  }

  // ── Сохранение черновика ──────────────────────────────────────────────────

  Future<void> _saveDraft({bool showMessage = true}) async {
    setState(() => _isSaving = true);
    try {
      await _autoSaveService.saveGenericDraft(
        id: _draftId,
        screenType: AutoSaveService.screenTypeNdkProtocol,
        data: _toDraftData(),
        meta: {
          'objectName': _objectCtrl.text.trim().isNotEmpty
              ? _objectCtrl.text.trim()
              : 'Протокол НК',
          'controlType': 'НК - протокол (${_selectedMethods.join(', ')})',
          'category': _selectedMethods.join(', '),
        },
      );
      if (showMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Черновик сохранён'),
            backgroundColor: Colors.blueGrey,
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError('Ошибка сохранения: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Открыть карту замеров УЗТ ─────────────────────────────────────────────

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

  // ── Открыть ведомость дефектов ────────────────────────────────────────────

  void _openDefectStatement() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DefectStatementScreen(
        objectName: _objectCtrl.text,
        date: _dateCtrl.text,
        executor: _executorCtrl.text,
        customer: _customerCtrl.text,
        devices: _devicesCtrl.text,
        normDoc: _normDocCtrl.text,
        controlMethods: _selectedMethods.toList(),
        vikDefects: _vikDefects
            .map((d) => {
                  'defect_type': d.defectType ?? '',
                  'location': d.location,
                  'size': d.size,
                  'description': d.description,
                })
            .toList(),
        uztMeasurements: _uztMeasurements,
      ),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _saveDraft(showMessage: false);
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0f172a),
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_step == 0
                  ? 'Новый протокол НК'
                  : 'Протокол НК — ${_selectedMethods.join(', ')}'),
              if (widget.wizardSubtitle != null &&
                  widget.wizardSubtitle!.trim().isNotEmpty)
                Text(
                  widget.wizardSubtitle!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: Colors.white70,
                  ),
                ),
            ],
          ),
          backgroundColor: const Color(0xFF1e293b),
          foregroundColor: Colors.white,
          actions: [
            if (_step == 1) ...[
              IconButton(
                icon: const Icon(Icons.assignment_outlined),
                tooltip: 'Ведомость дефектов',
                onPressed: _openDefectStatement,
              ),
              IconButton(
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                tooltip: 'Сохранить черновик',
                onPressed: () => _saveDraft(),
              ),
            ],
          ],
        ),
        body: _step == 0 ? _buildMethodSelection() : _buildProtocolForm(),
        bottomNavigationBar: _step == 1
            ? SafeArea(
                top: false,
                maintainBottomViewPadding: true,
                child: _buildBottomBar(),
              )
            : null,
      ),
    );
  }

  // ─── Шаг 0: Выбор методов НК ─────────────────────────────────────────────

  Widget _buildMethodSelection() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Выберите методы контроля',
          style: TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Таблица результатов автоматически расширится под выбранные методы.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 24),
        ..._ndtMethods.map((m) => _buildMethodCard(m)),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: _selectedMethods.where((c) {
                final m = _ndtMethods.firstWhere((n) => n.code == c,
                    orElse: () => _ndtMethods.first);
                return m.available;
              }).isEmpty
              ? null
              : () => setState(() => _step = 1),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Продолжить'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.darkPrimary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Widget _buildMethodCard(_NdtMethod m) {
    final selected = _selectedMethods.contains(m.code);
    return GestureDetector(
      onTap: m.available
          ? () {
              setState(() {
                if (selected) {
                  _selectedMethods.remove(m.code);
                } else {
                  _selectedMethods.add(m.code);
                }
              });
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? m.color.withOpacity(0.12)
              : const Color(0xFF1e293b),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? m.color : Colors.white.withOpacity(0.1),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: m.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(m.icon, color: m.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(m.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      if (!m.available) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Скоро',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(m.description,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            if (m.available)
              Checkbox(
                value: selected,
                onChanged: (_) {
                  setState(() {
                    if (selected) {
                      _selectedMethods.remove(m.code);
                    } else {
                      _selectedMethods.add(m.code);
                    }
                  });
                },
                activeColor: m.color,
                side: BorderSide(color: m.color.withOpacity(0.5)),
              )
            else
              const Icon(Icons.lock_outline, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }

  // ─── Шаг 1: Форма протокола ───────────────────────────────────────────────

  Widget _buildProtocolForm() {
    final hasVik = _selectedMethods.contains('VIK');
    final hasUzt = _selectedMethods.contains('UZT');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Шапка: выбранные методы ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1e293b),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Wrap(
            spacing: 8,
            children: [
              ..._selectedMethods.map((code) {
                final m = _ndtMethods.firstWhere((n) => n.code == code,
                    orElse: () => _ndtMethods.first);
                return Chip(
                  label: Text(m.label,
                      style: TextStyle(color: m.color, fontSize: 12)),
                  backgroundColor: m.color.withOpacity(0.1),
                  side: BorderSide(color: m.color.withOpacity(0.4)),
                  deleteIcon: Icon(Icons.close, size: 14, color: m.color),
                  onDeleted: () => setState(() {
                    _selectedMethods.remove(code);
                    if (_selectedMethods.isEmpty) _step = 0;
                  }),
                );
              }),
              ActionChip(
                label: const Text('+ метод',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                backgroundColor: Colors.white10,
                side: const BorderSide(color: Colors.white24),
                onPressed: () => setState(() => _step = 0),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Общие поля ──
        _sectionHeader('Общие данные'),
        _tf(_dateCtrl, 'Дата'),
        _tf(_locationCtrl, 'Место проведения'),
        _tf(_objectCtrl, 'Объект контроля *'),
        _tf(_customerCtrl, 'Заказчик'),
        _tf(_executorCtrl, 'Исполнитель'),
        _tf(_normDocCtrl, 'Нормативный документ (ГОСТ, РД...)'),
        // Приборы
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _devicesCtrl,
                maxLines: 2,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _inputDecor('Приборы').copyWith(
                  suffixIcon: _loadingInstruments
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Выбрать из реестра приборов',
              child: IconButton(
                icon: Icon(Icons.build_circle_outlined,
                    color: AppColors.darkPrimary),
                onPressed: _pickInstruments,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── ВИК ──
        if (hasVik) ...[
          _sectionHeader('ВИК — Визуально-измерительный контроль'),
          _subLabel('Фото / схема объекта'),
          _photoGrid(_vikPhotos,
              onDelete: (i) =>
                  _confirmDelete(() => setState(() => _vikPhotos.removeAt(i)))),
          _addPhotoBtn(() => _pickPhoto(_vikPhotos)),
          const SizedBox(height: 12),
          _subLabel('Результаты контроля (обнаруженные дефекты)'),
          _vikDefectsTable(),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _addVikDefect,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Добавить дефект'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blueAccent,
              side: const BorderSide(color: Colors.blueAccent),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── УЗТ ──
        if (hasUzt) ...[
          _sectionHeader('УЗТ — Ультразвуковая толщинометрия'),
          // Схема
          if (_uztSchemeFile != null && _uztSchemeFile!.existsSync()) ...[
            GestureDetector(
              onTap: _openThicknessMap,
              child: Stack(
                children: [
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.greenAccent.withOpacity(0.5)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_uztSchemeFile!, fit: BoxFit.cover,
                          width: double.infinity),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app,
                              color: Colors.white70, size: 14),
                          SizedBox(width: 4),
                          Text('Карта замеров',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          _photoGrid(_uztPhotos,
              onDelete: (i) => _confirmDelete(
                  () => setState(() => _uztPhotos.removeAt(i)))),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickPhoto(_uztPhotos),
                icon: const Icon(Icons.add_a_photo, size: 14),
                label: const Text('Фото'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white60,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _openThicknessMap,
                icon: const Icon(Icons.touch_app, size: 16),
                label: Text(
                  'Карта замеров (${_uztMeasurements.length} точек)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.withOpacity(0.2),
                  foregroundColor: Colors.greenAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _subLabel('Результаты замеров'),
          _uztTable(),
          const SizedBox(height: 16),
        ],

        // ── Заключение ──
        _sectionHeader('Заключение'),
        _tf(TextEditingController(), 'Вывод по результатам контроля',
            maxLines: 3),
        const SizedBox(height: 24),

        // ── Кнопка ведомости дефектов ──
        if (hasVik && _vikDefects.isNotEmpty) ...[
          ElevatedButton.icon(
            onPressed: _openDefectStatement,
            icon: const Icon(Icons.assignment_outlined, size: 16),
            label: const Text('Сформировать ведомость дефектов'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.withOpacity(0.2),
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange),
              minimumSize: const Size.fromHeight(44),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // ── Таблица ВИК ──────────────────────────────────────────────────────────

  Widget _vikDefectsTable() {
    if (_vikDefects.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1e293b),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text('Дефекты не обнаружены',
            style: TextStyle(color: Colors.white38),
            textAlign: TextAlign.center),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFF0f172a)),
        dataRowColor: WidgetStateProperty.all(const Color(0xFF1e293b)),
        columnSpacing: 10,
        headingTextStyle: const TextStyle(
            color: Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w600),
        dataTextStyle: const TextStyle(color: Colors.white, fontSize: 11),
        columns: const [
          DataColumn(label: Text('Вид дефекта')),
          DataColumn(label: Text('Место/узел')),
          DataColumn(label: Text('Размер')),
          DataColumn(label: Text('Описание')),
          DataColumn(label: Text('')),
        ],
        rows: _vikDefects.asMap().entries.map((e) {
          final idx = e.key;
          final d = e.value;
          return DataRow(cells: [
            DataCell(Text(d.defectType ?? '')),
            DataCell(Text(d.location)),
            DataCell(Text(d.size)),
            DataCell(SizedBox(
                width: 100,
                child: Text(d.description,
                    overflow: TextOverflow.ellipsis))),
            DataCell(IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.delete, color: Colors.redAccent, size: 15),
              onPressed: () => _confirmDelete(
                  () => setState(() => _vikDefects.removeAt(idx))),
            )),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _uztTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFF0f172a)),
        dataRowColor: WidgetStateProperty.all(const Color(0xFF1e293b)),
        columnSpacing: 8,
        headingTextStyle: const TextStyle(
            color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600),
        dataTextStyle: const TextStyle(color: Colors.white, fontSize: 12),
        columns: const [
          DataColumn(label: Text('№')),
          DataColumn(label: Text('Элемент')),
          DataColumn(label: Text('Ном., мм')),
          DataColumn(label: Text('Факт., мм')),
          DataColumn(label: Text('Отбр., мм')),
        ],
        rows: _uztMeasurements.asMap().entries.map((e) {
          final m = e.value;
          return DataRow(cells: [
            DataCell(Text(m.sectionNumber)),
            DataCell(SizedBox(
                width: 90,
                child: Text(m.location, overflow: TextOverflow.ellipsis))),
            DataCell(Text(m.nominalThickness?.toStringAsFixed(1) ?? '')),
            DataCell(Text(m.thickness?.toStringAsFixed(1) ?? '')),
            DataCell(Text(m.minAllowedThickness?.toStringAsFixed(1) ?? '')),
          ]);
        }).toList(),
      ),
    );
  }

  // ── Добавить дефект ВИК ──────────────────────────────────────────────────

  Future<void> _addVikDefect() async {
    final def = _VikDefect();
    final types = ['Коррозия', 'Вмятина', 'Трещина', 'Разрыв',
        'Потеря металла', 'Расслоение', 'Скол', 'Другое'];
    String? selType;
    final locCtrl = TextEditingController();
    final sizeCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Добавить дефект ВИК'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selType,
                  decoration: const InputDecoration(labelText: 'Тип *'),
                  items: types
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => set(() => selType = v),
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: locCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Место / узел')),
                const SizedBox(height: 8),
                TextField(
                    controller: sizeCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Размер (мм)')),
                const SizedBox(height: 8),
                TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Описание')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена')),
            ElevatedButton(
              onPressed: selType == null
                  ? null
                  : () {
                      def
                        ..defectType = selType
                        ..location = locCtrl.text
                        ..size = sizeCtrl.text
                        ..description = descCtrl.text;
                      setState(() => _vikDefects.add(def));
                      Navigator.pop(ctx);
                    },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );

    locCtrl.dispose();
    sizeCtrl.dispose();
    descCtrl.dispose();
  }

  // ── Выбрать приборы из реестра ───────────────────────────────────────────

  Future<void> _pickInstruments() async {
    try {
      final data = await _apiService.getInstruments();
      if (!mounted) return;
      final instruments = List<Map<String, dynamic>>.from(data);
      if (instruments.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Реестр пуст')));
        return;
      }
      final sel = <int>{};
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
            title: const Text('Выбрать приборы'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: ListView.builder(
                itemCount: instruments.length,
                itemBuilder: (_, i) => CheckboxListTile(
                  dense: true,
                  value: sel.contains(i),
                  onChanged: (v) =>
                      set(() => v! ? sel.add(i) : sel.remove(i)),
                  title: Text(instruments[i]['name'] ?? '',
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена')),
              ElevatedButton(
                onPressed: sel.isEmpty
                    ? null
                    : () {
                        final names = sel
                            .map((i) => instruments[i]['name'] ?? '')
                            .join(', ');
                        final cur = _devicesCtrl.text.trim();
                        setState(() => _devicesCtrl.text =
                            cur.isEmpty ? names : '$cur, $names');
                        Navigator.pop(ctx);
                      },
                child: Text('Выбрать (${sel.length})'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      _showError('Ошибка: $e');
    }
  }

  // ── Вспомогательные виджеты ──────────────────────────────────────────────

  Widget _sectionHeader(String label) => Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.darkPrimary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.darkPrimary.withOpacity(0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                color: AppColors.darkPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      );

  Widget _subLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      );

  Widget _tf(TextEditingController ctrl, String label, {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: _inputDecor(label),
        ),
      );

  InputDecoration _inputDecor(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF1e293b),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.darkPrimary)),
      );

  Widget _photoGrid(List<File> photos,
      {required void Function(int) onDelete}) {
    if (photos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: photos.asMap().entries.map((e) {
          final idx = e.key;
          return Stack(children: [
            GestureDetector(
              onTap: () => _showFullImage(e.value),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(e.value,
                    width: 80, height: 80, fit: BoxFit.cover),
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
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _addPhotoBtn(VoidCallback onTap) => OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_a_photo, size: 14),
        label: const Text('Добавить фото / схему'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkPrimary,
          side: BorderSide(color: AppColors.darkPrimary),
        ),
      );

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
                child: Center(child: Image.file(f, fit: BoxFit.contain))),
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

  // ── Нижняя панель ─────────────────────────────────────────────────────────

  Widget _buildBottomBar() => Container(
        color: const Color(0xFF1e293b),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : () => _saveDraft(),
                icon: const Icon(Icons.save_outlined, size: 15),
                label: const Text('Сохранить (черновик)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white30),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  await _saveDraft(showMessage: false);
                  var ok = false;
                  var queuedOffline = false;
                  final title = _objectCtrl.text.trim().isNotEmpty
                      ? _objectCtrl.text.trim()
                      : 'Протокол НК';
                  try {
                    final online = await _apiService.checkConnection();
                    if (!online) {
                      await _syncService.saveStandaloneProtocolOffline(
                        title: title,
                        kind: 'ndk_protocol',
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
                    if (mounted) _showError('Сервер: $e');
                  }
                  if (ok) {
                    // Протокол завершён (на сервере или в очереди) —
                    // удаляем черновик, чтобы в реестре не висел «не завершён»
                    await _autoSaveService.deleteDraft(_draftId);
                  }
                  if (!mounted) return;
                  if (ok && !queuedOffline) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Протокол на сервере. Веб → Генерация отчётов → блок мобильных протоколов.',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.check_circle_outline, size: 15),
                label: const Text('Подписать / Завершить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkPrimary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
}
