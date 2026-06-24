import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/equipment.dart';

/// Конфигурация формы технического отчёта (приложение к ТО).
class TechnicalReportForm {
  final String id;
  final int number;
  final String title;
  final List<String> navigationLabels;
  final Map<String, String> sectionHeaders;
  final List<Map<String, String>> documents;

  const TechnicalReportForm({
    required this.id,
    required this.number,
    required this.title,
    required this.navigationLabels,
    required this.sectionHeaders,
    this.documents = const [],
  });

  String get displayTitle => TechnicalReportFormRegistry.cleanTitle(title);

  String sectionHeader(String key, {String? fallback}) =>
      sectionHeaders[key] ?? fallback ?? key;

  String navigationLabel(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= navigationLabels.length) {
      return '${pageIndex + 1}';
    }
    return navigationLabels[pageIndex];
  }
}

/// Результат выбора при открытии обследования из задания.
class InspectionStartSelection {
  final String reportFormId;
  final String inspectionType;

  const InspectionStartSelection({
    required this.reportFormId,
    required this.inspectionType,
  });
}

/// Реестр форм ТО — названия из каталога «Приложение_форма ТО».
class TechnicalReportFormRegistry {
  TechnicalReportFormRegistry._();

  static List<TechnicalReportForm>? _forms;
  static final Map<String, TechnicalReportForm> _byId = {};

  static String cleanTitle(String raw) {
    return raw
        .replaceAll(RegExp(r'[_\s]*корр$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Документы по форме ТО «Обследование сосудов и аппаратов» (таблица № 1).
  static const List<Map<String, String>> vesselDocuments = [
    {'number': '1', 'name': 'Лицензия на осуществление эксплуатации'},
    {
      'number': '2',
      'name':
          'Свидетельство о регистрации опасных производственных объектов',
    },
    {
      'number': '3',
      'name':
          'Договор обязательного страхования гражданской ответственности',
    },
    {'number': '4', 'name': 'Страховой полис'},
    {
      'number': '5',
      'name': 'Положение о производственном контроле',
    },
    {
      'number': '6',
      'name': 'Приказ об организации производственного контроля',
    },
    {
      'number': '7',
      'name':
          'План мероприятий по локализации и ликвидации последствий аварий',
    },
    {'number': '8', 'name': 'Предписания надзорных органов'},
    {
      'number': '9',
      'name':
          'Журнал учета аварий и инцидентов, происшедших на опасных производственных объектах',
    },
    {'number': '10', 'name': 'Технический паспорт сосуда'},
    {'number': '11', 'name': 'Инструкция по монтажу и эксплуатации'},
    {'number': '12', 'name': 'Паспорта на предохранительные клапаны'},
    {'number': '13', 'name': 'Паспорта на запорную арматуру'},
    {
      'number': '14',
      'name': 'Документация на контрольно-измерительные приборы',
    },
    {'number': '15', 'name': 'Ремонтная (исполнительная) документация'},
    {
      'number': '16',
      'name': 'Заключение экспертизы промышленной безопасности',
    },
    {'number': '17', 'name': 'Акты проведения УЗТ'},
  ];

  static const List<String> _vesselNavigation = [
    '1–7. Сведения об обследовании',
    '11. Сведения о рассмотренных документах',
    'Прил. Б. Паспортные данные',
    '9. Краткая техническая характеристика',
    'Прил. № 3. Визуальный и измерительный контроль',
    'ЗРА и предохранительные клапаны',
    'Прил. № 4–7. Протоколы НК',
    '15. Выводы по результатам ТД',
  ];

  static const Map<String, String> _vesselSections = {
    'general':
        '1–7. Основания, сроки, заказчик, организация, специалисты и приборы',
    'documents':
        '11. Сведения о рассмотренных в процессе ТД документах',
    'passport':
        'Прил. № 1. Протокол анализа технической документации (табл. № 1–9)',
    'survey': '9. Краткая техническая характеристика объекта',
    'survey_prev': '12. Анализ результатов предыдущих обследований',
    'checks':
        'Прил. № 3. Протокол визуального и измерительного контроля',
    'defects': 'Прил. № 3. Результаты визуального контроля — дефекты',
    'zra': 'ЗРА (запорно-регулирующая арматура)',
    'sppk': 'Предохранительные клапаны',
    'measurements_vik':
        'Прил. № 3. Измерительный контроль (овальность, прогиб)',
    'measurements_operational':
        'Прил. № 2. Оперативная (функциональная) диагностика',
    'measurements_hardness':
        'Прил. № 5. Протокол контроля твердости',
    'measurements_ndt':
        'Прил. № 6–7. Протоколы УЗК и магнитопорошкового контроля',
    'measurements_uzt':
        'Прил. № 4. Протокол ультразвуковой толщинометрии',
    'conclusion': '15. Выводы по результатам технической диагностики',
  };

  static List<String> _genericNavigation(String objectLabel) => [
        '1–7. Сведения об обследовании',
        '11. Сведения о рассмотренных документах',
        'Паспортные данные',
        '9. Техническая характеристика — $objectLabel',
        'Визуальный и измерительный контроль',
        'Арматура и предохранительные устройства',
        'Протоколы неразрушающего контроля',
        '15. Выводы по результатам обследования',
      ];

  static Map<String, String> _genericSections(String objectLabel) => {
        'general': '1–7. Сведения об обследовании',
        'documents': '11. Сведения о рассмотренных документах',
        'passport': 'Техническая документация и паспортные данные',
        'survey': '9. Техническая характеристика — $objectLabel',
        'survey_prev': '12. Анализ результатов предыдущих обследований',
        'checks': 'Визуальный и измерительный контроль',
        'defects': 'Выявленные дефекты',
        'zra': 'ЗРА',
        'sppk': 'Предохранительные клапаны',
        'measurements_vik': 'Измерительный контроль',
        'measurements_operational': 'Функциональная диагностика',
        'measurements_hardness': 'Контроль твердости',
        'measurements_ndt': 'Неразрушающий контроль (УЗК, МПК, ПВК)',
        'measurements_uzt': 'Ультразвуковая толщинометрия',
        'conclusion': '15. Выводы по результатам обследования',
      };

  static Future<void> ensureLoaded() async {
    if (_forms != null) return;
    final raw = await rootBundle.loadString(
      'assets/data/technical_report_forms.json',
    );
    final list = json.decode(raw) as List<dynamic>;
    _forms = [];
    _byId.clear();
    for (final item in list) {
      final map = Map<String, dynamic>.from(item as Map);
      final id = map['id'] as String;
      final number = map['number'] as int;
      final title = map['title'] as String;
      final form = _buildForm(id: id, number: number, title: title);
      _forms!.add(form);
      _byId[id] = form;
    }
    _forms!.sort((a, b) => a.number.compareTo(b.number));
  }

  static TechnicalReportForm _buildForm({
    required String id,
    required int number,
    required String title,
  }) {
    if (id == 'to-1') {
      return TechnicalReportForm(
        id: id,
        number: number,
        title: title,
        navigationLabels: _vesselNavigation,
        sectionHeaders: _vesselSections,
        documents: vesselDocuments,
      );
    }

    final label = cleanTitle(title);
    return TechnicalReportForm(
      id: id,
      number: number,
      title: title,
      navigationLabels: _genericNavigation(label),
      sectionHeaders: _genericSections(label),
      documents: vesselDocuments,
    );
  }

  static List<TechnicalReportForm> get forms {
    if (_forms == null) {
      throw StateError(
        'TechnicalReportFormRegistry.ensureLoaded() must be called first',
      );
    }
    return List.unmodifiable(_forms!);
  }

  static TechnicalReportForm getById(String id) {
    if (_byId.isEmpty) {
      return _buildForm(
        id: 'to-1',
        number: 1,
        title: 'Обследование сосудов и аппаратов корр',
      );
    }
    return _byId[id] ?? _byId['to-1']!;
  }

  static TechnicalReportForm formForChecklist(String? reportFormId) {
    if (reportFormId == null || reportFormId.isEmpty) {
      return _byId['to-1'] ?? _buildForm(id: 'to-1', number: 1, title: '');
    }
    return getById(reportFormId);
  }

  static String inspectionTypeFromAssignment(String assignmentType) {
    switch (assignmentType.toUpperCase()) {
      case 'EXPERTISE':
        return 'EXPERTISE';
      case 'INSPECTION':
        return 'VISUAL';
      case 'DIAGNOSTICS':
      case 'CHTO':
      case 'PTO':
      case 'NVO':
      case 'NVO_GI':
      default:
        return 'NDT';
    }
  }

  /// Подбор формы ТО по типу и наименованию оборудования.
  static String suggestFormId(Equipment equipment) {
    final type = (equipment.typeCode ?? '').toUpperCase();
    final name = equipment.name.toLowerCase();
    final typeName = (equipment.typeName ?? '').toLowerCase();

    if (type.contains('PIPELINE') ||
        name.contains('трубопровод') ||
        typeName.contains('трубопровод') ||
        typeName.contains('pipeline')) {
      if (name.contains('подземн')) return 'to-33';
      if (name.contains('надземн') || name.contains('газопровод')) {
        return 'to-32';
      }
      if (name.contains('обвязк') && name.contains('скважин')) return 'to-26';
      return 'to-13';
    }
    if (name.contains('кран') ||
        name.contains('грузоподъем') ||
        name.contains('грузоподъём') ||
        type.contains('CRANE')) {
      return 'to-3';
    }
    if (name.contains('котел') ||
        name.contains('котёл') ||
        type.contains('BOILER')) {
      return 'to-28';
    }
    if (name.contains('резервуар') ||
        name.contains('ёмкост') ||
        name.contains('емкост') ||
        type.contains('TANK')) {
      return 'to-25';
    }
    if (name.contains('компрессор') || type.contains('COMPRESSOR')) {
      return 'to-12';
    }
    if (name.contains('трансформатор')) return 'to-5';
    if (name.contains('электродвигател')) return 'to-8';
    if (name.contains('арматур') && !name.contains('фонтан')) return 'to-24';
    return 'to-1';
  }
}
