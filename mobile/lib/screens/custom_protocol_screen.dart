import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path_pkg;
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/auto_save_service.dart';
import '../services/image_resize_service.dart';
import '../theme/app_colors.dart';

/// Экран заполнения произвольного шаблона протокола/акта.
/// Динамически рендерит блоки из [template]['structure'].
/// П.1.1.4 — «Свой протокол/акт»
class CustomProtocolScreen extends StatefulWidget {
  final Map<String, dynamic> template;
  /// Задание, в рамках которого заполняется шаблон (в payload для учёта).
  final String? assignmentId;
  /// `custom_template` | `quick_control` — тип standalone на сервере.
  final String protocolKind;
  /// Код быстрого контроля (qc_vik, …) для аналитики в payload.
  final String? quickControlCode;

  const CustomProtocolScreen({
    super.key,
    required this.template,
    this.assignmentId,
    this.protocolKind = 'custom_template',
    this.quickControlCode,
  });

  @override
  State<CustomProtocolScreen> createState() => _CustomProtocolScreenState();
}

class _CustomProtocolScreenState extends State<CustomProtocolScreen> {
  final _apiService = ApiService();
  final _syncService = SyncService();
  final _autoSaveService = AutoSaveService();
  final _imagePicker = ImagePicker();
  late final String _draftId;

  /// Значения полей: field_key → значение (String | List<String> | List<Map>)
  final Map<String, dynamic> _values = {};

  /// Список инструментов из реестра (для поля instruments_field)
  List<Map<String, dynamic>> _myInstruments = [];

  bool _loadingInstruments = false;
  bool _isSaving = false;

  List<Map<String, dynamic>> get _structure {
    final s = widget.template['structure'];
    if (s is List) return s.whereType<Map<String, dynamic>>().toList();
    return [];
  }

  @override
  void initState() {
    super.initState();
    final templateId = widget.template['id'] as String? ?? 'custom';
    _draftId = 'cp_${templateId}_${DateTime.now().millisecondsSinceEpoch}';
    _initDefaults();
    _loadMyInstruments();
  }

  /// Заполняем дефолтные значения полей
  void _initDefaults() {
    final today = intl.DateFormat('dd.MM.yyyy').format(DateTime.now());
    for (final block in _structure) {
      final key = block['field_key'] as String?;
      final type = block['block_type'] as String?;
      if (key == null || key.isEmpty) continue;
      switch (type) {
        case 'date_field':
          _values[key] = today;
          break;
        case 'table':
          _values[key] = <List<String>>[];
          break;
        case 'photo_section':
          _values[key] = <String>[];
          break;
        case 'checkbox_list':
          final items = block['items'] as List? ?? [];
          _values[key] = Map.fromIterables(
            items.map((i) => i.toString()),
            List.filled(items.length, false),
          );
          break;
        default:
          _values[key] = '';
      }
    }
  }

  /// П.4.5 — загружаем закреплённые приборы
  Future<void> _loadMyInstruments() async {
    setState(() => _loadingInstruments = true);
    try {
      final data = await _apiService.getMyInstruments();
      if (mounted) {
        setState(() {
          _myInstruments = List<Map<String, dynamic>>.from(data);
          // Автозаполнение полей типа instruments_field
          for (final block in _structure) {
            final key = block['field_key'] as String?;
            final type = block['block_type'] as String?;
            if (type == 'instruments_field' && key != null && _myInstruments.isNotEmpty) {
              if ((_values[key] as String? ?? '').isEmpty) {
                _values[key] = _myInstruments
                    .map((i) => '${i['name'] ?? ''}')
                    .where((s) => s.isNotEmpty)
                    .join(', ');
              }
            }
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingInstruments = false);
    }
  }

  // ─── Фото ─────────────────────────────────────────────────────────────────

  Future<void> _pickPhoto(String fieldKey) async {
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
        ],
      ),
    );
    if (src == null) return;
    try {
      final picked = await _imagePicker.pickImage(source: src, imageQuality: 85);
      if (picked == null) return;
      final resized = await ImageResizeService.resizeIfNeeded(picked.path);
      final dir = await getApplicationDocumentsDirectory();
      final dest = path_pkg.join(dir.path, 'custom_protocols',
          '${DateTime.now().millisecondsSinceEpoch}.jpg');
      await Directory(path_pkg.dirname(dest)).create(recursive: true);
      await File(resized).copy(dest);
      final list = List<String>.from(_values[fieldKey] as List? ?? []);
      list.add(dest);
      setState(() => _values[fieldKey] = list);
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
        content: const Text('Вы уверены? Данные будут удалены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Да')),
        ],
      ),
    );
    if (ok == true) onConfirm();
  }

  // ─── Таблица: добавить строку ─────────────────────────────────────────────

  Future<void> _addTableRow(Map<String, dynamic> block) async {
    final columns = (block['columns'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (columns.isEmpty) return;

    final Map<String, TextEditingController> controllers = {
      for (final col in columns)
        (col['key'] as String? ?? ''): TextEditingController(),
    };

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Добавить строку: ${block['label'] ?? ''}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: columns.map((col) {
              final key = (col['key'] as String? ?? '');
              final label = (col['label'] as String? ?? key);
              final colType = (col['col_type'] as String? ?? 'text');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: controllers[key],
                  keyboardType: colType == 'number' ? TextInputType.number : TextInputType.text,
                  decoration: InputDecoration(labelText: label),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              final row = {
                for (final col in columns)
                  (col['key'] as String? ?? ''): controllers[col['key']]?.text ?? '',
              };
              final key = block['field_key'] as String?;
              if (key != null) {
                final list = List<Map<String, dynamic>>.from(
                    _values[key] as List? ?? []);
                list.add(row);
                setState(() => _values[key] = list);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );

    for (final c in controllers.values) {
      c.dispose();
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final templateName = widget.template['name'] as String? ?? 'Протокол';
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: Text(templateName),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          ..._structure.map((block) => _buildBlock(block)),
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        child: _buildBottomButtons(),
      ),
    );
  }

  Widget _buildBlock(Map<String, dynamic> block) {
    final type = block['block_type'] as String? ?? '';
    final label = block['label'] as String? ?? '';
    final key = block['field_key'] as String?;
    final required = block['required'] as bool? ?? false;
    final placeholder = block['placeholder'] as String? ?? label;

    switch (type) {
      case 'section_header':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.darkPrimary.withOpacity(0.15),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(2),
              topRight: Radius.circular(8),
              bottomLeft: Radius.circular(2),
              bottomRight: Radius.circular(8),
            ),
            border: Border.all(color: AppColors.darkPrimary.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 20,
                color: AppColors.darkPrimary,
                margin: const EdgeInsets.only(right: 10),
              ),
              Text(label,
                  style: TextStyle(
                      color: AppColors.darkPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ],
          ),
        );

      case 'text_field':
      case 'instruments_field':
        return _buildTextField(
          key: key,
          label: label,
          required: required,
          placeholder: placeholder,
          suffix: type == 'instruments_field'
              ? IconButton(
                  icon: Icon(Icons.build_circle_outlined,
                      color: AppColors.darkPrimary, size: 20),
                  onPressed: () => _pickInstrumentFromRegistry(key),
                  tooltip: 'Из реестра',
                )
              : null,
        );

      case 'number_field':
        return _buildTextField(
          key: key,
          label: label,
          required: required,
          placeholder: placeholder,
          keyboardType: TextInputType.number,
        );

      case 'date_field':
        return _buildDateField(key: key, label: label, required: required);

      case 'textarea':
        return _buildTextArea(
            key: key, label: label, required: required, placeholder: placeholder);

      case 'table':
        return _buildTable(block: block, key: key, label: label);

      case 'photo_section':
        return _buildPhotoSection(key: key, label: label);

      case 'checkbox_list':
        return _buildCheckboxList(block: block, key: key, label: label);

      case 'signature':
        return _buildSignatureBlock(label: label);

      default:
        return const SizedBox.shrink();
    }
  }

  // ── Виджеты блоков ────────────────────────────────────────────────────────

  Widget _buildTextField({
    required String? key,
    required String label,
    required bool required,
    String? placeholder,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: TextEditingController(text: key != null ? (_values[key] as String? ?? '') : ''),
        keyboardType: keyboardType ?? TextInputType.text,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        onChanged: (v) { if (key != null) _values[key] = v; },
        decoration: _inputDecor(
          label: '$label${required ? ' *' : ''}',
          placeholder: placeholder,
          suffix: suffix,
        ),
      ),
    );
  }

  Widget _buildDateField({required String? key, required String label, required bool required}) {
    final current = key != null ? (_values[key] as String? ?? '') : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: TextEditingController(text: current),
        readOnly: true,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: _inputDecor(
          label: '$label${required ? ' *' : ''}',
          placeholder: 'дд.мм.гггг',
          suffix: Icon(Icons.calendar_today, color: AppColors.darkPrimary, size: 18),
        ),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null && key != null) {
            final formatted = intl.DateFormat('dd.MM.yyyy').format(picked);
            setState(() => _values[key] = formatted);
          }
        },
      ),
    );
  }

  Widget _buildTextArea({
    required String? key,
    required String label,
    required bool required,
    String? placeholder,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: TextEditingController(text: key != null ? (_values[key] as String? ?? '') : ''),
        maxLines: 4,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        onChanged: (v) { if (key != null) _values[key] = v; },
        decoration: _inputDecor(
          label: '$label${required ? ' *' : ''}',
          placeholder: placeholder,
        ),
      ),
    );
  }

  Widget _buildTable({
    required Map<String, dynamic> block,
    required String? key,
    required String label,
  }) {
    final columns = (block['columns'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final rows = key != null
        ? List<Map<String, dynamic>>.from(_values[key] as List? ?? [])
        : <Map<String, dynamic>>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(label),
          const SizedBox(height: 6),
          if (columns.isEmpty)
            const Text('Таблица не настроена',
                style: TextStyle(color: Colors.white38, fontSize: 12))
          else
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1e293b),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0f172a)),
                  columnSpacing: 12,
                  headingTextStyle: const TextStyle(
                      color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                  dataTextStyle:
                      const TextStyle(color: Colors.white, fontSize: 12),
                  columns: [
                    ...columns.map((col) => DataColumn(
                          label: Text(col['label'] as String? ?? ''),
                        )),
                    const DataColumn(label: Text('')),
                  ],
                  rows: rows.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final row = entry.value;
                    return DataRow(
                      cells: [
                        ...columns.map((col) {
                          final ck = col['key'] as String? ?? '';
                          return DataCell(
                            SizedBox(
                              width: 90,
                              child: Text(row[ck]?.toString() ?? '',
                                  overflow: TextOverflow.ellipsis),
                            ),
                          );
                        }),
                        DataCell(IconButton(
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 28, minHeight: 28),
                          icon: const Icon(Icons.delete,
                              color: Colors.redAccent, size: 15),
                          onPressed: () => _confirmDelete(() {
                            final list = List<Map<String, dynamic>>.from(
                                _values[key] as List? ?? []);
                            list.removeAt(idx);
                            setState(() => _values[key!] = list);
                          }),
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => _addTableRow(block),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Добавить строку'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkPrimary,
              side: BorderSide(color: AppColors.darkPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection({required String? key, required String label}) {
    final photos = key != null
        ? List<String>.from(_values[key] as List? ?? [])
        : <String>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(label),
          const SizedBox(height: 6),
          if (photos.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: photos.asMap().entries.map((e) {
                final idx = e.key;
                final p = e.value;
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(File(p),
                          width: 80, height: 80, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => _confirmDelete(() {
                          final list = List<String>.from(
                              _values[key] as List? ?? []);
                          list.removeAt(idx);
                          setState(() => _values[key!] = list);
                        }),
                        child: Container(
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: key != null ? () => _pickPhoto(key) : null,
            icon: const Icon(Icons.add_a_photo, size: 14),
            label: const Text('Добавить фото/схему'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white60,
              side: const BorderSide(color: Colors.white24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxList({
    required Map<String, dynamic> block,
    required String? key,
    required String label,
  }) {
    final items = (block['items'] as List? ?? []).map((i) => i.toString()).toList();
    final checkValues = key != null
        ? (_values[key] as Map<String, dynamic>? ?? {})
        : <String, dynamic>{};

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(label),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1e293b),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              children: items.map((item) {
                final checked = checkValues[item] == true;
                return CheckboxListTile(
                  dense: true,
                  value: checked,
                  onChanged: (v) {
                    if (key == null) return;
                    final newMap = Map<String, dynamic>.from(
                        _values[key] as Map? ?? {});
                    newMap[item] = v ?? false;
                    setState(() => _values[key] = newMap);
                  },
                  title: Text(item,
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                  checkColor: Colors.white,
                  activeColor: AppColors.darkPrimary,
                  side: const BorderSide(color: Colors.white38),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignatureBlock({required String label}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(label),
          const SizedBox(height: 6),
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF1e293b),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            alignment: Alignment.bottomCenter,
            child: const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('___________________________',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ),
          ),
          const SizedBox(height: 4),
          const Text('Подпись / дата',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  // ── Вспомогательные декораторы ────────────────────────────────────────────

  InputDecoration _inputDecor({
    required String label,
    String? placeholder,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
      hintText: placeholder,
      hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFF1e293b),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.darkPrimary),
      ),
    );
  }

  Widget _fieldLabel(String label) => Text(
        label,
        style: const TextStyle(
            color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
      );

  // ── Выбор прибора из реестра (П.4.6/4.7) ─────────────────────────────────

  Future<void> _pickInstrumentFromRegistry(String? key) async {
    if (key == null) return;
    try {
      final data = await _apiService.getInstruments();
      if (!mounted) return;
      final instruments = List<Map<String, dynamic>>.from(data);
      if (instruments.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Реестр приборов пуст')),
        );
        return;
      }
      final sel = <int>{};
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Выбрать приборы'),
            content: SizedBox(
              width: 320,
              height: 320,
              child: ListView.builder(
                itemCount: instruments.length,
                itemBuilder: (_, idx) {
                  final inst = instruments[idx];
                  return CheckboxListTile(
                    dense: true,
                    value: sel.contains(idx),
                    onChanged: (v) =>
                        setLocal(() => v! ? sel.add(idx) : sel.remove(idx)),
                    title: Text(
                      '${inst['name'] ?? ''}${(inst['type'] ?? '').isNotEmpty ? ' (${inst['type']})' : ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                },
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
                            .where((s) => s.toString().isNotEmpty)
                            .join(', ');
                        final cur = _values[key] as String? ?? '';
                        setState(() => _values[key] =
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

  // ── Кнопки сохранения ─────────────────────────────────────────────────────

  Widget _buildBottomButtons() {
    return Container(
      color: const Color(0xFF1e293b),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _saveDraft,
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
              onPressed: _isSaving ? null : _finish,
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Подписать / Завершить'),
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

  Future<void> _saveDraft({bool showMessage = true}) async {
    try {
      final objectName = _values['object'] as String? ??
          _values['object_name'] as String? ??
          (widget.template['name'] as String? ?? 'Протокол');
      await _autoSaveService.saveGenericDraft(
        id: _draftId,
        screenType: AutoSaveService.screenTypeCustomProtocol,
        data: {
          'template_id': widget.template['id'],
          'template_name': widget.template['name'],
          'values': _values,
        },
        meta: {
          'objectName': objectName.isNotEmpty ? objectName : 'Протокол',
          'controlType': widget.template['name'] as String? ?? 'Протокол',
          'category': widget.template['category'] as String? ?? '',
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

  dynamic _toJsonValue(dynamic v) {
    if (v == null) return null;
    if (v is Map) {
      return v.map((k, dynamic val) => MapEntry(k.toString(), _toJsonValue(val)));
    }
    if (v is List) {
      return v.map(_toJsonValue).toList();
    }
    return v;
  }

  Future<void> _finish() async {
    setState(() => _isSaving = true);
    await _saveDraft(showMessage: false);
    var serverOk = false;
    try {
      final title = (_values['object'] as String? ??
              _values['object_name'] as String? ??
              widget.template['name'] as String? ??
              'Протокол')
          .trim();
      final valuesJson = <String, dynamic>{};
      for (final e in _values.entries) {
        valuesJson[e.key] = _toJsonValue(e.value);
      }
      final payload = <String, dynamic>{
        'structure': _structure,
        'values': valuesJson,
        if (widget.assignmentId != null && widget.assignmentId!.trim().isNotEmpty)
          'assignment_id': widget.assignmentId!.trim(),
        if (widget.quickControlCode != null &&
            widget.quickControlCode!.trim().isNotEmpty)
          'quick_control_code': widget.quickControlCode!.trim(),
      };
      final kind = widget.protocolKind.trim().isEmpty
          ? 'custom_template'
          : widget.protocolKind.trim();
      final online = await _apiService.checkConnection();
      if (!online) {
        await _syncService.saveStandaloneProtocolOffline(
          title: title.isEmpty ? 'Протокол' : title,
          kind: kind,
          templateId: widget.template['id']?.toString(),
          templateName: widget.template['name']?.toString(),
          assignmentId: widget.assignmentId,
          payload: payload,
        );
        serverOk = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Нет сети: протокол в очереди. Отправьте на экране «Синхронизация».',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 6),
            ),
          );
        }
      } else {
        await _apiService.submitStandaloneProtocol(
          title: title.isEmpty ? 'Протокол' : title,
          kind: kind,
          templateId: widget.template['id']?.toString(),
          templateName: widget.template['name']?.toString(),
          assignmentId: widget.assignmentId,
          payload: payload,
        );
        serverOk = true;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Сервер: $e. Черновик остаётся на устройстве.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        if (serverOk) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Протокол на сервере. Веб → Генерация отчётов → «Протоколы из мобильного» → DOCX.',
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        }
        Navigator.of(context).pop();
      }
    }
  }
}
