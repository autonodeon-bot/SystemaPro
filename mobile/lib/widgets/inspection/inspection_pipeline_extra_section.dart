import '../../theme/app_colors.dart';
import 'package:flutter/material.dart';
import '../../models/vessel_checklist.dart';
import 'inspection_form_fields.dart';

/// ЭХЗ, геометрия, расчёт — данные для приложений И / З / К формы to-33.
class InspectionPipelineExtraSection extends StatefulWidget {
  final VesselChecklist checklist;
  final VoidCallback onStateChanged;

  const InspectionPipelineExtraSection({
    super.key,
    required this.checklist,
    required this.onStateChanged,
  });

  @override
  State<InspectionPipelineExtraSection> createState() =>
      _InspectionPipelineExtraSectionState();
}

class _InspectionPipelineExtraSectionState
    extends State<InspectionPipelineExtraSection> {
  Map<String, dynamic> get _ad {
    widget.checklist.additionalData ??= {};
    return widget.checklist.additionalData!;
  }

  Map<String, dynamic> get _station {
    final raw = _ad['ehz_station'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    final m = <String, dynamic>{};
    _ad['ehz_station'] = m;
    return m;
  }

  List<Map<String, dynamic>> get _ehzPoints {
    final raw = _ad['ehz_points'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  List<Map<String, dynamic>> get _geometryPoints {
    final raw = _ad['geometry_points'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  void _saveStation(String key, String? v) {
    _station[key] = v;
    _ad['ehz_station'] = _station;
    widget.onStateChanged();
  }

  void _setList(String key, List<Map<String, dynamic>> list) {
    _ad[key] = list;
    widget.onStateChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ehz = _ehzPoints;
    final geo = _geometryPoints;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionHeader('ЭХЗ и изоляция (прил. И)'),
        buildInspectionTextField(
          'ehz_station_type',
          'Тип катодной станции',
          (v) => _saveStation('station_type', v),
          initialValue: _station['station_type']?.toString(),
        ),
        buildInspectionTextField(
          'ehz_power',
          'Мощность УКЗ, Вт',
          (v) => _saveStation('power_w', v),
          initialValue: _station['power_w']?.toString(),
        ),
        buildInspectionTextField(
          'ehz_voltage',
          'Напряжение УКЗ, В',
          (v) => _saveStation('voltage_v', v),
          initialValue: _station['voltage_v']?.toString(),
        ),
        buildInspectionTextField(
          'ehz_current',
          'Ток УКЗ, А',
          (v) => _saveStation('current_a', v),
          initialValue: _station['current_a']?.toString(),
        ),
        const SizedBox(height: 8),
        Text('Точки защитного потенциала',
            style: TextStyle(
                color: AppColors.mutedText(context),
                fontWeight: FontWeight.w600)),
        ...ehz.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          return ListTile(
            dense: true,
            title: Text(
              'Точка ${p['point_on_scheme'] ?? i + 1}: ${p['protective_potential_v'] ?? '—'} В',
              style: TextStyle(color: AppColors.onSurface(context)),
            ),
            subtitle: Text(
              '${p['object_name'] ?? ''} | ${p['coating_state'] ?? ''}',
              style:
                  TextStyle(color: AppColors.mutedText(context), fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () {
                final list = _ehzPoints..removeAt(i);
                _setList('ehz_points', list);
              },
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _addEhzPoint(context),
            icon: const Icon(Icons.add),
            label: const Text('Добавить точку ЭХЗ'),
          ),
        ),
        const SizedBox(height: 16),
        buildSectionHeader('Геометрия / пространственное положение (прил. З)'),
        ...geo.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          return ListTile(
            dense: true,
            title: Text(
              '№ ${p['point'] ?? i + 1}: H=${p['height_mm'] ?? '—'} мм, уклон=${p['slope_mm_per_m'] ?? '—'}',
              style: TextStyle(color: AppColors.onSurface(context)),
            ),
            subtitle: Text(
              p['conclusion']?.toString() ?? '',
              style:
                  TextStyle(color: AppColors.mutedText(context), fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () {
                final list = _geometryPoints..removeAt(i);
                _setList('geometry_points', list);
              },
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _addGeometryPoint(context),
            icon: const Icon(Icons.add),
            label: const Text('Добавить точку геометрии'),
          ),
        ),
        const SizedBox(height: 16),
        buildSectionHeader('Расчёт толщины / срока службы (прил. К)'),
        buildInspectionTextField(
          'calc_min_thickness',
          'Минимально допустимая толщина стенки, мм',
          (v) {
            widget.checklist.calculationData ??= {};
            widget.checklist.calculationData!['min_thickness'] = v;
            widget.onStateChanged();
          },
          initialValue:
              widget.checklist.calculationData?['min_thickness']?.toString(),
        ),
        buildInspectionTextField(
          'calc_residual_life',
          'Расчётный срок безопасной эксплуатации, лет',
          (v) {
            widget.checklist.calculationData ??= {};
            widget.checklist.calculationData!['residual_life_years'] = v;
            widget.onStateChanged();
          },
          initialValue: widget.checklist.calculationData?['residual_life_years']
              ?.toString(),
        ),
        buildInspectionTextField(
          'calc_steel',
          'Марка стали (для расчёта)',
          (v) {
            widget.checklist.calculationData ??= {};
            widget.checklist.calculationData!['steel'] = v;
            _ad['pipe_material'] = v;
            widget.onStateChanged();
          },
          initialValue:
              widget.checklist.calculationData?['steel']?.toString() ??
                  _ad['pipe_material']?.toString(),
        ),
        buildInspectionTextField(
          'shurf_act_path',
          'Путь к скану акта шурфовки (файл на устройстве)',
          (v) {
            _ad['shurf_act_path'] = v;
            widget.onStateChanged();
          },
          initialValue: _ad['shurf_act_path']?.toString(),
        ),
        buildInspectionTextField(
          'shurf_notes',
          'Замечания по шурфовке (прил. М)',
          (v) {
            _ad['shurf_notes'] = v;
            widget.onStateChanged();
          },
          initialValue: _ad['shurf_notes']?.toString(),
        ),
      ],
    );
  }

  Future<void> _addEhzPoint(BuildContext context) async {
    final point = TextEditingController();
    final object = TextEditingController();
    final potential = TextEditingController();
    final coating = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Text('Точка ЭХЗ',
            style: TextStyle(color: AppColors.onSurface(context))),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: point,
                style: TextStyle(color: AppColors.onSurface(context)),
                decoration: InputDecoration(
                  labelText: '№ точки на схеме',
                  labelStyle: TextStyle(color: AppColors.mutedText(context)),
                ),
              ),
              TextField(
                controller: object,
                style: TextStyle(color: AppColors.onSurface(context)),
                decoration: InputDecoration(
                  labelText: 'Объект',
                  labelStyle: TextStyle(color: AppColors.mutedText(context)),
                ),
              ),
              TextField(
                controller: potential,
                style: TextStyle(color: AppColors.onSurface(context)),
                decoration: InputDecoration(
                  labelText: 'Защитный потенциал, В',
                  labelStyle: TextStyle(color: AppColors.mutedText(context)),
                ),
              ),
              TextField(
                controller: coating,
                style: TextStyle(color: AppColors.onSurface(context)),
                decoration: InputDecoration(
                  labelText: 'Состояние изоляции',
                  labelStyle: TextStyle(color: AppColors.mutedText(context)),
                ),
              ),
            ],
          ),
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
    if (ok == true) {
      final list = _ehzPoints
        ..add({
          'point_on_scheme': point.text.trim(),
          'object_name': object.text.trim(),
          'protective_potential_v': potential.text.trim(),
          'coating_state': coating.text.trim(),
        });
      _setList('ehz_points', list);
    }
  }

  Future<void> _addGeometryPoint(BuildContext context) async {
    final point = TextEditingController();
    final height = TextEditingController();
    final slope = TextEditingController();
    final conclusion = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Text('Точка геометрии',
            style: TextStyle(color: AppColors.onSurface(context))),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: point,
                style: TextStyle(color: AppColors.onSurface(context)),
                decoration: InputDecoration(
                  labelText: '№ точки',
                  labelStyle: TextStyle(color: AppColors.mutedText(context)),
                ),
              ),
              TextField(
                controller: height,
                style: TextStyle(color: AppColors.onSurface(context)),
                decoration: InputDecoration(
                  labelText: 'Высота, мм',
                  labelStyle: TextStyle(color: AppColors.mutedText(context)),
                ),
              ),
              TextField(
                controller: slope,
                style: TextStyle(color: AppColors.onSurface(context)),
                decoration: InputDecoration(
                  labelText: 'Уклон, мм/м',
                  labelStyle: TextStyle(color: AppColors.mutedText(context)),
                ),
              ),
              TextField(
                controller: conclusion,
                style: TextStyle(color: AppColors.onSurface(context)),
                decoration: InputDecoration(
                  labelText: 'Вывод',
                  labelStyle: TextStyle(color: AppColors.mutedText(context)),
                ),
              ),
            ],
          ),
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
    if (ok == true) {
      final list = _geometryPoints
        ..add({
          'point': point.text.trim(),
          'height_mm': height.text.trim(),
          'slope_mm_per_m': slope.text.trim(),
          'conclusion': conclusion.text.trim(),
        });
      _setList('geometry_points', list);
    }
  }
}
