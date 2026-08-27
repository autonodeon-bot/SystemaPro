import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/equipment.dart';
import 'inspection_form_profiles.dart';

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
        'Прил. № 6. Протокол контроля твердости',
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

  static const List<String> _pipelineNavigation = [
    '1–7. Сведения об обследовании',
    '11. Сведения о рассмотренных документах',
    'Паспорт трубопровода',
    '9. Характеристика трубопровода',
    'ВИК / дефекты',
    'Сварные соединения',
    'Протоколы НК (УЗТ, УЗК, МПК)',
    '13. Выводы по результатам ТД',
  ];

  static const Map<String, String> _pipelineSections = {
    'general':
        '1–7. Основания, сроки, заказчик, организация, специалисты и приборы',
    'documents':
        '11. Сведения о рассмотренных в процессе ТД документах',
    'passport': 'Прил. Б. Протокол анализа технической документации',
    'survey': '9. Краткая характеристика трубопровода',
    'survey_prev': 'Предыдущие обследования',
    'checks': 'Прил. В. Визуальный и измерительный контроль',
    'defects': 'Дефекты / результаты ВИК',
    'zra': 'Сварные соединения (вместо ЗРА сосуда)',
    'sppk': 'Элементы трассы',
    'measurements_vik': 'Измерительный контроль',
    'measurements_operational': 'Обследование трассы / ЭХЗ',
    'measurements_hardness': 'Контроль твердости',
    'measurements_ndt': 'УЗК / МПК / ВТК сварных соединений',
    'measurements_uzt': 'Ультразвуковая толщинометрия',
    'conclusion': '13. Выводы по результатам технической диагностики',
  };

  static const List<Map<String, String>> pipelineDocuments = [
    {'number': '1', 'name': 'Лицензия на осуществление деятельности'},
    {
      'number': '2',
      'name': 'Свидетельство о регистрации опасных производственных объектов'
    },
    {'number': '3', 'name': 'Декларация промышленной безопасности'},
    {
      'number': '4',
      'name':
          'Договор обязательного страхования гражданской ответственности'
    },
    {'number': '5', 'name': 'Страховой полис'},
    {'number': '6', 'name': 'План мероприятий по локализации аварий'},
    {'number': '7', 'name': 'Положение о производственном контроле'},
    {'number': '8', 'name': 'Паспорт трубопровода'},
    {'number': '9', 'name': 'Исполнительная документация / схемы'},
    {'number': '10', 'name': 'Журнал эксплуатации / ремонтов'},
    {'number': '11', 'name': 'Заключение ЭПБ (при наличии)'},
    {'number': '12', 'name': 'Акты УЗТ / НК предыдущих обследований'},
  ];

  static const List<String> _craneNavigation = [
    '1–7. Сведения об обследовании',
    'Документы ПС',
    'Паспортные данные ПС',
    'Характеристика крана / ГПМ',
    'ВИК металлоконструкций',
    'Устройства безопасности',
    'Протоколы НК (УЗТ, УЗК)',
    '15. Выводы',
  ];

  static const Map<String, String> _craneSections = {
    'general': '1–7. Сведения об обследовании ГПМ',
    'documents': '11. Документы на подъемное сооружение',
    'passport': 'Паспортные данные ПС',
    'survey': '9. Краткая характеристика подъемного сооружения',
    'survey_prev': 'Предыдущие обследования',
    'checks': 'ВИК металлоконструкций',
    'defects': 'Ведомость дефектов',
    'zra': 'Приборы и устройства безопасности',
    'sppk': 'Механическое / канатно-блочное оборудование',
    'measurements_vik': 'Геометрия металлоконструкции',
    'measurements_operational': 'Проверка работоспособности',
    'measurements_hardness': 'Контроль твердости',
    'measurements_ndt': 'УЗК металлоконструкций',
    'measurements_uzt': 'Ультразвуковая толщинометрия',
    'conclusion': '15. Выводы по результатам технического диагностирования',
  };

  static const List<Map<String, String>> craneDocuments = [
    {'number': '1', 'name': 'Паспорт крана'},
    {'number': '2', 'name': 'Инструкция по эксплуатации'},
    {'number': '3', 'name': 'Страховой полис ОПО'},
    {'number': '4', 'name': 'Предыдущие акты обследования'},
    {'number': '5', 'name': 'Ведомость дефектов / ремонтов'},
    {'number': '6', 'name': 'Документы на приборы безопасности'},
  ];

  static TechnicalReportForm _buildForm({
    required String id,
    required int number,
    required String title,
  }) {
    final profile = InspectionFormProfiles.forFormId(id);
    if (profile == InspectionProfile.vessel) {
      return TechnicalReportForm(
        id: id,
        number: number,
        title: title,
        navigationLabels: _vesselNavigation,
        sectionHeaders: _vesselSections,
        documents: vesselDocuments,
      );
    }
    if (profile == InspectionProfile.pipeline) {
      return TechnicalReportForm(
        id: id,
        number: number,
        title: title,
        navigationLabels: _pipelineNavigation,
        sectionHeaders: _pipelineSections,
        documents: pipelineDocuments,
      );
    }
    if (profile == InspectionProfile.crane) {
      return TechnicalReportForm(
        id: id,
        number: number,
        title: title,
        navigationLabels: _craneNavigation,
        sectionHeaders: _craneSections,
        documents: craneDocuments,
      );
    }

    final label = InspectionFormProfiles.objectLabel(profile, cleanTitle(title));
    final nav = _genericNavigation(label);
    // страница 5: не «арматура сосуда», а профиль объекта
    final sections = _genericSections(label);
    sections['zra'] = InspectionFormProfiles.page5Title(profile);
    sections['sppk'] = profile == InspectionProfile.tank
        ? 'Швы и пояса резервуара'
        : profile == InspectionProfile.electrical
            ? 'Точки электрических измерений'
            : 'Элементы и узлы объекта';

    List<Map<String, String>> docs = vesselDocuments;
    if (profile == InspectionProfile.tank) {
      docs = [
        {'number': '1', 'name': 'Паспорт резервуара'},
        {'number': '2', 'name': 'Свидетельство о регистрации ОПО'},
        {'number': '3', 'name': 'Страховой полис'},
        {'number': '4', 'name': 'Исполнительная документация / схемы'},
        {'number': '5', 'name': 'Журнал эксплуатации / ремонтов'},
        {'number': '6', 'name': 'Акты УЗТ / НК предыдущих обследований'},
      ];
    } else if (profile == InspectionProfile.boiler) {
      docs = [
        {'number': '1', 'name': 'Паспорт котла'},
        {'number': '2', 'name': 'Инструкция по эксплуатации'},
        {'number': '3', 'name': 'Свидетельство о регистрации ОПО'},
        {'number': '4', 'name': 'Документы на арматуру и КИП'},
        {'number': '5', 'name': 'Акты предыдущих обследований'},
      ];
    } else if (profile == InspectionProfile.electrical ||
        profile == InspectionProfile.machinery ||
        profile == InspectionProfile.station ||
        profile == InspectionProfile.valve ||
        profile == InspectionProfile.tower) {
      docs = [
        {'number': '1', 'name': 'Паспорт / формуляр оборудования'},
        {'number': '2', 'name': 'Свидетельство о регистрации ОПО (при наличии)'},
        {'number': '3', 'name': 'Страховой полис'},
        {'number': '4', 'name': 'Инструкция по эксплуатации'},
        {'number': '5', 'name': 'Исполнительная / ремонтная документация'},
        {'number': '6', 'name': 'Акты предыдущих обследований / НК'},
      ];
    }

    return TechnicalReportForm(
      id: id,
      number: number,
      title: title,
      navigationLabels: nav,
      sectionHeaders: sections,
      documents: docs,
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
    final type = (equipment.typeCode ?? '').toUpperCase().trim();
    if (type.isNotEmpty &&
        InspectionFormProfiles.equipmentTypeToForm.containsKey(type)) {
      return InspectionFormProfiles.equipmentTypeToForm[type]!;
    }

    final name = equipment.name.toLowerCase();
    final typeName = (equipment.typeName ?? '').toLowerCase();
    final blob = '$name $typeName ${type.toLowerCase()}';

    if (type == 'UNDERGROUND_PIPELINE' ||
        ((type.contains('PIPELINE') ||
                name.contains('трубопровод') ||
                typeName.contains('трубопровод') ||
                typeName.contains('pipeline')) &&
            blob.contains('подземн'))) {
      return 'to-33';
    }
    if (type == 'CRANE' ||
        type == 'GPM' ||
        type == 'LIFTING' ||
        name.contains('кран') ||
        name.contains('грузоподъем') ||
        name.contains('грузоподъём') ||
        name.contains('трубоуклад') ||
        typeName.contains('грузоподъем') ||
        typeName.contains('гпм')) {
      return 'to-3';
    }
    if (type.contains('PIPELINE') ||
        name.contains('трубопровод') ||
        typeName.contains('трубопровод') ||
        typeName.contains('pipeline')) {
      if (name.contains('надземн') || name.contains('газопровод')) {
        return 'to-32';
      }
      if (name.contains('обвязк') && name.contains('скважин')) return 'to-26';
      return 'to-13';
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
    if (name.contains('факел')) return 'to-44';
    if (name.contains('дымов')) return 'to-39';
    if (name.contains('грс')) return 'to-9';
    return 'to-1';
  }
}
