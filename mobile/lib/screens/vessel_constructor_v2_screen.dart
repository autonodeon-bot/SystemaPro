import '../models/vessel_library.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import '../models/vessel_geometry.dart';
import '../models/vessel_merge.dart';
import '../services/vessel_constructor_store.dart';
import '../services/vessel_svg_export.dart';
import '../widgets/vessel_drawing.dart';
import '../widgets/vessel_elements_editor.dart';
import 'vessel_scheme_constructor_screen.dart'
    show VesselSchemeConstructorResult;

class VesselConstructorV2Screen extends StatefulWidget {
  final Map<String, dynamic>? initialGeometry;
  final String orientation, equipmentKind, draftKey;
  final String? formId;
  final Set<String> measuredPointIds;
  final Set<String> measuredZoneIds;
  final List<Map<String, dynamic>> legacyMeasurements;
  const VesselConstructorV2Screen(
      {super.key,
      this.initialGeometry,
      this.orientation = 'vertical',
      this.equipmentKind = 'vessel',
      this.formId,
      required this.draftKey,
      this.measuredPointIds = const {},
      this.measuredZoneIds = const {},
      this.legacyMeasurements = const []});
  @override
  State<VesselConstructorV2Screen> createState() =>
      _VesselConstructorV2ScreenState();
}

class _VesselConstructorV2ScreenState extends State<VesselConstructorV2Screen>
    with WidgetsBindingObserver {
  late final VesselConstructorStore store;
  VesselGeometry get g => store.geometry;
  String? detail;
  String layer = 'Все';
  bool move = false,
      moveLabel = false,
      exteriorB = false,
      busy = false,
      ready = false,
      allowPop = false;
  final transform = TransformationController();
  static const steps = [
    'Основа',
    'Части и швы',
    'Элементы',
    'Контроль',
    'Проверка'
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store = VesselConstructorStore(
        VesselGeometry.load(widget.initialGeometry,
            orientation: widget.orientation),
        widget.draftKey);
    store.addListener(refresh);
    restore();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> restore() async {
    try {
      final draft = await store.readDraft();
      if (draft != null && mounted) {
        final use = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                    title: const Text('Найден черновик конструктора'),
                    content: Text(
                        'Сохранён ${draft['saved_at'] ?? ''}. Применённая схема обследования ещё не изменена.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Открыть применённую')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Восстановить'))
                    ]));
        if (use == true) {
          final baseline = draft['base_geometry'];
          final local = Map<String, dynamic>.from(draft['geometry'] as Map);
          if (baseline is Map && baseline['model_id'] == g.data['model_id'] &&
              baseline['revision'] != g.data['revision']) {
            final comparison = VesselMerge(Map<String, dynamic>.from(baseline), local, g.data);
            while (comparison.conflicts.isNotEmpty && mounted) {
              if (!mounted) return;
              final conflict = comparison.conflicts.first;
              final choice = await showDialog<bool>(context: context, barrierDismissible: false,
                builder: (c) => AlertDialog(
                  title: const Text('Изменения одной и той же детали'),
                  content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Раздел: ${conflict.key}'),
                    const Text('Мой черновик', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(const JsonEncoder.withIndent('  ').convert(conflict.local)),
                    const Divider(),
                    const Text('Применённая версия', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(const JsonEncoder.withIndent('  ').convert(conflict.remote)),
                  ])),
                  actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Применённая')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Мой черновик'))]));
              if (choice == null) return;
              comparison.choose(conflict, choice);
            }
            store.restore({...draft, 'geometry': comparison.merged});
            message('Независимые изменения объединены. Проверьте схему перед применением.');
          } else {
            store.restore(draft);
          }
        }
      }
    } catch (e) {
      message('Не удалось прочитать черновик: $e');
    }
    if (mounted) {
      setState(() {
        ready = true;
        store.selection ??= g.shells.first['id'];
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (ready && state != AppLifecycleState.resumed) store.flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(refresh);
    store.dispose();
    transform.dispose();
    super.dispose();
  }

  void message(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  void edit(void Function(VesselGeometry) action) {
    try {
      store.command(action);
    } catch (e) {
      message(e.toString());
    }
  }

  Future<void> leave() async {
    final choice = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Закрыть конструктор?'),
                content: const Text(
                    'Изменения попадут в обследование только после «Применить». Черновик можно продолжить позднее.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Продолжить')),
                  TextButton(
                      onPressed: () => Navigator.pop(c, 'discard'),
                      child: const Text('Удалить черновик')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, 'save'),
                      child: const Text('Сохранить и выйти'))
                ]));
    if (choice == null) return;
    if (choice == 'discard') {
      await store.discard();
    } else {
      await store.flush();
      if (store.saveStatus.startsWith('Не удалось')) return;
    }
    if (mounted) {
      setState(() => allowPop = true);
      Navigator.pop(context);
    }
  }

  Future<Map<String, String>?> fields(String title, Map<String, String> values,
      {String? hint}) async {
    final controllers =
        values.map((k, v) => MapEntry(k, TextEditingController(text: v)));
    final form = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(title),
                content: SizedBox(
                    width: 420,
                    child: Form(
                        key: form,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              if (hint != null)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(hint)),
                              for (final e in controllers.entries)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: TextFormField(
                                        controller: e.value,
                                        keyboardType: e.key.contains('мм') ||
                                                e.key.contains('°') ||
                                                e.key == 'Количество'
                                            ? const TextInputType
                                                .numberWithOptions(
                                                decimal: true, signed: true)
                                            : TextInputType.text,
                                        decoration: InputDecoration(
                                            labelText: e.key,
                                            border: const OutlineInputBorder()),
                                        validator: (v) =>
                                            v != null && v.length > 250
                                                ? 'Не более 250 символов'
                                                : null)),
                            ])))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () {
                        if (form.currentState!.validate()) {
                          Navigator.pop(
                              c,
                              controllers
                                  .map((k, v) => MapEntry(k, v.text.trim())));
                        }
                      },
                      child: const Text('Сохранить'))
                ]));
    // Dialog exit animation may still use its controllers; let route dispose them.
    return result;
  }

  double? number(String? value, {bool positive = false}) {
    if (value == null || value.isEmpty) return null;
    final n = double.tryParse(value.replaceAll(',', '.'));
    if (n == null || !n.isFinite || (positive && n <= 0)) {
      throw const FormatException(
          'Введите корректное число; размеры должны быть больше нуля.');
    }
    return n;
  }

  Future<void> base() async {
    final f = g.data['coordinate_frame'] as Map;
    final v = await fields(
        'Основа и источник',
        {
          'Ноль угла': f['zero_description'] ?? '',
          'Источник (паспорт, фото, лист)': g.data['source_note'] ?? '',
          'Линия разреза, °': '${g.cut}'
        },
        hint:
            'Ось A → B. Смотрим со стороны A вдоль оси, угол по часовой стрелке. Введите описание нуля для подтверждения.');
    if (v == null) return;
    try {
      final cut = number(v['Линия разреза, °']) ?? 0;
      edit((m) {
        m.data['coordinate_frame']['zero_description'] = v['Ноль угла'];
        m.data['coordinate_frame']['confirmed'] = v['Ноль угла']!.isNotEmpty;
        m.data['source_note'] = v['Источник (паспорт, фото, лист)'];
        (m.data['views'] as List).first['cut_angle_deg'] = cut % 360;
      });
    } catch (e) {
      message('$e');
    }
  }

  Future<void> loadVisioExample() async {
    if (widget.measuredPointIds.isNotEmpty || widget.measuredZoneIds.isNotEmpty) {
      message('В обследовании уже есть результаты. Откройте пример в новом обследовании.');
      return;
    }
    final use = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Пример по Visio'),
      content: const Text('6 обечаек, 2 днища, крышка люка Т, 25 элементов и 138 точек. Размеры учебные. Заменить текущую схему? Изменение можно отменить.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Загрузить схему'))]));
    if (use != true) return;
    try {
      final raw = jsonDecode(await rootBundle.loadString('assets/data/visio_vessel_example.json')) as Map<String, dynamic>;
      final example = VesselGeometry.fromExample(raw);
      edit((m) { store.geometry = example; });
      setState(() { detail = null; store.selection = g.shells.first['id']; });
      transform.value = Matrix4.identity();
      message('Пример загружен. Выберите деталь на чертеже или в списке и измените её параметры.');
    } catch (e) { message('Не удалось загрузить пример: $e'); }
  }

  Future<void> partProperties(VesselEntity p) async {
    final d = p['dimensions'] as Map;
    final v = await fields(
        '${p['designation']}',
        {
          'Обозначение': p['designation'],
          if (p['kind'] == 'shell') 'Длина, мм': '${d['length_mm'] ?? ''}',
          'Диаметр, мм': '${d['diameter_mm'] ?? ''}',
          'Толщина, мм': '${d['thickness_mm'] ?? ''}',
          'Источник размеров': p['dimension_source'] ?? ''
        },
        hint:
            'Пустое поле означает неизвестный размер. Для днища и крышки диаметр задаёт плоскую проекцию.');
    if (v == null) return;
    try {
      final length = number(v['Длина, мм'], positive: true),
          diameter = number(v['Диаметр, мм'], positive: true),
          thickness = number(v['Толщина, мм'], positive: true);
      edit((m) {
        final target = m.entity(p['id'])!;
        target['designation'] = v['Обозначение'];
        target['dimensions'] = {
          'length_mm': length,
          'diameter_mm': diameter,
          'thickness_mm': thickness
        };
        target['dimension_source'] = v['Источник размеров'];
        target['confidence'] =
            v['Источник размеров']!.isEmpty ? 'unknown' : 'user_confirmed';
      });
    } catch (e) {
      message('$e');
    }
  }

  Future<void> coordinates(VesselEntity e) async {
    final owner = g.entity(e['parent_id'] ?? e['owner_id']);
    final shell = owner?['kind'] == 'shell';
    final p = e['placement'] as Map;
    final rings=shell ? g.welds.where((w)=>w['kind']=='circumferential' && (w['connected_part_ids'] as List).contains(owner!['id'])).toList() : <VesselEntity>[];
    final startRing=rings.where((w)=>(w['connected_part_ids'] as List).last==owner!['id']).firstOrNull;
    final reference=g.entity(p['reference_weld_id']) ?? startRing;
    final length=(owner?['dimensions']?['length_mm'] as num?)?.toDouble();
    final fromEnd=shell && reference!=null && (reference['connected_part_ids'] as List).first==owner!['id'];
    final stored=p['z_local_mm'] as num?;
    final distance= shell ? (fromEnd && length!=null && stored!=null ? length-stored : stored) : p['radius_projection_mm'];
    final axis = shell ? 'До центра от шва, мм' : 'Радиус проекции, мм';
    final v = await fields(
        'Точное размещение',
        {
          if(shell) 'Базовый шов (${rings.map((w)=>w['designation']).join(', ')})': '${reference?['designation'] ?? ''}',
          axis: '${distance ?? ''}',
          if(!shell) 'Отсчёт: visio / legacy': '${p['angle_convention']=='visio-head-2026'?'visio':'legacy'}',
          'Угол, °': '${p['theta_deg'] ?? 0}'
        },
        hint:
            '${owner?['designation']} • ноль: ${g.data['coordinate_frame']['zero_description'] ?? 'не задан'}. Для днищ visio: A 0° слева, B 0° справа, 90° сверху. legacy сохраняет прежний отсчёт. Для точного режима задайте размеры части.');
    if (v == null) return;
    try {
      final dist = number(v[axis]), angle = number(v['Угол, °']);
      final extent =
          (owner?['dimensions']?[shell ? 'length_mm' : 'diameter_mm'] as num?)
              ?.toDouble();
      if (dist == null ||
          angle == null ||
          extent == null ||
          dist < 0 ||
          dist > (shell ? extent : extent / 2)) {
        throw const FormatException(
            'Задайте размер части и координату внутри неё.');
      }
      final chosen=shell ? rings.where((w)=>w['designation']==v.entries.first.value).firstOrNull : null;
      if(shell && chosen==null) throw const FormatException('Выберите обозначение одного из граничных швов');
      if (!await allowPhysicalMove(e)) return;
      edit((m) => m.entity(e['id'])!['placement'] = {
            'mode': 'physical',
            shell ? 'z_local_mm' : 'radius_projection_mm': shell && (chosen!['connected_part_ids'] as List).first==owner!['id'] ? extent-dist : dist,
            if(shell) 'reference_weld_id': chosen!['id'],
            if(!shell && v['Отсчёт: visio / legacy']=='visio') 'angle_convention':'visio-head-2026',
            'theta_deg': angle % 360
          });
    } catch (error) {
      message('$error');
    }
  }

  Future<bool> allowPhysicalMove(VesselEntity e) async {
    if (!widget.measuredPointIds.contains(e['id']) &&
        !(g.data['legacy_point_bindings'] as Map? ?? {}).containsKey(e['id'])) {
      return true;
    }
    final reason = await fields(
        'У точки уже есть результат', {'Причина перемещения': ''},
        hint:
            'Изменение будет записано в историю ревизий; результат останется привязан к той же точке.');
    if (reason == null || reason.values.first.isEmpty) return false;
    edit((m) {
      (m.data.putIfAbsent('revision_history', () => []) as List).add({
        'entity_id': e['id'],
        'reason': reason.values.first,
        'revision': m.data['revision'],
        'old_placement': VesselGeometry.copy(e['placement'] as Map)
      });
    });
    return true;
  }

  Future<void> elementProperties(VesselEntity e) async {
    final v = await fields(
        'Элемент',
        {
          'Обозначение': e['designation'],
          'DN, мм': '${e['nominal_dn_mm'] ?? ''}',
          'Диаметр отверстия, мм': '${e['opening_diameter_mm'] ?? ''}',
          'Крепление к сосуду': e['attachment_to_vessel'] == 'unknown'
              ? ''
              : e['attachment_to_vessel'] ?? '',
          'Присоединение к трубопроводу':
              e['end_connection'] == 'unknown' ? '' : e['end_connection'] ?? '',
          'Назначение': e['purpose'] ?? '',
          'Источник': e['source_ref'] ?? ''
        },
        hint:
            'Сварное крепление к сосуду и фланец на конце патрубка задаются отдельно. По шаблону Visio: ДУ <150 — 2 точки, ≥150 — 4. Изменение ДУ не удаляет результаты; примените рекомендуемый шаблон отдельно.');
    if (v == null) return;
    try {
      final dn = number(v['DN, мм'], positive: true),
          opening = number(v['Диаметр отверстия, мм'], positive: true);
      edit((m) {
        m.entity(e['id'])!.addAll({
          'designation': v['Обозначение'],
          'nominal_dn_mm': dn,
          'opening_diameter_mm': opening,
          'attachment_to_vessel': v['Крепление к сосуду'],
          'end_connection': v['Присоединение к трубопроводу'],
          'purpose': v['Назначение'],
          'source_ref': v['Источник']
        });
      });
    } catch (error) {
      message('$error');
    }
  }

  Future<void> addElement() async {
    var parent = g.entity(store.selection);
    if (parent == null || !g.parts.contains(parent)) {
      parent = g.entity(detail) ?? g.shells.first;
    }
    final id = parent['id'] as String;
    final kind = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (c) => SafeArea(
            child: SizedBox(
                height: 450,
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Добавить на ${parent!['designation']}')),
                  Expanded(
                      child: GridView.count(
                          crossAxisCount: 3,
                          childAspectRatio: .95,
                          children: [
                        for (final e in {...vesselLibrary, ...vesselElementNames}.entries)
                          InkWell(
                              onTap: () => Navigator.pop(c, e.key),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CustomPaint(
                                        size: const Size(34, 34),
                                        painter: _Symbol(e.key)),
                                    Text(e.value, textAlign: TextAlign.center)
                                  ]))
                      ]))
                ]))));
    if (kind != null) {
      edit((m) {
        store.selection = vesselLibrary.containsKey(kind) ? m.applyLibrary(kind, (kind.startsWith('zone_')||kind=='profile'||kind=='ring') && m.welds.any((w)=>w['id']==store.selection) ? store.selection! : id) : m.addElement(id, kind)['id'];
      });
    }
  }

  Future<bool> confirmPointArchive() async => await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Изменить число точек?'),content:const Text('Лишние точки будут архивированы. Их ID и результаты сохранятся.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Отмена')),TextButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Архивировать'))])) ?? false;

  Future<void> template(VesselEntity owner, {int? recommended}) async {
    final v = await fields(
        'Точки контроля',
        {
          'Количество':
              '${recommended ?? g.points.where((p) => p['owner_id'] == owner['id'] && p['archived'] != true).length}'
        },
        hint:
            'Вручную: 2 / 4 для штуцера, 6 для крышки, 12 для обечайки или другое число. Раскладка условная, уточните физические координаты. Уменьшение архивирует лишние точки и сохраняет их ID.');
    if (v == null) return;
    final n = int.tryParse(v.values.first);
    if (n == null || n < 0 || n > 100) {
      message('Введите целое число от 0 до 100');
      return;
    }
    final old=g.points.where((p)=>p['owner_id']==owner['id'] && p['archived']!=true).toList();
    if(n<old.length && !await confirmPointArchive()) return;
    edit((m) => m.setPointTemplate(owner['id'], n));
  }

  Future<void> addWeld(VesselEntity p) async {
    final v = await fields('Фактический продольный шов', {'Угол, °': ''},
        hint: 'Добавляйте только швы, подтверждённые паспортом или осмотром.');
    if (v == null) return;
    try {
      final a = number(v.values.first);
      if (a == null) return;
      edit((m) => m.addLongWeld(p['id'], a));
    } catch (e) {
      message('$e');
    }
  }

  Future<void> circularPattern(VesselEntity part) async {
    final v = await fields(
        'Штуцера по окружности',
        {
          'Количество': '2',
          'Радиус проекции, мм': '',
          'Первый угол, °': '0',
          'Шаг, °': '180'
        },
        hint:
            'Каждый штуцер станет самостоятельным элементом. Повторите команду с другим радиусом для второй окружности.');
    if (v == null) return;
    try {
      final n = int.tryParse(v['Количество']!);
      final r = number(v['Радиус проекции, мм']);
      final a = number(v['Первый угол, °']) ?? 0;
      final step = number(v['Шаг, °']) ?? 0;
      final diameter = (part['dimensions']['diameter_mm'] as num?)?.toDouble();
      if (n == null ||
          n < 1 ||
          n > 50 ||
          r == null ||
          diameter == null ||
          r < 0 ||
          r > diameter / 2) {
        throw const FormatException(
            'Задайте диаметр части, допустимый радиус и количество 1…50');
      }
      edit((m) {
        for (var i = 0; i < n; i++) {
          m.addElement(part['id'], 'nozzle')['placement'] = {
            'mode': 'physical',
            'radius_projection_mm': r,
            'theta_deg': (a + i * step) % 360
          };
        }
      });
    } catch (e) {
      message('$e');
    }
  }

  Future<void> section(VesselEntity owner, {required bool profile}) async {
    final v = await fields(
        profile ? 'Профиль А–А' : 'Сечение овальности',
        {
          'Обозначение': profile ? 'А–А' : 'I–I',
          if (!profile) 'От начала обечайки, мм': '',
          if (profile) 'Метод контроля (после согласования)': '',
          'Примечание': ''
        },
        hint: profile
            ? 'Пять позиций: основной металл, ЗТВ, шов, ЗТВ, основной металл. Метод и результаты не назначаются автоматически.'
            : 'Сохраняется расположение сечения. Оценка годности не выполняется без согласованной методики.');
    if (v == null) return;
    try {
      final z = number(v['От начала обечайки, мм']);
      final length = (owner['dimensions']?['length_mm'] as num?)?.toDouble();
      if (!profile && (z == null || length == null || z < 0 || z > length)) {
        throw const FormatException(
            'Задайте длину обечайки и координату внутри неё');
      }
      edit((m) => (m.data.putIfAbsent('sections', () => []) as List).add({
            'id': VesselGeometry.id(),
            'owner_id': owner['id'],
            'kind': profile ? 'weld_profile' : 'ovality',
            'designation': v['Обозначение'],
            'z_local_mm': z,
            'method': v['Метод контроля (после согласования)'],
            'note': v['Примечание'],
            if (profile)
              'positions': [
                'Основной металл',
                'ЗТВ',
                'Металл шва',
                'ЗТВ',
                'Основной металл'
              ]
          }));
    } catch (e) {
      message('$e');
    }
  }

  Future<void> zone(VesselEntity w) async {
    String method = 'УЗК', coverage = 'whole';
    final start = TextEditingController(text: '0'),
        end = TextEditingController(text: '90');
    final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, set) => AlertDialog(
                    title: Text('Контроль ${w['designation']}'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          value: method,
                          items: ['УЗК', 'МК', 'ПВК', 'ВИК']
                              .map((m) =>
                                  DropdownMenuItem(value: m, child: Text(m)))
                              .toList(),
                          onChanged: (v) => set(() => method = v!)),
                      DropdownButtonFormField<String>(
                          value: coverage,
                          items: [
                            const DropdownMenuItem(
                                value: 'whole', child: Text('Весь шов')),
                            DropdownMenuItem(
                                value: 'sector',
                                child: Text(['circumferential','attachment'].contains(w['kind'])
                                    ? 'Сектор в градусах'
                                    : 'Участок, доля 0…1'))
                          ],
                          onChanged: (v) => set(() => coverage = v!)),
                      if (coverage != 'whole') ...[
                        TextField(
                            controller: start,
                            decoration:
                                const InputDecoration(labelText: 'Начало')),
                        TextField(
                            controller: end,
                            decoration:
                                const InputDecoration(labelText: 'Конец'))
                      ],
                      const Text(
                          'Каждый метод — самостоятельная зона. 350° → 10° = 20°. Результаты не копируются между методами.'),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Отмена')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Добавить'))
                    ])));
    if (accepted != true) return;
    try {
      final a = number(start.text) ?? 0, b = number(end.text) ?? 0;
      final ring = ['circumferential','attachment'].contains(w['kind']);
      if (coverage != 'whole' &&
          ((ring && (a - b) % 360 == 0) ||
              (!ring && (a < 0 || b > 1 || a >= b)))) {
        throw const FormatException('Неверные границы участка');
      }
      edit((m) => (m.data['control_zones'] as List).add({
            'id': VesselGeometry.id(),
            'weld_id': w['id'],
            'designation': '${w['designation']} $method',
            'planned_methods': [method],
            'coverage': {
              'kind': coverage == 'whole'
                  ? 'whole'
                  : ring
                      ? 'sector'
                      : 'interval',
              'unit': ring ? 'deg' : 'fraction',
              'start': ring ? a % 360 : a,
              'end': ring ? b % 360 : b
            },
            'status': 'planned'
          }));
    } catch (e) {
      message('$e');
    }
  }

  Widget properties() {
    final e = g.entity(store.selection);
    if (e == null) {
      return const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Выберите часть, элемент или точку на чертеже.'));
    }
    final part = g.parts.contains(e),
        element = g.elements.contains(e),
        point = g.points.contains(e);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(
          e['designation']?.toString() ??
              'Точка ${e['body_number'] ?? e['local_number']}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      if (part) ...[
        if (e['kind'] == 'head' || e['kind'] == 'cover')
          TextButton(onPressed: () async {
            final values = await fields('Шов днища / крышки', {'Обозначение': 'П${g.welds.where((w) => w['kind'] != 'circumferential').length + 1}', 'От центра, мм': '0'}, hint: 'Отрицательное смещение — выше центра, положительное — ниже.');
            if (values == null) return;
            try {
              final offset = number(values['От центра, мм']) ?? 0;
              final diameter = e['dimensions']['diameter_mm'] as num?;
              if (diameter == null || offset.abs() >= diameter / 2) throw const FormatException('Задайте диаметр и смещение внутри детали.');
              edit((m) => (m.data['welds'] as List).add({'id': VesselGeometry.id(), 'kind': 'head_joint', 'designation': values['Обозначение'], 'connected_part_ids': [e['id']], 'geometry': {'offset_mm': offset}}));
            } catch (error) { message('$error'); }
          }, child: const Text('Добавить шов днища / крышки')),
        TextButton.icon(
            onPressed: () => partProperties(e),
            icon: const Icon(Icons.straighten),
            label: const Text('Размеры и источник')),
        TextButton.icon(
            onPressed: () => setState(() {
                  detail = e['id'];
                  transform.value = Matrix4.identity();
                }),
            icon: const Icon(Icons.zoom_in),
            label: const Text('Отдельный вид')),
        if (e['kind'] != 'shell')
          DropdownButtonFormField<String>(
              value: e['head_type'] ?? 'elliptical',
              decoration:
                  const InputDecoration(labelText: 'Форма днища / крышки'),
              items: const [
                DropdownMenuItem(
                    value: 'elliptical', child: Text('Эллиптическая')),
                DropdownMenuItem(
                    value: 'hemispherical', child: Text('Полусферическая')),
                DropdownMenuItem(value: 'flat', child: Text('Плоская')),
                DropdownMenuItem(value: 'conical', child: Text('Коническая'))
              ],
              onChanged: (v) =>
                  edit((m) => m.entity(e['id'])!['head_type'] = v)),
        if (e['kind'] == 'shell')
          TextButton.icon(
              onPressed: () => addWeld(e),
              icon: const Icon(Icons.add),
              label: const Text('Продольный шов')),
        if (e['kind'] == 'shell')
          TextButton(
              onPressed: () => section(e, profile: false),
              child: const Text('Сечение овальности')),
        if (e['kind'] == 'shell')
          Row(children: [
            IconButton(
                tooltip: 'Переместить к A',
                onPressed: widget.measuredPointIds.isEmpty
                    ? () => edit((m) => m.moveShell(e['id'], -1))
                    : null,
                icon: const Icon(Icons.arrow_upward)),
            IconButton(
                tooltip: 'Переместить к B',
                onPressed: widget.measuredPointIds.isEmpty
                    ? () => edit((m) => m.moveShell(e['id'], 1))
                    : null,
                icon: const Icon(Icons.arrow_downward)),
            const Expanded(child: Text('Порядок A → B')),
          ]),
        if (e['kind'] != 'shell')
          TextButton(
              onPressed: () => circularPattern(e),
              child: const Text('Штуцера по окружности')),
        if (e['kind'] == 'shell')
          TextButton(
              onPressed: () => edit((m) {
                    m.removeEmptyShell(e['id']);
                    store.selection = m.shells.first['id'];
                    detail = null;
                  }),
              child: const Text('Удалить пустую обечайку')),
        for (final w in g.welds
            .where((w) => (w['connected_part_ids'] as List).contains(e['id'])))
          ListTile(
              title: Text(w['designation']),
              subtitle: Text(w['kind'] == 'circumferential'
                  ? 'Общий кольцевой шов'
                  : w['kind'] == 'head_joint' ? 'От центра ${w['geometry']['offset_mm']} мм' : w['kind'] == 'attachment' ? 'Шов приварки элемента' : '${w['geometry']['theta_deg']}°'),
              trailing: const Icon(Icons.add_task),
              onTap: () => showModalBottomSheet(
                  context: context,
                  builder: (c) => SafeArea(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(
                            title: Text(
                                '${w['designation']}: назначить метод и участок'),
                            onTap: () {
                              Navigator.pop(c);
                              zone(w);
                            }),
                        ListTile(
                            title: const Text('Профиль А–А (5 позиций)'),
                            onTap: () {
                              Navigator.pop(c);
                              section(w, profile: true);
                            }),
                      ])))),
      ],
      if (element) ...[
        if (['nozzle','manway'].contains(e['kind']))
          TextButton(onPressed: () async {
            final found=g.welds.where((w) => w['kind']=='attachment' && w['geometry']['element_id']==e['id']);
            final weld=found.isNotEmpty ? found.first : <String,dynamic>{'id':VesselGeometry.id(),'kind':'attachment','designation':'Шов ${e['designation']}','connected_part_ids':[e['parent_id']],'geometry':{'element_id':e['id']}};
            if (found.isEmpty) edit((m) => (m.data['welds'] as List).add(weld));
            await zone(weld);
          }, child: const Text('Контроль шва приварки')),
        Text(vesselElementNames[e['kind']] ?? e['kind']),
        if(e['kind']=='nozzle') TextButton(onPressed:() {final n=VesselGeometry.recommendedNozzlePoints(e['nominal_dn_mm'] as num?);if(n==null){message('Сначала задайте ДУ в свойствах');return;}template(e,recommended:n);},child:Text('По ДУ: ${VesselGeometry.recommendedNozzlePoints(e['nominal_dn_mm'] as num?) ?? '?'} точки')),
        TextButton(
            onPressed: () => elementProperties(e),
            child: const Text('Свойства элемента')),
        if (e['kind'] == 'manway')
          TextButton(
              onPressed: () => edit((m) {
                    store.selection = m.addCover(e['id'])['id'];
                    detail = store.selection;
                  }),
              child: const Text('Открыть / создать крышку')),
      ],
      if (element || point) ...[
        Text(
            'Координаты: ${e['placement']['mode'] == 'physical' ? 'мм / градусы' : 'условные'}'),
        TextButton.icon(
            onPressed: () => coordinates(e),
            icon: const Icon(Icons.pin_drop),
            label: const Text('Точное размещение')),
        TextButton(
            onPressed: () {
              setState(() {
                move = true;
                moveLabel = false;
              });
              if (MediaQuery.sizeOf(context).width < 1000) {
                Navigator.maybePop(context);
              }
            },
            child: const Text('Переместить: нажать место')),
        TextButton(
            onPressed: () {
              setState(() {
                moveLabel = true;
                move = false;
              });
              if (MediaQuery.sizeOf(context).width < 1000) {
                Navigator.maybePop(context);
              }
            },
            child: const Text('Перенести только подпись')),
      ],
      if (part || element)
        TextButton.icon(
            onPressed: () => template(e),
            icon: const Icon(Icons.control_point_duplicate),
            label: const Text('Шаблон точек')),
      if (element)
        TextButton(
            onPressed: () => edit((m) {
                  m.entity(e['id'])!['archived'] = true;
                  for (final p
                      in m.points.where((p) => p['owner_id'] == e['id'])) {
                    p['archived'] = true;
                  }
                }),
            child: const Text('Архивировать элемент')),
      if (point) ...[
        if (widget.legacyMeasurements.isNotEmpty &&
            !widget.measuredPointIds.contains(e['id']))
          TextButton(
              onPressed: () async {
                final candidate =
                    await showModalBottomSheet<Map<String, dynamic>>(
                        context: context,
                        builder: (c) => SafeArea(
                                child: ListView(children: [
                              const ListTile(
                                  title: Text(
                                      'Связать прежнюю запись УЗТ с этой точкой')),
                              for (final row in widget.legacyMeasurements.where(
                                  (r) => !g.points.any(
                                      (p) => p['id'] == r['scheme_point_id'])))
                                ListTile(
                                    title: Text(
                                        '${row['location']} · ${row['section_number']}'),
                                    subtitle: Text(
                                        '${row['thickness'] ?? 'нет результата'} мм'),
                                    onTap: () => Navigator.pop(c, row)),
                            ])));
                if (candidate != null) {
                  edit((m) {
                    final bindings = m.data.putIfAbsent(
                            'legacy_point_bindings', () => <String, dynamic>{})
                        as Map;
                    bindings.removeWhere((k, v) =>
                        v['source_index'] == candidate['source_index']);
                    bindings[e['id']] = {
                      'source_index': candidate['source_index'],
                      'old_point_id': candidate['scheme_point_id'],
                      'source_location': candidate['location'],
                      'source_number': candidate['section_number'],
                    };
                  });
                }
              },
              child: const Text('Привязать прежнюю запись УЗТ')),
        Text(widget.measuredPointIds.contains(e['id'])
            ? 'Есть результат в таблице УЗТ'
            : 'Плановая точка. Результат вводится в таблице УЗТ.'),
        DropdownButtonFormField<String>(
            value: e['status'] ?? 'planned',
            items: const [
              DropdownMenuItem(value: 'planned', child: Text('Запланирована')),
              DropdownMenuItem(
                  value: 'inaccessible', child: Text('Недоступна')),
              DropdownMenuItem(value: 'skipped', child: Text('Пропущена'))
            ],
            onChanged: (v) async {
              final reason = v == 'planned'
                  ? <String, String>{'Причина': ''}
                  : await fields('Причина', {'Причина': ''});
              if (reason == null ||
                  (v != 'planned' && reason.values.first.isEmpty)) {
                return;
              }
              edit((m) {
                m.entity(e['id'])!['status'] = v;
                m.entity(e['id'])!['reason'] = reason.values.first;
              });
            }),
      ],
      for (final s in (g.data['sections'] as List? ?? []).where((s) =>
          s['owner_id'] == e['id'] ||
          g.welds.any((w) =>
              w['id'] == s['owner_id'] &&
              (w['connected_part_ids'] as List).contains(e['id']))))
        ListTile(
            title: Text(s['designation']),
            subtitle: Text(s['kind'] == 'weld_profile'
                ? '5 позиций · ${s['method'] ?? 'метод не задан'}'
                : 'z = ${s['z_local_mm']} мм'),
            trailing: IconButton(
                tooltip: 'Удалить сечение',
                onPressed: (s['method']?.toString().isNotEmpty ?? false)
                    ? null
                    : () => edit((m) => (m.data['sections'] as List)
                        .removeWhere((x) => x['id'] == s['id'])),
                icon: const Icon(Icons.close))),
      for (final z in g.zones.where((z) =>
          z['weld_id'] == e['id'] ||
          g.welds.any((w) =>
              w['id'] == z['weld_id'] &&
              (w['connected_part_ids'] as List).contains(e['id']))))
        ListTile(
            title: Text(z['designation']),
            subtitle: Text(
                '${z['coverage']['kind']} ${z['coverage']['start']} → ${z['coverage']['end']}'),
            trailing: IconButton(
                tooltip: 'Удалить план зоны',
                onPressed: widget.measuredZoneIds.contains(z['id'])
                    ? null
                    : () => edit((m) => (m.data['control_zones'] as List)
                        .removeWhere((x) => x['id'] == z['id'])),
                icon: const Icon(Icons.close))),
    ]);
  }

  Widget tree() => ListView(children: [
        ListTile(
            title: const Text('Весь сосуд'),
            leading: const Icon(Icons.view_agenda),
            onTap: () => setState(() => detail = null)),
        for (final p in g.parts)
          ExpansionTile(
              key: ValueKey(p['id']),
              initiallyExpanded: p['id'] == store.selection,
              title: Text(p['designation'],
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              leading: Icon(p['kind'] == 'shell'
                  ? Icons.view_day
                  : Icons.circle_outlined),
              trailing: IconButton(
                  tooltip: 'Выбрать часть',
                  onPressed: () => select(p['id']),
                  icon: Icon(store.selection == p['id']
                      ? Icons.check_circle
                      : Icons.touch_app)),
              children: [
                for (final e in g.elements.where(
                    (e) => e['parent_id'] == p['id'] && e['archived'] != true))
                  ListTile(
                      dense: true,
                      title: Text(e['designation']),
                      selected: store.selection == e['id'],
                      onTap: () => select(e['id'])),
              ]),
        ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Добавить обечайку'),
            onTap: () => edit((m) {
                  store.selection = m.addShell()['id'];
                })),
      ]);
  void select(String id) {
    setState(() => store.selection = id);
    store.changed();
  }

  Future<void> tap(Offset at, VesselDrawingLayout layout) async {
    final e = g.entity(store.selection);
    if (moveLabel && e != null && layout.marks[e['id']] != null) {
      final delta = at - layout.marks[e['id']]!;
      edit((m) => m.labels[e['id']] = {'dx': delta.dx, 'dy': delta.dy});
      setState(() => moveLabel = false);
      return;
    }
    if (move && e != null) {
      final owner = g.entity(e['parent_id'] ?? e['owner_id']);
      final r = layout.parts[owner?['id']];
      if (r == null || !r.contains(at)) {
        message('Выберите место внутри части-владельца');
        return;
      }
      var u = (at.dx - r.left) / r.width, v = (at.dy - r.top) / r.height;
      if (owner?['kind'] == 'shell' && g.data['orientation'] != 'horizontal') {
        final t = u;
        u = v;
        v = t;
      }
      if (owner?['kind'] != 'shell' && (Offset(u - .5, v - .5).distance > .5)) {
        message('Выберите место внутри контура');
        return;
      }
      if (exteriorB && owner?['side'] == 'B') u = 1 - u;
      if (!await allowPhysicalMove(e)) return;
      edit((m) => m.entity(e['id'])!['placement'] = {
            'mode': 'schematic',
            'u': u,
            'v': v
          });
      setState(() => move = false);
      return;
    }
    final hits = layout.hit(at);
    if (hits.isEmpty) return;
    String? id = hits.first;
    if (hits.length > 1) {
      id = await showModalBottomSheet<String>(
          context: context,
          builder: (c) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final h in hits)
                  ListTile(
                      title: Text(g.entity(h)?['designation'] ??
                          'Точка ${g.entity(h)?['body_number'] ?? g.entity(h)?['local_number']}'),
                      onTap: () => Navigator.pop(c, h))
              ])));
    }
    if (id != null) select(id);
  }

  Future<List<int>> png(
      {String? part, String? drawingLayer, Map? section}) async {
    final size = vesselSheetSize(g);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(1.5);
    if (section != null) {
      paintVesselSection(canvas, size, g, section);
    } else {
      VesselDrawingPainter(
              VesselDrawingLayout(g, size, detail: part, exteriorB: exteriorB),
              layer: drawingLayer ?? layer)
          .paint(canvas, size);
    }
    final pic = recorder.endRecording();
    final image = await pic.toImage((size.width*1.5).round(), (size.height*1.5).round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    pic.dispose();
    return bytes!.buffer.asUint8List();
  }

  Future<void> exportPdf() async {
    setState(() => busy = true);
    try {
      final doc = pw.Document();
      final font = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      final base=vesselPaper(g)=='A3'?PdfPageFormat.a3:PdfPageFormat.a4;
      final format=g.data['orientation']=='horizontal'?base.landscape:base;
      final details=(g.data['print_settings']?['detail_ids'] as List? ?? []).where((id)=>g.parts.any((p)=>p['id']==id));
      for(final id in [null,...details]) {
        doc.addPage(pw.Page(pageFormat:format,margin:const pw.EdgeInsets.all(12),
          build:(_)=>pw.Center(child:pw.SvgImage(svg:exportVesselSvg(g,detail:id),customFontLookup:(_,__,___)=>font))));
      }
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      message('Не удалось сформировать PDF: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> exportSvg() async {
    try {
      await FilePicker.platform.saveFile(
          dialogTitle: 'Сохранить векторный чертёж',
          fileName: 'vessel_${g.data['revision']}.svg',
          bytes: Uint8List.fromList(utf8.encode(exportVesselSvg(g,
              detail: detail, layer: layer, exteriorB: exteriorB))));
    } catch (e) {
      message('Не удалось сохранить SVG: $e');
    }
  }

  Future<void> apply() async {
    setState(() => busy = true);
    try {
      g.validateForSave();
      await store.flush();
      if (store.saveStatus.startsWith('Не удалось')) {
        throw StateError(store.saveStatus);
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/vessel_${g.data['model_id']}_${g.data['revision']}.png');
      await file.writeAsBytes(await png(drawingLayer: 'Все'), flush: true);
      final views = g.data['views'] as List;
      views.removeWhere((v) => v['kind'] == 'part_detail');
      for (final part in g.parts) {
        final detailFile = File(
            '${dir.path}/vessel_${g.data['model_id']}_${part['id']}_${g.data['revision']}.png');
        await detailFile.writeAsBytes(
            await png(part: part['id'], drawingLayer: 'Все'),
            flush: true);
        views.add({
          'id': VesselGeometry.id(),
          'kind': 'part_detail',
          'part_ids': [part['id']],
          'designation': part['designation'],
          'image_path': detailFile.path,
          'revision': g.data['revision']
        });
      }
      views.removeWhere((v) => v['kind'] == 'section_detail');
      for (final section in (g.data['sections'] as List? ?? [])
          .where((s) => s['kind'] == 'weld_profile')) {
        final sectionFile = File(
            '${dir.path}/vessel_section_${section['id']}_${g.data['revision']}.png');
        await sectionFile.writeAsBytes(await png(section: section),
            flush: true);
        views.add({
          'id': VesselGeometry.id(),
          'kind': 'section_detail',
          'part_ids': [section['id']],
          'designation': section['designation'],
          'image_path': sectionFile.path,
          'revision': g.data['revision']
        });
      }
      g.data['equipment_kind'] = widget.equipmentKind;
      g.data['base_revision'] = widget.initialGeometry?['revision'] ?? 0;
      g.data['operation_id'] = VesselGeometry.id();
      g.data['form_id'] = widget.formId;
      if (mounted) {
        setState(() => allowPop = true);
        Navigator.pop(
            context,
            VesselSchemeConstructorResult(
                imagePath: file.path,
                geometry: VesselGeometry.copy(g.data),
                orientation: g.data['orientation'],
                equipmentKind: widget.equipmentKind,
                formId: widget.formId));
      }
    } catch (e) {
      message('Схема не применена: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) leave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Конструктор сосуда'), actions: [
          IconButton(
              tooltip: 'Отменить',
              onPressed: store.canUndo ? store.undo : null,
              icon: const Icon(Icons.undo)),
          IconButton(
              tooltip: 'Повторить',
              onPressed: store.canRedo ? store.redo : null,
              icon: const Icon(Icons.redo))
        ]),
        body: !ready
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (var i = 0; i < steps.length; i++)
                        Padding(
                            padding: const EdgeInsets.all(4),
                            child: ChoiceChip(
                                label: Text('${i + 1}. ${steps[i]}'),
                                selected: store.step == i,
                                onSelected: (_) {
                                  setState(() => store.step = i);
                                  store.changed();
                                }))
                    ])),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Expanded(
                          child: Text(store.saveStatus,
                              style: const TextStyle(fontSize: 12))),
                      Text('Рев. ${g.data['revision']}')
                    ])),
                if (store.step == 0)
                  Wrap(spacing: 8, children: [
                    TextButton.icon(onPressed: loadVisioExample,
                        icon: const Icon(Icons.schema_outlined), label: const Text('Пример Visio · 6 обечаек')),
                    TextButton(
                        onPressed: base,
                        child: const Text('Источник и отсчёт углов')),
                    TextButton(
                        onPressed: () => edit((m) => m.data['orientation'] =
                            m.data['orientation'] == 'horizontal'
                                ? 'vertical'
                                : 'horizontal'),
                        child: Text(g.data['orientation'] == 'horizontal'
                            ? 'Горизонтальный'
                            : 'Вертикальный'))
                  ]),
                if (store.step == 1)
                  TextButton.icon(
                      onPressed: () => edit((m) {
                            store.selection = m.addShell()['id'];
                          }),
                      icon: const Icon(Icons.add),
                      label: Text('Обечаек: ${g.shells.length} · добавить')),
                if (store.step == 3)
                  Wrap(children: [
                    TextButton(
                        onPressed: () => edit((m) {
                              for (final s in m.shells) {
                                m.setPointTemplate(s['id'], 12);
                              }
                            }),
                        child: const Text('По 12 точек на обечайку')),
                    Text(
                        '${g.points.where((p) => p['archived'] != true).length} точек (план)')
                  ]),
                if (store.step == 4)
                  Wrap(children:[DropdownButton<String>(value:g.data['print_settings']?['paper'] ?? 'auto',items:const [DropdownMenuItem(value:'auto',child:Text('Лист: автоматически')),DropdownMenuItem(value:'A4',child:Text('А4')),DropdownMenuItem(value:'A3',child:Text('А3'))],onChanged:(v)=>edit((m)=>(m.data.putIfAbsent('print_settings',()=> <String,dynamic>{}) as Map)['paper']=v)),Text('${vesselPaper(g)} · ${g.data['orientation']=='horizontal'?'альбомный':'книжный'} · общая схема')]),
                if (store.step == 4)
                  SizedBox(
                      height: 110,
                      child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: g
                              .diagnostics()
                              .map((s) => Text('• $s',
                                  style: const TextStyle(fontSize: 12)))
                              .toList())),
                if (move || moveLabel)
                  MaterialBanner(
                      content: Text(moveLabel
                          ? 'Нажмите новое место подписи'
                          : 'Нажмите новое место элемента. Координаты станут условными.'),
                      actions: [
                        TextButton(
                            onPressed: () => setState(() {
                                  move = false;
                                  moveLabel = false;
                                }),
                            child: const Text('Отмена'))
                      ]),
                Expanded(child: LayoutBuilder(builder: (c, constraints) {
                  final tablet = constraints.maxWidth >= 1000;
                  return Row(children: [
                    if (tablet) SizedBox(width: 220, child: tree()),
                    Expanded(
                        child: Column(children: [
                      Row(children: [
                        if (!tablet)
                          IconButton(
                              tooltip: 'Части сосуда',
                              icon: const Icon(Icons.account_tree),
                              onPressed: () => showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => SafeArea(
                                      child: SizedBox(
                                          height: 500, child: tree())))),
                        Expanded(
                            child: Text(
                                detail == null
                                    ? 'Общий вид'
                                    : g.entity(detail)?['designation'] ?? '',
                                overflow: TextOverflow.ellipsis)),
                        if (detail != null)
                          IconButton(
                              tooltip: 'Общий вид',
                              onPressed: () => setState(() => detail = null),
                              icon: const Icon(Icons.close)),
                        PopupMenuButton<String>(
                            tooltip: 'Слой контроля',
                            initialValue: layer,
                            onSelected: (v) => setState(() => layer = v),
                            itemBuilder: (_) => [
                                  'Все',
                                  'УЗТ',
                                  'УЗК',
                                  'МК',
                                  'ПВК',
                                  'ВИК'
                                ]
                                    .map((s) =>
                                        PopupMenuItem(value: s, child: Text(s)))
                                    .toList(),
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(layer))),
                        IconButton(
                            tooltip: 'Днище B с внешней стороны',
                            onPressed: () =>
                                setState(() => exteriorB = !exteriorB),
                            icon: Icon(
                                exteriorB ? Icons.flip : Icons.flip_outlined)),
                      ]),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton(tooltip: 'Уменьшить', icon: const Icon(Icons.zoom_out), onPressed: () {
                          if (transform.value.getMaxScaleOnAxis() > .4) transform.value = transform.value.clone()..scale(1 / 1.4);
                        }),
                        TextButton(onPressed: () => transform.value = Matrix4.identity(), child: const Text('Весь лист')),
                        IconButton(tooltip: 'Увеличить', icon: const Icon(Icons.zoom_in), onPressed: () {
                          if (transform.value.getMaxScaleOnAxis() < 4) transform.value = transform.value.clone()..scale(1.4);
                        }),
                      ]),
                      Expanded(child: LayoutBuilder(builder: (_, box) {
                        // One engineering sheet in every viewport; never distort the drawing on phones.
                        final size = vesselSheetSize(g);
                        final drawing = VesselDrawingLayout(g, size,
                            detail: detail, exteriorB: exteriorB);
                        return ClipRect(
                            child: InteractiveViewer(
                                transformationController: transform,
                                minScale: .25,
                                maxScale: 5,
                                child: FittedBox(
                                    child: GestureDetector(
                                        onTapUp: (d) =>
                                            tap(d.localPosition, drawing),
                                        child: CustomPaint(
                                            size: size,
                                            painter: VesselDrawingPainter(
                                                drawing,
                                                selection: store.selection,
                                                layer: layer))))));
                      })),
                    ])),
                    if (tablet) SizedBox(width: 280, child: properties()),
                  ]);
                })),
              ]),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                    alignment: WrapAlignment.spaceAround,
                    spacing: 6,
                    children: [
                      OutlinedButton.icon(
                          onPressed: busy ? null : addElement,
                          icon: const Icon(Icons.add),
                          label: const Text('Элемент')),
                      OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => SafeArea(
                                      child: SizedBox(
                                          height: MediaQuery.sizeOf(context)
                                                  .height *
                                              .72,
                                          child: AnimatedBuilder(
                                              animation: store,
                                              builder: (_, __) =>
                                                  properties())))),
                          child: const Text('Свойства')),
                      if (store.step == 4)
                        OutlinedButton(
                            onPressed: busy ? null : exportPdf,
                            child: Text('PDF ${vesselPaper(g)}')),
                      if (store.step == 4)
                        OutlinedButton(
                            onPressed: busy ? null : exportSvg,
                            child: const Text('SVG')),
                      FilledButton(
                          onPressed: busy
                              ? null
                              : store.step == 4
                                  ? apply
                                  : () {
                                      setState(() => store.step++);
                                      store.changed();
                                    },
                          child: Text(busy
                              ? 'Подождите…'
                              : store.step == 4
                                  ? 'Применить'
                                  : 'Далее')),
                    ]))),
      ));
}

class _Symbol extends CustomPainter {
  final String kind;
  _Symbol(this.kind);
  @override
  void paint(Canvas canvas, Size size) {
    final center=Offset(size.width/2,size.height/2),ink=Paint()..color=Colors.black..style=PaintingStyle.stroke;
    if(kind=='profile'){paintWeldProfile(canvas,Offset.zero,32,scale:.22);return;}
    if(kind=='support'){canvas.drawRect(Rect.fromCenter(center:center,width:8,height:30),ink);return;}
    if(kind=='point'){canvas.drawLine(center-const Offset(4,4),center+const Offset(4,4),ink);canvas.drawLine(center+const Offset(-4,4),center+const Offset(4,-4),ink);return;}
    if(kind=='ring'||kind=='longitudinal'||kind.startsWith('zone_')) {final vertical=kind.contains('ring');canvas.drawLine(center-(vertical?const Offset(0,14):const Offset(14,0)),center+(vertical?const Offset(0,14):const Offset(14,0)),ink);if(kind.startsWith('zone_'))canvas.drawRect(Rect.fromCenter(center:center,width:vertical?8:22,height:vertical?22:8),ink);return;}
    paintVesselElement(canvas,center,kind.startsWith('nozzle_')||kind=='cover'?'nozzle':kind,engineering:true);
    if(kind.startsWith('nozzle_')&&kind!='nozzle_none') {
      canvas.drawCircle(center,13,ink);
      for(final offset in [const Offset(-10,0),const Offset(10,0),if(!kind.contains('small'))const Offset(0,-10),if(!kind.contains('small'))const Offset(0,10)])canvas.drawCircle(center+offset,2,Paint()..color=Colors.black);
      if(kind.endsWith('combined'))canvas.drawCircle(center,15,ink..strokeWidth=2);
    }
  }
  @override
  bool shouldRepaint(covariant _Symbol oldDelegate) => false;
}
