import '../models/vessel_library.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, LogicalKeyboardKey;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import '../models/vessel_geometry.dart';
import '../models/vessel_editor_tools.dart';
import '../models/vessel_merge.dart';
import '../services/vessel_constructor_store.dart';
import '../services/vessel_svg_export.dart';
import '../widgets/vessel_drawing.dart';
import '../widgets/vessel_editor_canvas.dart';
import '../widgets/vessel_elements_editor.dart';
import 'vessel_scheme_constructor_screen.dart'
    show VesselSchemeConstructorResult;

String _conflictSectionName(String key) =>
    const {
      'parts': 'Детали сосуда',
      'elements': 'Элементы',
      'welds': 'Швы',
      'control_points': 'Точки контроля',
      'control_zones': 'Участки контроля',
      'sections': 'Сечения',
      'orientation': 'Ориентация',
      'views': 'Виды чертежа',
      'print_settings': 'Настройки печати',
    }[key] ??
    'Параметры схемы ($key)';

String _conflictDescription(dynamic value, dynamic other) {
  if (value == null) return 'Удалено в этой версии';
  if (value is! Map)
    return value is List ? 'Записей: ${value.length}' : '$value';
  const labels = {
    'designation': 'Обозначение',
    'length_mm': 'Длина, мм',
    'diameter_mm': 'Диаметр, мм',
    'thickness_mm': 'Толщина, мм',
    'z_local_mm': 'От начала детали, мм',
    'radius_projection_mm': 'Радиус проекции, мм',
    'theta_deg': 'Угол, °',
    'mode': 'Режим координат',
    'nominal_dn_mm': 'ДУ',
    'dimensions': 'Размеры',
    'placement': 'Размещение',
    'archived': 'В архиве',
    'kind': 'Тип',
    'physical': 'точный',
    'schematic': 'условный',
  };
  final comparison = other is Map ? other : const {};
  final lines = <String>[
    if (value['designation'] != null) '${value['designation']}'
  ];
  for (final key in {...value.keys, ...comparison.keys}) {
    if (key == 'id' ||
        key == 'designation' ||
        VesselMerge.same(value[key], comparison[key])) continue;
    final current = value[key];
    final rendered = current is Map
        ? current.entries
            .map((entry) =>
                '${labels[entry.key] ?? entry.key}: ${labels[entry.value] ?? entry.value}')
            .join(', ')
        : current is List
            ? current.join(', ')
            : labels[current] ?? current ?? 'не задано';
    lines.add('${labels[key] ?? key}: $rendered');
  }
  return lines.isEmpty ? 'Параметры совпадают' : lines.join('\n');
}

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
  final search = ValueNotifier<String>('');
  final searchInput = TextEditingController();
  bool grid = false, snap = false, snapWelds = false, ruler = false;
  int gridDivisions = 20;
  final hiddenLayers = <String>{};
  Map<String, dynamic>? copiedProperties, copiedPlacement;
  String? copiedPlacementOwner;
  bool move = false,
      moveLabel = false,
      exteriorB = false,
      busy = false,
      ready = false,
      allowPop = false;
  final transform = TransformationController();
  final canvasKey = GlobalKey<VesselEditorCanvasState>();
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
          if (baseline is Map &&
              baseline['model_id'] == g.data['model_id'] &&
              baseline['revision'] != g.data['revision']) {
            final comparison =
                VesselMerge(Map<String, dynamic>.from(baseline), local, g.data);
            while (comparison.conflicts.isNotEmpty && mounted) {
              if (!mounted) return;
              final conflict = comparison.conflicts.first;
              final choice = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (c) => AlertDialog(
                          title: const Text('Изменения одной и той же детали'),
                          content: SingleChildScrollView(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(_conflictSectionName(conflict.key)),
                                const Text('Мой черновик',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                Text(_conflictDescription(
                                    conflict.local, conflict.remote)),
                                const Divider(),
                                const Text('Применённая версия',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                Text(_conflictDescription(
                                    conflict.remote, conflict.local)),
                              ])),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Применённая')),
                            FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Мой черновик'))
                          ]));
              if (choice == null) return;
              comparison.choose(conflict, choice);
            }
            store.restore({...draft, 'geometry': comparison.merged});
            message(
                'Независимые изменения объединены. Проверьте схему перед применением.');
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
    search.dispose();
    searchInput.dispose();
    super.dispose();
  }

  void message(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> rename(VesselEntity e) async {
    if (g.points.contains(e)) {
      message('Номер точки задаётся её положением в плане контроля');
      return;
    }
    if (e['locked'] == true) {
      message('Сначала снимите блокировку объекта');
      return;
    }
    final result = await fields(
        'Переименовать объект', {'Обозначение': '${e['designation'] ?? ''}'});
    if (result == null || result.values.first.isEmpty) return;
    edit((m) => m.entity(e['id'])!['designation'] = result.values.first);
  }

  Future<void> note(VesselEntity e) async {
    final result = await fields(
        'Заметка к объекту', {'Текст': '${e['editor_note'] ?? ''}'});
    if (result != null)
      edit((m) => m.entity(e['id'])!['editor_note'] = result.values.first);
  }

  Future<void> moveObject(String id, Map<String, dynamic> placement) async {
    final e = g.entity(id);
    if (e == null ||
        e['locked'] == true ||
        !await allowPhysicalMove(e) ||
        !mounted) return;
    edit((m) => VesselEditorTools.move(m, id, placement));
  }

  Future<void> placementAction(
      void Function(VesselGeometry, String) action) async {
    final id = store.selection, e = g.entity(store.selection);
    if (id == null || e == null || !VesselEditorTools.movable(g, e)) {
      message('Выберите незаблокированный элемент, точку или продольный шов');
      return;
    }
    if (!await allowPhysicalMove(e) || !mounted) return;
    edit((m) => action(m, id));
  }

  void duplicateSelection() {
    final id = store.selection;
    if (id != null)
      edit((m) => store.selection = VesselEditorTools.duplicate(m, id));
  }

  void keyboardShift(double dx, double dy) {
    final e = g.entity(store.selection),
        owner = g.entity(e?['parent_id'] ?? e?['owner_id']);
    final vertical =
        (owner?['kind'] == 'shell' || e?['kind'] == 'longitudinal') &&
            g.data['orientation'] != 'horizontal';
    placementAction((m, id) => VesselEditorTools.shift(
        m,
        id,
        (vertical ? dy : dx) / gridDivisions,
        (vertical ? dx : dy) / gridDivisions));
  }

  Future<void> relativeCoordinates(VesselEntity e) async {
    final p = g.position(e);
    final values = await fields(
        'Координаты в пределах детали',
        {
          'Вдоль детали, %': (p.x * 100).toStringAsFixed(2),
          'Поперёк детали, %': (p.y * 100).toStringAsFixed(2)
        },
        hint:
            '0–100%. На днище — координаты внутри круга. При точном режиме сохраняются миллиметры и угол.');
    if (values == null) return;
    try {
      final u = number(values.values.first), v = number(values.values.last);
      if (u == null || v == null)
        throw const FormatException('Введите обе координаты');
      await moveObject(
          e['id'], VesselEditorTools.unitPlacement(g, e, u / 100, v / 100));
    } catch (error) {
      message('$error');
    }
  }

  void focusSelection() {
    final id = store.selection;
    if (id == null) return;
    final e = g.entity(id);
    setState(() {
      if (e != null &&
          detail != null &&
          detail != id &&
          detail != e['parent_id'] &&
          detail != e['owner_id']) detail = null;
      hiddenLayers.clear();
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => canvasKey.currentState?.focusObject(id));
  }

  Future<void> showTools() => showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (panelContext) =>
          StatefulBuilder(builder: (context, updatePanel) {
            void view(VoidCallback update) {
              setState(update);
              updatePanel(() {});
            }

            void close() => Navigator.pop(panelContext);
            return Dialog.fullscreen(
                child: Scaffold(
                    appBar: AppBar(
                        title: const Text('Инструменты чертежа'),
                        leading: IconButton(
                            tooltip: 'Закрыть инструменты',
                            icon: const Icon(Icons.close),
                            onPressed: close)),
                    body: AnimatedBuilder(
                        animation: store,
                        builder: (_, __) {
                          final e = g.entity(store.selection),
                              id = store.selection;
                          Widget button(String label, VoidCallback? action) =>
                              OutlinedButton(
                                  onPressed: action, child: Text(label));
                          return ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                const Text('Вид и привязки',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18)),
                                SwitchListTile(
                                    title: const Text('Сетка'),
                                    value: grid,
                                    onChanged: (v) => view(() => grid = v)),
                                DropdownButtonFormField<int>(
                                    initialValue: gridDivisions,
                                    decoration: const InputDecoration(
                                        labelText: 'Делений сетки на деталь'),
                                    items: [10, 20, 40, 100]
                                        .map((n) => DropdownMenuItem(
                                            value: n, child: Text('$n')))
                                        .toList(),
                                    onChanged: (v) =>
                                        view(() => gridDivisions = v!)),
                                SwitchListTile(
                                    title: const Text('Привязка к сетке'),
                                    subtitle: const Text('При перетаскивании'),
                                    value: snap,
                                    onChanged: (v) => view(() => snap = v)),
                                SwitchListTile(
                                    title: const Text('Привязка к швам'),
                                    subtitle: const Text(
                                        'Элементы и точки притягиваются к ближайшей линии шва'),
                                    value: snapWelds,
                                    onChanged: (v) =>
                                        view(() => snapWelds = v)),
                                const Text(
                                    'Слои на экране · экспорт содержит полную схему'),
                                Wrap(spacing: 8, children: [
                                  for (final name in [
                                    'Элементы',
                                    'Швы',
                                    'Точки',
                                    'Зоны'
                                  ])
                                    FilterChip(
                                        label: Text(name),
                                        selected: !hiddenLayers.contains(name),
                                        onSelected: (v) => view(() {
                                              v
                                                  ? hiddenLayers.remove(name)
                                                  : hiddenLayers.add(name);
                                            }))
                                ]),
                                Wrap(spacing: 8, children: [
                                  button('Найти и выбрать объект', () {
                                    close();
                                    showObjectList();
                                  }),
                                  button(
                                      'Показать выбранный крупно',
                                      id == null
                                          ? null
                                          : () {
                                              close();
                                              focusSelection();
                                            }),
                                  button(
                                      ruler ? 'Выключить линейку' : 'Линейка',
                                      () {
                                    view(() => ruler = !ruler);
                                    close();
                                  })
                                ]),
                                const Divider(height: 24),
                                Text(
                                    e == null
                                        ? 'Выберите объект на схеме'
                                        : 'Выбрано: ${e['designation'] ?? 'точка ${e['local_number']}'}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                if (e != null) ...[
                                  Wrap(spacing: 8, children: [
                                    button('Переименовать', () => rename(e)),
                                    button('Заметка', () => note(e)),
                                    button(
                                        e['locked'] == true
                                            ? 'Разблокировать'
                                            : 'Заблокировать',
                                        () => edit((m) =>
                                            m.entity(id)!['locked'] =
                                                e['locked'] != true)),
                                    if (g.elements.contains(e))
                                      button('Дублировать элемент',
                                          duplicateSelection),
                                    if (g.elements.contains(e))
                                      button('Копировать свойства', () {
                                        copiedProperties =
                                            VesselEditorTools.copyProperties(e);
                                        updatePanel(() {});
                                      }),
                                    if (g.elements.contains(e))
                                      button(
                                          'Вставить свойства',
                                          copiedProperties == null ||
                                                  e['locked'] == true
                                              ? null
                                              : () => edit((m) =>
                                                  VesselEditorTools
                                                      .pasteProperties(m, id!,
                                                          copiedProperties!))),
                                  ]),
                                  if (e['placement'] is Map) ...[
                                    button(
                                        'Координаты в процентах',
                                        e['locked'] == true
                                            ? null
                                            : () => relativeCoordinates(e)),
                                    Wrap(spacing: 8, children: [
                                      button('Копировать размещение', () {
                                        copiedPlacement =
                                            VesselGeometry.copy(e['placement']);
                                        copiedPlacementOwner =
                                            e['parent_id'] ?? e['owner_id'];
                                        updatePanel(() {});
                                      }),
                                      button(
                                          'Вставить размещение',
                                          copiedPlacement == null ||
                                                  copiedPlacementOwner !=
                                                      (e['parent_id'] ??
                                                          e['owner_id']) ||
                                                  e['locked'] == true
                                              ? null
                                              : () => moveObject(
                                                  id!, copiedPlacement!)),
                                      button(
                                          'Середина вдоль детали',
                                          () => placementAction((m, id) =>
                                              VesselEditorTools.align(m, id))),
                                      button(
                                          'Середина поперёк детали',
                                          () => placementAction((m, id) =>
                                              VesselEditorTools.align(m, id,
                                                  axial: false))),
                                      button(
                                          'Зеркально вдоль',
                                          () => placementAction((m, id) =>
                                              VesselEditorTools.mirror(m, id))),
                                      button(
                                          'Зеркально поперёк',
                                          () => placementAction((m, id) =>
                                              VesselEditorTools.mirror(m, id,
                                                  axial: false))),
                                    ]),
                                  ],
                                  if (VesselEditorTools.movable(g, e)) ...[
                                    const Text(
                                        'Сдвиг на одно деление сетки: вдоль / поперёк детали'),
                                    Wrap(spacing: 8, children: [
                                      for (final d in [
                                        (-1.0, 0.0, 'Вдоль −'),
                                        (1.0, 0.0, 'Вдоль +'),
                                        (0.0, -1.0, 'Поперёк −'),
                                        (0.0, 1.0, 'Поперёк +')
                                      ])
                                        button(
                                            d.$3,
                                            () => placementAction((m, id) =>
                                                VesselEditorTools.shift(
                                                    m,
                                                    id,
                                                    d.$1 / gridDivisions,
                                                    d.$2 / gridDivisions))),
                                      button(
                                          'Повернуть −15°',
                                          () => placementAction((m, id) =>
                                              VesselEditorTools.rotate(
                                                  m, id, -15))),
                                      button(
                                          'Повернуть +15°',
                                          () => placementAction((m, id) =>
                                              VesselEditorTools.rotate(
                                                  m, id, 15))),
                                    ]),
                                  ],
                                ],
                                const Divider(height: 24),
                                const Text('Проверка схемы',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18)),
                                if (g.diagnostics().isEmpty)
                                  const ListTile(
                                      leading: Icon(Icons.check_circle),
                                      title: Text(
                                          'Замечаний к составу схемы нет')),
                                for (final diagnostic in g.diagnostics())
                                  ListTile(
                                      leading: const Icon(Icons.warning_amber),
                                      title: Text(diagnostic),
                                      onTap: () {
                                        final found = g.parts
                                            .where((p) => diagnostic.startsWith(
                                                '${p['designation']}:'))
                                            .firstOrNull;
                                        if (found != null) select(found['id']);
                                        close();
                                        if (found != null) focusSelection();
                                      }),
                                const Divider(height: 24),
                                const Text('Архив элементов',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18)),
                                for (final item in g.elements
                                    .where((e) => e['archived'] == true))
                                  ListTile(
                                      title: Text('${item['designation']}'),
                                      trailing: TextButton(
                                          onPressed: () => edit((m) =>
                                              VesselEditorTools.archive(
                                                  m, item['id'], false)),
                                          child: const Text('Восстановить'))),
                                if (!g.elements
                                    .any((e) => e['archived'] == true))
                                  const Text('Архив пуст'),
                                const Divider(height: 24),
                                const Text(
                                    'Клавиатура: Ctrl+Z — отменить; Ctrl+Y / Ctrl+Shift+Z — повторить; Ctrl+D — дублировать; стрелки — сдвиг; Esc — отменить режим.\nРезультаты измерений при дублировании не копируются. Линейка измеряет развёртку / проекцию по заданным размерам.'),
                              ]);
                        })));
          }));

  Future<void> showObjectList() => showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (c) => Dialog.fullscreen(
          child: Scaffold(
              appBar: AppBar(
                  title: const Text('Объекты чертежа'),
                  leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(c))),
              body: tree(closePanel: () => Navigator.pop(c)))));

  Future<void> showPrintSettings() => showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (c) => Dialog.fullscreen(
          child: Scaffold(
              appBar: AppBar(
                  title: const Text('Параметры печати'),
                  leading: IconButton(
                      tooltip: 'Закрыть параметры печати',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(c))),
              body: AnimatedBuilder(
                  animation: store,
                  builder: (_, __) =>
                      ListView(padding: const EdgeInsets.all(16), children: [
                        DropdownButtonFormField<String>(
                            initialValue:
                                g.data['print_settings']?['paper'] ?? 'auto',
                            decoration: const InputDecoration(
                                labelText: 'Размер листа'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'auto', child: Text('Автоматически')),
                              DropdownMenuItem(value: 'A4', child: Text('А4')),
                              DropdownMenuItem(value: 'A3', child: Text('А3'))
                            ],
                            onChanged: (v) => edit((m) => (m.data.putIfAbsent(
                                    'print_settings', () => <String, dynamic>{})
                                as Map)['paper'] = v)),
                        SwitchListTile(
                            title: const Text('Размерные выноски'),
                            subtitle:
                                const Text('Координаты — на детальных видах'),
                            value: g.data['print_settings']
                                    ?['show_dimensions'] !=
                                false,
                            onChanged: (v) => edit((m) => (m.data.putIfAbsent(
                                    'print_settings', () => <String, dynamic>{})
                                as Map)['show_dimensions'] = v)),
                        const Text('Дополнительные листы деталей'),
                        for (final part in g.parts)
                          CheckboxListTile(
                              title: Text('Лист: ${part['designation']}'),
                              value: (g.data['print_settings']?['detail_ids']
                                          as List? ??
                                      [])
                                  .contains(part['id']),
                              onChanged: (v) => edit((m) {
                                    final settings = m.data.putIfAbsent(
                                        'print_settings',
                                        () => <String, dynamic>{}) as Map;
                                    final ids = List<String>.from(
                                        settings['detail_ids'] as List? ?? []);
                                    ids.remove(part['id']);
                                    if (v == true) ids.add(part['id']);
                                    settings['detail_ids'] = ids;
                                  })),
                        const Divider(),
                        const Text('Перед применением'),
                        for (final message in g.diagnostics())
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text('• $message')),
                      ])))));

  void edit(void Function(VesselGeometry) action) {
    try {
      store.command((m) {
        final locked = [...m.parts, ...m.elements, ...m.welds, ...m.points]
            .where((e) => e['locked'] == true)
            .map(VesselGeometry.copy)
            .toList();
        action(m);
        for (final before in locked) {
          final after = m.entity(before['id']);
          if (after == null)
            throw StateError('Заблокированный объект нельзя удалить');
          if (after['locked'] != true) continue;
          final a = VesselGeometry.copy(before)..remove('editor_note');
          final b = VesselGeometry.copy(after)..remove('editor_note');
          if (json.encode(a) != json.encode(b))
            throw StateError('Сначала снимите блокировку объекта');
        }
        m.orientHeadNames();
      });
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
    if (widget.measuredPointIds.isNotEmpty ||
        widget.measuredZoneIds.isNotEmpty) {
      message(
          'В обследовании уже есть результаты. Откройте пример в новом обследовании.');
      return;
    }
    final use = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Пример по Visio'),
                content: const Text(
                    '6 обечаек, 2 днища, крышка люка Т, 25 элементов и 138 точек. Размеры учебные. Заменить текущую схему? Изменение можно отменить.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Загрузить схему'))
                ]));
    if (use != true) return;
    try {
      final raw = jsonDecode(await rootBundle.loadString(
          'assets/data/visio_vessel_example.json')) as Map<String, dynamic>;
      final example = VesselGeometry.fromExample(raw);
      edit((m) {
        store.geometry = example;
      });
      setState(() {
        detail = null;
        store.selection = g.shells.first['id'];
      });
      transform.value = Matrix4.identity();
      message(
          'Пример загружен. Выберите деталь на чертеже или в списке и измените её параметры.');
    } catch (e) {
      message('Не удалось загрузить пример: $e');
    }
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
    final rings = shell
        ? g.welds
            .where((w) =>
                w['kind'] == 'circumferential' &&
                (w['connected_part_ids'] as List).contains(owner!['id']))
            .toList()
        : <VesselEntity>[];
    final startRing = rings
        .where((w) => (w['connected_part_ids'] as List).last == owner!['id'])
        .firstOrNull;
    final reference = g.entity(p['reference_weld_id']) ?? startRing;
    final length = (owner?['dimensions']?['length_mm'] as num?)?.toDouble();
    final fromEnd = shell &&
        reference != null &&
        (reference['connected_part_ids'] as List).first == owner!['id'];
    final stored = p['z_local_mm'] as num?;
    final distance = shell
        ? (fromEnd && length != null && stored != null
            ? length - stored
            : stored)
        : p['radius_projection_mm'];
    final axis = shell ? 'До центра от шва, мм' : 'Радиус проекции, мм';
    final v = await fields(
        'Точное размещение',
        {
          if (shell)
            'Базовый шов (${rings.map((w) => w['designation']).join(', ')})':
                '${reference?['designation'] ?? ''}',
          axis: '${distance ?? ''}',
          if (!shell)
            'Отсчёт: visio / legacy':
                '${p['angle_convention'] == 'visio-head-2026' ? 'visio' : 'legacy'}',
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
      final chosen = shell
          ? rings
              .where((w) => w['designation'] == v.entries.first.value)
              .firstOrNull
          : null;
      if (shell && chosen == null)
        throw const FormatException(
            'Выберите обозначение одного из граничных швов');
      if (!await allowPhysicalMove(e)) return;
      edit((m) => m.entity(e['id'])!['placement'] = {
            'mode': 'physical',
            shell ? 'z_local_mm' : 'radius_projection_mm': shell &&
                    (chosen!['connected_part_ids'] as List).first ==
                        owner!['id']
                ? extent - dist
                : dist,
            if (shell) 'reference_weld_id': chosen!['id'],
            if (!shell && v['Отсчёт: visio / legacy'] == 'visio')
              'angle_convention': 'visio-head-2026',
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
          'Поворот символа, °': '${e['symbol_rotation_deg'] ?? 0}',
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
          'symbol_rotation_deg': (number(v['Поворот символа, °']) ?? 0) % 360,
          'source_ref': v['Источник']
        });
      });
    } catch (error) {
      message('$error');
    }
  }

  Future<void> addElement() async {
    var parent = g.entity(store.selection);
    if (parent != null && !g.parts.contains(parent)) {
      final owner = g.entity(parent['parent_id'] ?? parent['owner_id']);
      parent = owner != null && g.parts.contains(owner)
          ? owner
          : g.entity(owner?['parent_id']);
    }
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
                        for (final e in {
                          ...vesselLibrary,
                          ...vesselElementNames
                        }.entries)
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
    if (kind == 'longitudinal' && mounted) {
      await editWeld(parent: parent);
      return;
    }
    if (kind != null && mounted) {
      edit((m) {
        store.selection = vesselLibrary.containsKey(kind)
            ? m.applyLibrary(
                kind,
                (kind.startsWith('zone_') ||
                            kind == 'profile' ||
                            kind == 'ring') &&
                        m.welds.any((w) => w['id'] == store.selection)
                    ? store.selection!
                    : id)
            : m.addElement(id, kind)['id'];
        final added = m.entity(store.selection);
        move = added?['placement'] != null;
        moveLabel = false;
        if (move && detail != null && added?['parent_id'] != detail)
          detail = null;
      });
    }
  }

  Future<bool> confirmPointArchive() async =>
      await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Изменить число точек?'),
                  content: const Text(
                      'Лишние точки будут архивированы. Их ID и результаты сохранятся.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Отмена')),
                    TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Архивировать'))
                  ])) ??
      false;

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
    final old = g.points
        .where((p) => p['owner_id'] == owner['id'] && p['archived'] != true)
        .toList();
    if (n < old.length && !await confirmPointArchive()) return;
    edit((m) => m.setPointTemplate(owner['id'], n));
  }

  Future<void> addWeld(VesselEntity p) async {
    await editWeld(parent: p);
  }

  Future<void> editWeld({VesselEntity? parent, VesselEntity? weld}) async {
    parent ??= g.entity((weld?['connected_part_ids'] as List?)?.firstOrNull);
    if (parent == null) return;
    if (weld?['locked'] == true) {
      message('Сначала снимите блокировку шва');
      return;
    }
    final shell = parent['kind'] == 'shell';
    final field = shell ? 'Угол, °' : 'От центра, мм';
    final value = weld?['geometry']?[shell ? 'theta_deg' : 'offset_mm'];
    final v = await fields(
        shell ? 'Продольный шов' : 'Шов днища / крышки',
        {
          'Обозначение':
              '${weld?['designation'] ?? 'П${g.welds.where((w) => w['kind'] != 'circumferential').length + 1}'}',
          field: '${value ?? (shell ? '' : 0)}',
        },
        hint: shell
            ? 'Укажите угол по принятому нулю. При редактировании ID шва и зоны контроля сохраняются.'
            : 'Смещение от центра в миллиметрах: минус — выше, плюс — ниже.');
    if (v == null) return;
    try {
      final a = number(v[field]);
      if (a == null) throw const FormatException('Введите угол или смещение');
      if (!shell) {
        final diameter = parent['dimensions']?['diameter_mm'];
        if (diameter is! num || a.abs() >= diameter / 2)
          throw const FormatException(
              'Задайте диаметр и смещение внутри детали');
      }
      final parentId = parent['id'];
      edit((m) {
        var target = weld == null ? null : m.entity(weld['id']);
        if (target == null) {
          if (shell) {
            m.addLongWeld(parentId, a);
            target = m.welds.last;
          } else {
            target = <String, dynamic>{
              'id': VesselGeometry.id(),
              'kind': 'head_joint',
              'connected_part_ids': [parentId],
              'geometry': <String, dynamic>{}
            };
            (m.data['welds'] as List).add(target);
          }
        }
        target['designation'] = v['Обозначение']!.isEmpty
            ? target['designation'] ?? 'Шов'
            : v['Обозначение'];
        target['geometry'] = {
          ...Map<String, dynamic>.from(target['geometry'] as Map),
          shell ? 'theta_deg' : 'offset_mm': shell ? a % 360 : a
        };
        store.selection = target['id'];
      });
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
                                child: Text(['circumferential', 'attachment']
                                        .contains(w['kind'])
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
      final ring = ['circumferential', 'attachment'].contains(w['kind']);
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

  Future<void> showProperties() => showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (panelContext) => Dialog.fullscreen(
              child: Scaffold(
            appBar: AppBar(
                title: const Text('Свойства объекта'),
                leading: IconButton(
                    tooltip: 'Закрыть свойства',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(panelContext))),
            body: SafeArea(
                child: AnimatedBuilder(
                    animation: store,
                    builder: (_, __) => properties(
                        closePanel: () => Navigator.pop(panelContext)))),
          )));

  Widget properties({VoidCallback? closePanel}) {
    final e = g.entity(store.selection);
    if (e == null) {
      return const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Выберите часть, элемент или точку на чертеже.'));
    }
    final part = g.parts.contains(e),
        element = g.elements.contains(e),
        point = g.points.contains(e);
    return ListView(
        key: PageStorageKey('properties_${e['id']}'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              e['designation']?.toString() ??
                  'Точка ${e['body_number'] ?? e['local_number']}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Wrap(spacing: 8, children: [
            TextButton.icon(
                onPressed: () => rename(e),
                icon: const Icon(Icons.edit),
                label: const Text('Переименовать')),
            TextButton.icon(
                onPressed: () => edit(
                    (m) => m.entity(e['id'])!['locked'] = e['locked'] != true),
                icon: Icon(e['locked'] == true ? Icons.lock : Icons.lock_open),
                label: Text(
                    e['locked'] == true ? 'Разблокировать' : 'Заблокировать')),
            TextButton.icon(
                onPressed: () => note(e),
                icon: const Icon(Icons.notes),
                label: const Text('Заметка')),
          ]),
          if ('${e['editor_note'] ?? ''}'.isNotEmpty)
            Text('${e['editor_note']}'),
          if (g.welds.contains(e)) ...[
            Text(e['kind'] == 'longitudinal'
                ? 'Угол: ${e['geometry']['theta_deg']}°'
                : e['kind'] == 'head_joint'
                    ? 'Смещение: ${e['geometry']['offset_mm']} мм'
                    : 'Кольцевой шов'),
            if (['longitudinal', 'head_joint'].contains(e['kind']))
              TextButton(
                  onPressed: () => editWeld(weld: e),
                  child: const Text('Изменить положение шва')),
            TextButton(
                onPressed: () => zone(e),
                child: const Text('Назначить метод и участок')),
            TextButton(
                onPressed: () => section(e, profile: true),
                child: const Text('Профиль А–А (5 позиций)')),
          ],
          if (part) ...[
            if (e['kind'] == 'head' || e['kind'] == 'cover')
              TextButton(
                  onPressed: () async {
                    final values = await fields(
                        'Шов днища / крышки',
                        {
                          'Обозначение':
                              'П${g.welds.where((w) => w['kind'] != 'circumferential').length + 1}',
                          'От центра, мм': '0'
                        },
                        hint:
                            'Отрицательное смещение — выше центра, положительное — ниже.');
                    if (values == null) return;
                    try {
                      final offset = number(values['От центра, мм']) ?? 0;
                      final diameter = e['dimensions']['diameter_mm'] as num?;
                      if (diameter == null || offset.abs() >= diameter / 2)
                        throw const FormatException(
                            'Задайте диаметр и смещение внутри детали.');
                      edit((m) => (m.data['welds'] as List).add({
                            'id': VesselGeometry.id(),
                            'kind': 'head_joint',
                            'designation': values['Обозначение'],
                            'connected_part_ids': [e['id']],
                            'geometry': {'offset_mm': offset}
                          }));
                    } catch (error) {
                      message('$error');
                    }
                  },
                  child: const Text('Добавить шов днища / крышки')),
            TextButton.icon(
                onPressed: e['locked'] == true ? null : () => partProperties(e),
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
                    DropdownMenuItem(
                        value: 'conical', child: Text('Коническая'))
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
            for (final w in g.welds.where(
                (w) => (w['connected_part_ids'] as List).contains(e['id'])))
              ListTile(
                  title: Text(w['designation']),
                  subtitle: Text(w['kind'] == 'circumferential'
                      ? 'Общий кольцевой шов'
                      : w['kind'] == 'head_joint'
                          ? 'От центра ${w['geometry']['offset_mm']} мм'
                          : w['kind'] == 'attachment'
                              ? 'Шов приварки элемента'
                              : '${w['geometry']['theta_deg']}°'),
                  trailing: const Icon(Icons.add_task),
                  onTap: () => showModalBottomSheet(
                      context: context,
                      builder: (c) => SafeArea(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                ListTile(
                                    title: Text(
                                        '${w['designation']}: назначить метод и участок'),
                                    onTap: () {
                                      Navigator.pop(c);
                                      zone(w);
                                    }),
                                ListTile(
                                    title:
                                        const Text('Профиль А–А (5 позиций)'),
                                    onTap: () {
                                      Navigator.pop(c);
                                      section(w, profile: true);
                                    }),
                              ])))),
          ],
          if (element) ...[
            if (['nozzle', 'manway'].contains(e['kind']))
              TextButton(
                  onPressed: () async {
                    final found = g.welds.where((w) =>
                        w['kind'] == 'attachment' &&
                        w['geometry']['element_id'] == e['id']);
                    final weld = found.isNotEmpty
                        ? found.first
                        : <String, dynamic>{
                            'id': VesselGeometry.id(),
                            'kind': 'attachment',
                            'designation': 'Шов ${e['designation']}',
                            'connected_part_ids': [e['parent_id']],
                            'geometry': {'element_id': e['id']}
                          };
                    if (found.isEmpty)
                      edit((m) => (m.data['welds'] as List).add(weld));
                    await zone(weld);
                  },
                  child: const Text('Контроль шва приварки')),
            Text(vesselElementNames[e['kind']] ?? e['kind']),
            if (e['kind'] == 'nozzle')
              TextButton(
                  onPressed: () {
                    final n = VesselGeometry.recommendedNozzlePoints(
                        e['nominal_dn_mm'] as num?);
                    if (n == null) {
                      message('Сначала задайте ДУ в свойствах');
                      return;
                    }
                    template(e, recommended: n);
                  },
                  child: Text(
                      'По ДУ: ${VesselGeometry.recommendedNozzlePoints(e['nominal_dn_mm'] as num?) ?? '?'} точки')),
            TextButton(
                onPressed:
                    e['locked'] == true ? null : () => elementProperties(e),
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
                onPressed: e['locked'] == true ? null : () => coordinates(e),
                icon: const Icon(Icons.pin_drop),
                label: const Text('Точное размещение')),
            TextButton(
                onPressed: e['locked'] == true
                    ? null
                    : () {
                        setState(() {
                          move = true;
                          moveLabel = false;
                        });
                        closePanel?.call();
                      },
                child: const Text('Переместить: нажать место')),
            TextButton(
                onPressed: () {
                  setState(() {
                    moveLabel = true;
                    move = false;
                  });
                  closePanel?.call();
                },
                child: const Text('Перенести только подпись')),
          ],
          if (part || element)
            TextButton.icon(
                onPressed: e['locked'] == true ? null : () => template(e),
                icon: const Icon(Icons.control_point_duplicate),
                label: const Text('Шаблон точек')),
          if (element)
            TextButton(
                onPressed: e['locked'] == true
                    ? null
                    : () => edit(
                        (m) => VesselEditorTools.archive(m, e['id'], true)),
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
                                  for (final row in widget.legacyMeasurements
                                      .where((r) => !g.points.any((p) =>
                                          p['id'] == r['scheme_point_id'])))
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
                            'legacy_point_bindings',
                            () => <String, dynamic>{}) as Map;
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
                value: '${e['status'] ?? 'planned'}',
                items: [
                  if (!['planned', 'inaccessible', 'skipped', null]
                      .contains(e['status']))
                    DropdownMenuItem(
                        value: '${e['status']}',
                        child: Text('Сохранённый статус: ${e['status']}')),
                  DropdownMenuItem(
                      value: 'planned', child: Text('Запланирована')),
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

  Widget tree({VoidCallback? closePanel}) => AnimatedBuilder(
      animation: Listenable.merge([store, search]),
      builder: (_, __) => Column(children: [
            Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                    controller: searchInput,
                    onChanged: (v) => search.value = v,
                    decoration: const InputDecoration(
                        labelText: 'Поиск: обозначение, тип, ДУ',
                        prefixIcon: Icon(Icons.search)))),
            Expanded(
                child: ListView(children: [
              ListTile(
                  title: const Text('Весь сосуд'),
                  leading: const Icon(Icons.view_agenda),
                  onTap: () {
                    setState(() => detail = null);
                    closePanel?.call();
                  }),
              for (final e in [
                ...g.parts,
                ...g.elements,
                ...g.welds,
                ...g.points
              ].where((e) =>
                  e['archived'] != true &&
                  '${e['designation']} ${vesselElementNames[e['kind']] ?? e['kind']} ${e['nominal_dn_mm']} ${e['body_number'] ?? e['local_number']}'
                      .toLowerCase()
                      .contains(search.value.trim().toLowerCase())))
                ListTile(
                    dense: true,
                    selected: store.selection == e['id'],
                    leading: Icon(e['locked'] == true
                        ? Icons.lock
                        : g.welds.contains(e)
                            ? Icons.linear_scale
                            : e.containsKey('owner_id')
                                ? Icons.my_location
                                : Icons.category),
                    title: Text(
                        '${e['designation'] ?? 'Точка ${e['body_number'] ?? e['local_number']}'}'),
                    subtitle: Text(
                        '${vesselElementNames[e['kind']] ?? (e['kind'] == 'longitudinal' ? 'Продольный шов' : e['kind'] == 'shell' ? 'Обечайка' : e['kind'] == 'head' ? 'Днище' : e['kind'] ?? 'УЗТ')} · ${g.entity(e['parent_id'] ?? e['owner_id'])?['designation'] ?? ''}'),
                    onTap: () {
                      select(e['id']);
                      closePanel?.call();
                    }),
              ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Добавить обечайку'),
                  onTap: () =>
                      edit((m) => store.selection = m.addShell()['id'])),
            ])),
          ]));
  void select(String id) {
    setState(() {
      store.selection = id;
      move = moveLabel = false;
    });
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
      final placement = layout.placementAt(e, at);
      if (placement == null) {
        message(
            'Выберите место внутри контура детали. Для точного режима проверьте её размеры.');
        return;
      }
      if (!await allowPhysicalMove(e)) return;
      if (!mounted) return;
      edit((m) => m.entity(e['id'])!['placement'] = placement);
      setState(() => move = false);
      return;
    }
    final hits = layout.hit(at).where((id) {
      final e = g.entity(id)!;
      return !hiddenLayers.contains(g.welds.contains(e)
          ? 'Швы'
          : e.containsKey('owner_id')
              ? 'Точки'
              : g.elements.contains(e)
                  ? 'Элементы'
                  : '');
    }).toList();
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
    final image = await pic.toImage(
        (size.width * 1.5).round(), (size.height * 1.5).round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    pic.dispose();
    return bytes!.buffer.asUint8List();
  }

  Future<void> exportPdf() async {
    setState(() => busy = true);
    try {
      final doc = pw.Document();
      final font = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      final base = vesselPaper(g) == 'A3' ? PdfPageFormat.a3 : PdfPageFormat.a4;
      final format =
          g.data['orientation'] == 'horizontal' ? base.landscape : base;
      final details = (g.data['print_settings']?['detail_ids'] as List? ?? [])
          .where((id) => g.parts.any((p) => p['id'] == id));
      for (final id in [null, ...details]) {
        doc.addPage(pw.Page(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(12),
            build: (_) => pw.Center(
                child: pw.SvgImage(
                    svg: exportVesselSvg(g, detail: id),
                    width: format.width - 24,
                    height: format.height - 24,
                    fit: pw.BoxFit.contain,
                    customFontLookup: (_, __, ___) => font))));
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
  Widget build(BuildContext context) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                store.undo,
            const SingleActivator(LogicalKeyboardKey.keyY, control: true):
                store.redo,
            const SingleActivator(LogicalKeyboardKey.keyZ,
                control: true, shift: true): store.redo,
            const SingleActivator(LogicalKeyboardKey.keyD, control: true):
                duplicateSelection,
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                keyboardShift(0, -1),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                keyboardShift(0, 1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                keyboardShift(-1, 0),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                keyboardShift(1, 0),
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                setState(() {
                  move = false;
                  moveLabel = false;
                  ruler = false;
                }),
          },
          child: Focus(
              autofocus: true,
              child: PopScope(
                  canPop: allowPop,
                  onPopInvokedWithResult: (didPop, result) {
                    if (!didPop) leave();
                  },
                  child: Scaffold(
                    appBar: AppBar(
                        title: const Text('Конструктор сосуда'),
                        actions: [
                          IconButton(
                              tooltip: 'Инструменты чертежа',
                              onPressed: ready ? showTools : null,
                              icon: const Icon(Icons.handyman_outlined)),
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
                                            label:
                                                Text('${i + 1}. ${steps[i]}'),
                                            selected: store.step == i,
                                            onSelected: (_) {
                                              setState(() => store.step = i);
                                              store.changed();
                                            }))
                                ])),
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(children: [
                                  Expanded(
                                      child: Text(store.saveStatus,
                                          style:
                                              const TextStyle(fontSize: 12))),
                                  Text('Рев. ${g.data['revision']}')
                                ])),
                            if (store.step == 0)
                              Wrap(spacing: 8, children: [
                                TextButton.icon(
                                    onPressed: loadVisioExample,
                                    icon: const Icon(Icons.schema_outlined),
                                    label:
                                        const Text('Пример Visio · 6 обечаек')),
                                TextButton(
                                    onPressed: base,
                                    child:
                                        const Text('Источник и отсчёт углов')),
                                TextButton(
                                    onPressed: () => edit((m) => m
                                            .data['orientation'] =
                                        m.data['orientation'] == 'horizontal'
                                            ? 'vertical'
                                            : 'horizontal'),
                                    child: Text(
                                        g.data['orientation'] == 'horizontal'
                                            ? 'Горизонтальный'
                                            : 'Вертикальный'))
                              ]),
                            if (store.step == 1)
                              TextButton.icon(
                                  onPressed: () => edit((m) {
                                        store.selection = m.addShell()['id'];
                                      }),
                                  icon: const Icon(Icons.add),
                                  label: Text(
                                      'Обечаек: ${g.shells.length} · добавить')),
                            if (store.step == 3)
                              Wrap(children: [
                                TextButton(
                                    onPressed: () => edit((m) {
                                          for (final s in m.shells) {
                                            m.setPointTemplate(s['id'], 12);
                                          }
                                        }),
                                    child:
                                        const Text('По 12 точек на обечайку')),
                                Text(
                                    '${g.points.where((p) => p['archived'] != true).length} точек (план)')
                              ]),
                            if (store.step == 4)
                              Row(children: [
                                Expanded(
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12),
                                        child: Text(
                                            '${vesselPaper(g)} · ${g.data['orientation'] == 'horizontal' ? 'альбомный' : 'книжный'}'))),
                                TextButton.icon(
                                    onPressed: showPrintSettings,
                                    icon: const Icon(Icons.print_outlined),
                                    label: const Text('Печать'))
                              ]),
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
                            Expanded(
                                child: LayoutBuilder(builder: (c, constraints) {
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
                                          onPressed: showObjectList),
                                    Expanded(
                                        child: Text(
                                            detail == null
                                                ? 'Общий вид'
                                                : g.entity(detail)?[
                                                        'designation'] ??
                                                    '',
                                            overflow: TextOverflow.ellipsis)),
                                    if (detail != null)
                                      IconButton(
                                          tooltip: 'Общий вид',
                                          onPressed: () =>
                                              setState(() => detail = null),
                                          icon: const Icon(Icons.close)),
                                    PopupMenuButton<String>(
                                        tooltip: 'Слой контроля',
                                        initialValue: layer,
                                        onSelected: (v) =>
                                            setState(() => layer = v),
                                        itemBuilder: (_) => [
                                              'Все',
                                              'УЗТ',
                                              'УЗК',
                                              'МК',
                                              'ПВК',
                                              'ВИК'
                                            ]
                                                .map((s) => PopupMenuItem(
                                                    value: s, child: Text(s)))
                                                .toList(),
                                        child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Text(layer))),
                                    IconButton(
                                        tooltip: 'Днище B с внешней стороны',
                                        onPressed: () => setState(
                                            () => exteriorB = !exteriorB),
                                        icon: Icon(exteriorB
                                            ? Icons.flip
                                            : Icons.flip_outlined)),
                                  ]),
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                            tooltip: 'Уменьшить',
                                            icon: const Icon(Icons.zoom_out),
                                            onPressed: () {
                                              if (transform.value
                                                      .getMaxScaleOnAxis() >
                                                  .4)
                                                transform.value =
                                                    transform.value.clone()
                                                      ..scale(1 / 1.4);
                                            }),
                                        TextButton(
                                            onPressed: () => transform.value =
                                                Matrix4.identity(),
                                            child: const Text('Весь лист')),
                                        IconButton(
                                            tooltip: 'Увеличить',
                                            icon: const Icon(Icons.zoom_in),
                                            onPressed: () {
                                              if (transform.value
                                                      .getMaxScaleOnAxis() <
                                                  4)
                                                transform.value =
                                                    transform.value.clone()
                                                      ..scale(1.4);
                                            }),
                                      ]),
                                  Expanded(
                                      child: VesselEditorCanvas(
                                          key: canvasKey,
                                          geometry: g,
                                          selection: store.selection,
                                          detail: detail,
                                          exteriorB: exteriorB,
                                          layer: layer,
                                          transform: transform,
                                          grid: grid,
                                          snap: snap,
                                          snapWelds: snapWelds,
                                          divisions: gridDivisions,
                                          ruler: ruler,
                                          hiddenLayers: hiddenLayers,
                                          onTap: tap,
                                          onSelect: select,
                                          onMove: moveObject)),
                                ])),
                                if (tablet)
                                  SizedBox(width: 280, child: properties()),
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
                                      onPressed: busy ? null : showProperties,
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
                  ))));
}

class _Symbol extends CustomPainter {
  final String kind;
  _Symbol(this.kind);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2),
        ink = Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke;
    if (kind == 'profile') {
      paintWeldProfile(canvas, Offset.zero, 32, scale: .22);
      return;
    }
    if (kind == 'support') {
      canvas.drawRect(
          Rect.fromCenter(center: center, width: 8, height: 30), ink);
      return;
    }
    if (kind == 'point') {
      canvas.drawLine(
          center - const Offset(4, 4), center + const Offset(4, 4), ink);
      canvas.drawLine(
          center + const Offset(-4, 4), center + const Offset(4, -4), ink);
      return;
    }
    if (kind == 'ring' || kind == 'longitudinal' || kind.startsWith('zone_')) {
      final vertical = kind.contains('ring');
      canvas.drawLine(
          center - (vertical ? const Offset(0, 14) : const Offset(14, 0)),
          center + (vertical ? const Offset(0, 14) : const Offset(14, 0)),
          ink);
      if (kind.startsWith('zone_'))
        canvas.drawRect(
            Rect.fromCenter(
                center: center,
                width: vertical ? 8 : 22,
                height: vertical ? 22 : 8),
            ink);
      return;
    }
    paintVesselElement(canvas, center,
        kind.startsWith('nozzle_') || kind == 'cover' ? 'nozzle' : kind,
        engineering: true);
    if (kind.startsWith('nozzle_') && kind != 'nozzle_none') {
      canvas.drawCircle(center, 13, ink);
      for (final offset in [
        const Offset(-10, 0),
        const Offset(10, 0),
        if (!kind.contains('small')) const Offset(0, -10),
        if (!kind.contains('small')) const Offset(0, 10)
      ]) canvas.drawCircle(center + offset, 2, Paint()..color = Colors.black);
      if (kind.endsWith('combined'))
        canvas.drawCircle(center, 15, ink..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _Symbol oldDelegate) => false;
}
