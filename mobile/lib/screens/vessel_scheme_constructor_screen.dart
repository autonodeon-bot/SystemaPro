import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/scheme_equipment_catalog.dart';
import '../constants/report_formulation_options.dart';

/// Результат конструктора карты контроля.
class VesselSchemeConstructorResult {
  final String imagePath;
  final Map<String, dynamic> geometry;
  final String orientation;
  final String equipmentKind;
  final String? formId;

  VesselSchemeConstructorResult({
    required this.imagePath,
    required this.geometry,
    required this.orientation,
    required this.equipmentKind,
    this.formId,
  });
}

/// Мастер: тип (44 формы ТО) → параметры → превью → применить.
class VesselSchemeConstructorScreen extends StatefulWidget {
  final String? initialOrientation;
  final String? initialEquipmentKind;
  final String? initialFormId;

  const VesselSchemeConstructorScreen({
    super.key,
    this.initialOrientation,
    this.initialEquipmentKind,
    this.initialFormId,
  });

  @override
  State<VesselSchemeConstructorScreen> createState() =>
      _VesselSchemeConstructorScreenState();
}

class _VesselSchemeConstructorScreenState
    extends State<VesselSchemeConstructorScreen> {
  final _repaintKey = GlobalKey();
  final _searchCtrl = TextEditingController();

  int _step = 0; // 0 kind, 1 params, 2 preview
  List<SchemeEquipmentKind> _kinds = [];
  List<String> _groups = [];
  SchemeEquipmentKind? _selected;
  bool _loadingKinds = true;

  String _orientation = 'vertical';
  String _weldPreset = 'multi_shell';
  int _shellCount = 3;
  String _headType = 'elliptical';
  final List<Map<String, dynamic>> _nozzles = [];
  bool _busy = false;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    final o = (widget.initialOrientation ?? '').toLowerCase();
    if (o == 'vertical' || o == 'horizontal') {
      _orientation = o;
    } else if (o.contains('верт')) {
      _orientation = 'vertical';
    } else if (o.contains('гориз')) {
      _orientation = 'horizontal';
    }
    _nozzles.add({
      'id': 'N1',
      'dn': 50,
      'position': 0.35,
      'side': 'body',
      'label': 'Пт1',
      'purpose': 'вход нефти',
    });
    _loadKinds();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadKinds() async {
    setState(() {
      _loadingKinds = true;
      _error = null;
    });
    try {
      final items = await SchemeEquipmentCatalog.instance.ensureLoaded();
      final groups = SchemeEquipmentCatalog.instance.groups;
      SchemeEquipmentKind? pre;
      pre = SchemeEquipmentCatalog.instance.findByCodeOrForm(
            widget.initialEquipmentKind,
          ) ??
          SchemeEquipmentCatalog.instance.findByCodeOrForm(widget.initialFormId);
      if (!mounted) return;
      setState(() {
        _kinds = items;
        _groups = groups.isNotEmpty
            ? groups
            : items.map((e) => e.group).toSet().toList();
        _loadingKinds = false;
        if (pre != null) {
          _applyKind(pre, advance: true);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingKinds = false;
        _error = 'Не удалось загрузить типы: $e';
      });
    }
  }

  void _applyKind(SchemeEquipmentKind k, {bool advance = false}) {
    _selected = k;
    final d = k.defaults;
    if (d['orientation'] is String) {
      _orientation = d['orientation'] == 'horizontal' ? 'horizontal' : 'vertical';
    } else if (k.family == 'pipeline' || k.family == 'crane') {
      _orientation = 'horizontal';
    } else {
      _orientation = 'vertical';
    }
    if (d['shell_count'] is num) {
      _shellCount = (d['shell_count'] as num).toInt();
    } else if (k.family == 'pipeline') {
      _shellCount = 4;
    } else if (k.family == 'vessel_development') {
      _shellCount = 3;
    }
    if (d['weld_preset'] is String) {
      _weldPreset = d['weld_preset'].toString();
    } else if (k.family == 'pipeline') {
      _weldPreset = 'ring_only';
    } else {
      _weldPreset = 'multi_shell';
    }
    if (advance) _step = 1;
  }

  bool get _isVesselFamily =>
      (_selected?.family ?? '') == 'vessel_development';
  bool get _isPipelineFamily => (_selected?.family ?? '') == 'pipeline';
  bool get _showCount => [
        'vessel_development',
        'pipeline',
        'tank',
        'tower',
        'boiler',
        'crane',
        'station',
        'electrical',
        'machinery',
        'valve',
        'generic',
      ].contains(_selected?.family);

  String get _countLabel {
    switch (_selected?.family) {
      case 'pipeline':
        return 'Секций / стыков';
      case 'tank':
        return 'Поясов стенки';
      case 'tower':
        return 'Поясов ствола';
      case 'boiler':
        return 'Зон котла';
      case 'crane':
        return 'Пролётов / зон';
      case 'station':
        return 'Узлов на схеме';
      case 'electrical':
        return 'Ячеек / зон';
      case 'machinery':
        return 'Узлов агрегата';
      case 'valve':
        return 'Узлов арматуры';
      case 'vessel_development':
        return 'Обечаек / поясов';
      default:
        return 'Зон контроля';
    }
  }

  String get _familyHint {
    switch (_selected?.family) {
      case 'vessel_development':
        return 'Развёртка: днища — круги, продольные швы вразбежку.';
      case 'pipeline':
        return 'Линейная схема трубопровода со стыками.';
      case 'tank':
        return 'План резервуара + развёртка стенки.';
      case 'tower':
        return 'Ствол трубы / факела с поясами.';
      case 'boiler':
        return 'Схема котла по зонам контроля.';
      case 'crane':
        return 'Схема ГПМ / подкрановых путей.';
      case 'station':
        return 'План станции / узла.';
      case 'electrical':
        return 'Схема электрооборудования.';
      case 'machinery':
        return 'Схема агрегата по узлам.';
      case 'valve':
        return 'Схема арматуры / обвязки.';
      default:
        return 'Карта контроля по семейству «${_selected?.familyTitle ?? _selected?.family}».';
    }
  }

  Map<String, dynamic> get _geometry => {
        'equipment_kind': _selected?.code ?? 'vessel',
        'form_id': _selected?.formId,
        'orientation': _orientation,
        'shell': {'length': 1.0, 'diameter': 0.5, 'count': _shellCount},
        'shell_count': _shellCount,
        'segment_count': _shellCount,
        'head_type': _headType,
        'weld_preset': _weldPreset,
        'nozzles': (_isVesselFamily || _isPipelineFamily) ? _nozzles : [],
        'title': 'Карта контроля: ${_selected?.title ?? ''}',
      };

  Future<String?> _renderViaApi() async {
    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) return null;
      final uri = Uri.parse('${ApiService.baseUrl}/api/vessel-scheme/render');
      final res = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'equipment_kind': _selected?.code ?? 'vessel',
              'form_id': _selected?.formId,
              'orientation': _orientation,
              'shell_length': 1.0,
              'shell_diameter': 0.5,
              'shell_count': _shellCount,
              'segment_count': _shellCount,
              'head_type': _headType,
              'weld_preset': _weldPreset,
              'nozzles': (_isVesselFamily || _isPipelineFamily) ? _nozzles : [],
              'title': 'Карта контроля: ${_selected?.title ?? ''}',
              'width': 1000,
              'height': 1200,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return null;
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/scheme_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(res.bodyBytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<String> _renderLocal() async {
    final boundary =
        _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.5);
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = bd!.buffer.asUint8List();
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/scheme_local_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var path = await _renderViaApi();
      path ??= await _renderLocal();
      if (!mounted) return;
      Navigator.of(context).pop(
        VesselSchemeConstructorResult(
          imagePath: path,
          geometry: Map<String, dynamic>.from(_geometry),
          orientation: _orientation,
          equipmentKind: _selected?.code ?? 'vessel',
          formId: _selected?.formId,
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<SchemeEquipmentKind> get _filtered {
    final q = _filter.trim().toLowerCase();
    if (q.isEmpty) return _kinds;
    return _kinds.where((k) {
      return k.title.toLowerCase().contains(q) ||
          k.code.contains(q) ||
          k.formId.contains(q) ||
          k.formId.replaceFirst('to-', '') == q;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: Text(_step == 0
            ? 'Конструктор · тип оборудования'
            : (_selected?.title ?? 'Карта контроля')),
        backgroundColor: const Color(0xFF1e293b),
        actions: [
          if (_kinds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${SchemeEquipmentCatalog.instance.formsCount}/44',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadingKinds
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _stepHeader(),
                      const SizedBox(height: 12),
                      if (_step == 0) _stepKind(),
                      if (_step == 1) _stepParams(),
                      if (_step == 2) _stepPreview(),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.redAccent)),
                        ),
                    ],
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _step -= 1),
                      child: const Text('Назад'),
                    ),
                  const Spacer(),
                  if (_step == 0)
                    ElevatedButton(
                      onPressed: _selected == null
                          ? null
                          : () => setState(() => _step = 1),
                      child: const Text('Далее'),
                    )
                  else if (_step == 1)
                    ElevatedButton(
                      onPressed: () => setState(() => _step = 2),
                      child: const Text('Превью'),
                    )
                  else
                    ElevatedButton(
                      onPressed: _busy ? null : _apply,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Применить'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepHeader() {
    const labels = ['Тип (ТО)', 'Параметры', 'Готово'];
    final forms = SchemeEquipmentCatalog.instance.formsCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Шаг ${_step + 1}/3: ${labels[_step]}',
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        if (_step == 0)
          Text(
            'Форм ТО в каталоге: $forms (ожидается 44)',
            style: TextStyle(
              color: forms >= 44 ? Colors.greenAccent : Colors.orangeAccent,
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  Widget _stepKind() {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Поиск: название, код или to-12',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
          ),
          onChanged: (v) => setState(() => _filter = v),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const Text('Ничего не найдено',
              style: TextStyle(color: Colors.white54))
        else
          ..._groups.map((g) {
            final items = filtered.where((k) => k.group == g).toList();
            if (items.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Text(
                    g.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                ...items.map((k) {
                  final selected = _selected?.code == k.code;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    selectedTileColor: const Color(0xFF1e3a5f),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    title: Text(k.title,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: Text('${k.formId} · ${k.familyTitle ?? k.family}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                    trailing: selected
                        ? const Icon(Icons.check_circle, color: Colors.blueAccent)
                        : null,
                    onTap: () => setState(() => _applyKind(k)),
                  );
                }),
              ],
            );
          }),
      ],
    );
  }

  Widget _stepParams() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selected != null)
          Text(
            '${_selected!.formId} · ${_selected!.familyTitle ?? _selected!.family}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        const SizedBox(height: 8),
        if (_isVesselFamily) ...[
          _radioTile('vertical', 'Вертикальный'),
          _radioTile('horizontal', 'Горизонтальный'),
          const SizedBox(height: 8),
          _buildNozzleEditor(),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _headType,
            dropdownColor: const Color(0xFF1e293b),
            decoration: const InputDecoration(
              labelText: 'Тип днищ',
              labelStyle: TextStyle(color: Colors.white70),
            ),
            style: const TextStyle(color: Colors.white),
            items: const [
              DropdownMenuItem(value: 'elliptical', child: Text('Эллиптические')),
              DropdownMenuItem(
                  value: 'hemispherical', child: Text('Полусферические')),
              DropdownMenuItem(value: 'flat', child: Text('Плоские')),
            ],
            onChanged: (v) => setState(() => _headType = v ?? 'elliptical'),
          ),
        ],
        if (_showCount) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                _countLabel,
                style: const TextStyle(color: Colors.white70),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => setState(
                    () => _shellCount = (_shellCount - 1).clamp(1, 20)),
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.white70),
              ),
              Text('$_shellCount',
                  style: const TextStyle(color: Colors.white, fontSize: 18)),
              IconButton(
                onPressed: () => setState(
                    () => _shellCount = (_shellCount + 1).clamp(1, 20)),
                icon: const Icon(Icons.add_circle_outline,
                    color: Colors.white70),
              ),
            ],
          ),
        ],
        if (_isVesselFamily || _isPipelineFamily) ...[
          const SizedBox(height: 8),
          _presetTile('ring_only', 'Только кольцевые (К)'),
          if (_isVesselFamily) ...[
            _presetTile(
                'long_plus_rings', 'Продольные вразбежку (~½) + кольцевые'),
            _presetTile(
                'multi_shell', 'Несколько обечаек, часть с двумя продольными'),
          ],
          const SizedBox(height: 8),
          Text(
            _familyHint,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
        if (!_isVesselFamily && !_isPipelineFamily)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _familyHint,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _buildNozzleEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Патрубки / легенда',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(
              onPressed: () {
                setState(() {
                  _nozzles.add({
                    'id': 'N${_nozzles.length + 1}',
                    'dn': 50,
                    'position': (0.15 + _nozzles.length * 0.14).clamp(0.08, 0.92),
                    'circ': (0.2 + (_nozzles.length % 4) * 0.2).clamp(0.1, 0.9),
                    'side': 'body',
                    'place': 'body',
                    'label': 'Пт${_nozzles.length + 1}',
                    'purpose': ReportFormulationOptions.nozzlePurposes.first,
                  });
                });
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
        ..._nozzles.asMap().entries.map((e) {
          final i = e.key;
          final n = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: n['label']?.toString() ?? '',
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Обозн.',
                          labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        onChanged: (v) => n['label'] = v,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: ReportFormulationOptions.nozzlePurposes.contains(n['purpose'])
                            ? n['purpose'] as String
                            : ReportFormulationOptions.nozzlePurposes.first,
                        dropdownColor: const Color(0xFF1e293b),
                        decoration: const InputDecoration(
                          labelText: 'Назначение',
                          labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        items: ReportFormulationOptions.nozzlePurposes
                            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (v) => setState(() => n['purpose'] = v ?? ''),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _nozzles.removeAt(i)),
                      icon: const Icon(Icons.delete_outline, color: Colors.white54),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: '${n['dn'] ?? 50}',
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'DN, мм',
                          labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        onChanged: (v) => n['dn'] = int.tryParse(v) ?? v,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: (n['place'] as String?) ?? 'body',
                        dropdownColor: const Color(0xFF1e293b),
                        decoration: const InputDecoration(
                          labelText: 'Место',
                          labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        items: const [
                          DropdownMenuItem(value: 'body', child: Text('Корпус')),
                          DropdownMenuItem(value: 'head_top', child: Text('Верх/лево днище')),
                          DropdownMenuItem(value: 'head_bottom', child: Text('Низ/право днище')),
                        ],
                        onChanged: (v) => setState(() {
                          n['place'] = v ?? 'body';
                          n['side'] = v == 'head_top'
                              ? 'top'
                              : v == 'head_bottom'
                                  ? 'bottom'
                                  : 'body';
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: '${n['position'] ?? 0.5}',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Ось 0–1',
                          labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        onChanged: (v) => n['position'] = double.tryParse(v.replaceAll(',', '.')) ?? 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: '${n['circ'] ?? 0.55}',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Окруж. 0–1',
                          labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        onChanged: (v) => n['circ'] = double.tryParse(v.replaceAll(',', '.')) ?? 0.55,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _radioTile(String value, String label) {
    return RadioListTile<String>(
      value: value,
      groupValue: _orientation,
      activeColor: Colors.blue,
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onChanged: (v) {
        if (v == null) return;
        setState(() => _orientation = v);
      },
    );
  }

  Widget _presetTile(String value, String label) {
    return RadioListTile<String>(
      value: value,
      groupValue: _weldPreset,
      activeColor: Colors.blue,
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      onChanged: (v) {
        if (v == null) return;
        setState(() => _weldPreset = v);
      },
    );
  }

  Widget _stepPreview() {
    return Column(
      children: [
        Container(
          height: 420,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: RepaintBoundary(
            key: _repaintKey,
            child: CustomPaint(
              painter: _VesselSchemePainter(
                orientation: _orientation,
                weldPreset: _weldPreset,
                shellCount: _shellCount,
                nozzles: _nozzles,
                family: _selected?.family ?? 'vessel_development',
                title: _selected?.title ?? 'Карта контроля',
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Превью офлайн. При применении предпочтительно API-рендер (${_selected?.formId ?? ""}).',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _VesselSchemePainter extends CustomPainter {
  final String orientation;
  final String weldPreset;
  final int shellCount;
  final List<Map<String, dynamic>> nozzles;
  final String family;
  final String title;

  _VesselSchemePainter({
    required this.orientation,
    required this.weldPreset,
    required this.shellCount,
    required this.nozzles,
    required this.family,
    required this.title,
  });

  List<double> _longPositions(int shellIndex, {required bool dual}) {
    if (dual) {
      final phase = ((shellIndex ~/ 2) % 2) * 0.25;
      return [0.18 + phase, 0.68 + phase];
    }
    return [shellIndex.isEven ? 0.30 : 0.70];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = const Color(0xFF1e1e1e)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final weld = Paint()
      ..color = const Color(0xFFb42828)
      ..strokeWidth = 2;
    final nozzle = Paint()
      ..color = const Color(0xFF1e50a0)
      ..strokeWidth = 2.0;

    final tp = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(color: Color(0xFF222222), fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 16);
    tp.paint(canvas, const Offset(8, 4));

    if (family == 'pipeline') {
      final y = size.height * 0.45;
      final h = 36.0;
      final x0 = 40.0;
      final x1 = size.width - 40;
      canvas.drawRect(Rect.fromLTRB(x0, y - h / 2, x1, y + h / 2), ink);
      final n = shellCount < 1 ? 1 : shellCount;
      for (var i = 0; i <= n; i++) {
        final x = x0 + (x1 - x0) * (i / n);
        canvas.drawLine(Offset(x, y - h / 2), Offset(x, y + h / 2), weld);
      }
      return;
    }

    if (family != 'vessel_development' && family != 'tank') {
      final n = shellCount < 1 ? 1 : shellCount;
      if (family == 'tower') {
        final cx = size.width / 2;
        final top = 50.0;
        final bot = size.height - 40;
        final path = Path()
          ..moveTo(cx - 28, top)
          ..lineTo(cx + 28, top)
          ..lineTo(cx + 70, bot)
          ..lineTo(cx - 70, bot)
          ..close();
        canvas.drawPath(path, ink);
        for (var i = 1; i < n; i++) {
          final t = i / n;
          final y = top + (bot - top) * t;
          final w = 28 + (70 - 28) * t;
          canvas.drawLine(Offset(cx - w, y), Offset(cx + w, y), weld);
        }
        return;
      }
      if (family == 'crane') {
        final y = size.height * 0.35;
        canvas.drawLine(Offset(40, y), Offset(size.width - 40, y), ink);
        canvas.drawLine(Offset(40, y), Offset(40, size.height - 50), ink);
        canvas.drawLine(
            Offset(size.width - 40, y), Offset(size.width - 40, size.height - 50), ink);
        for (var i = 1; i < n; i++) {
          final x = 40 + (size.width - 80) * (i / n);
          canvas.drawLine(Offset(x, y - 8), Offset(x, y + 8), weld);
          canvas.drawCircle(Offset(x, y), 4, nozzle);
        }
        return;
      }
      if (family == 'machinery' || family == 'boiler' || family == 'valve') {
        final body = Rect.fromLTRB(50, 50, size.width - 50, size.height - 50);
        canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(12)), ink);
        for (var i = 0; i < n; i++) {
          final x = body.left + body.width * ((i + 0.5) / n);
          canvas.drawCircle(Offset(x, body.center.dy), 10, nozzle);
          canvas.drawLine(
              Offset(x, body.top + 20), Offset(x, body.bottom - 20), weld);
        }
        return;
      }
      if (family == 'electrical' || family == 'station') {
        final cols = n.clamp(1, 6);
        final body = Rect.fromLTRB(30, 40, size.width - 30, size.height - 30);
        canvas.drawRect(body, ink);
        for (var c = 0; c < cols; c++) {
          final x0 = body.left + body.width * (c / cols);
          final x1 = body.left + body.width * ((c + 1) / cols);
          canvas.drawRect(Rect.fromLTRB(x0 + 4, body.top + 8, x1 - 4, body.bottom - 8), ink);
          canvas.drawCircle(Offset((x0 + x1) / 2, body.center.dy), 6, nozzle);
        }
        return;
      }
      // generic
      final body = Rect.fromLTRB(30, 40, size.width - 30, size.height - 30);
      canvas.drawRect(body, ink);
      for (var i = 0; i < n; i++) {
        final y = body.top + body.height * ((i + 0.5) / n);
        canvas.drawLine(Offset(body.left + 10, y), Offset(body.right - 10, y), weld);
        canvas.drawCircle(Offset(body.center.dx, y), 5, nozzle);
      }
      return;
    }

    // Развёртка сосуда / резервуара
    final cx = size.width / 2;
    final headR = size.width * 0.14;
    const gap = 10.0;
    final topCy = 28 + headR;
    final botCy = size.height - 20 - headR;
    final bodyTop = topCy + headR + gap;
    final bodyBot = botCy - headR - gap;
    final bodyW = size.width * 0.62;
    final body = Rect.fromLTRB(cx - bodyW / 2, bodyTop, cx + bodyW / 2, bodyBot);

    canvas.drawCircle(Offset(cx, topCy), headR, ink);
    canvas.drawCircle(Offset(cx, botCy), headR, ink);
    canvas.drawLine(
        Offset(cx, topCy - headR + 3), Offset(cx, topCy + headR - 3), weld);
    canvas.drawLine(
        Offset(cx, botCy - headR + 3), Offset(cx, botCy + headR - 3), weld);
    canvas.drawRect(body, ink);

    final n = shellCount < 1 ? 1 : shellCount;
    for (var i = 0; i <= n; i++) {
      final y = body.top + body.height * (i / n);
      canvas.drawLine(Offset(body.left, y), Offset(body.right, y), weld);
    }
    if (weldPreset != 'ring_only') {
      for (var s = 0; s < n; s++) {
        final dual = n >= 3 && s > 0 && s < n - 1 && s.isOdd;
        final y0 = body.top + body.height * (s / n) + 2;
        final y1 = body.top + body.height * ((s + 1) / n) - 2;
        for (final circ in _longPositions(s, dual: dual)) {
          final x = body.left + body.width * circ.clamp(0.06, 0.94);
          canvas.drawLine(Offset(x, y0), Offset(x, y1), weld);
        }
      }
    }
    for (final nzz in nozzles) {
      final t = (nzz['position'] as num?)?.toDouble() ?? 0.5;
      final circ = (nzz['circ'] as num?)?.toDouble() ?? 0.55;
      final x = body.left + body.width * circ.clamp(0.08, 0.92);
      final y = body.top + body.height * t.clamp(0.08, 0.92);
      canvas.drawCircle(Offset(x, y), 7, nozzle);
    }
  }

  @override
  bool shouldRepaint(covariant _VesselSchemePainter oldDelegate) => true;
}
