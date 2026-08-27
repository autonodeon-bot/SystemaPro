/// Профиль обследования по семейству схемы / форме ТО.
/// Определяет поля карты, страницу арматуры/узлов и подписи навигации.
enum InspectionProfile {
  vessel,
  pipeline,
  crane,
  tank,
  boiler,
  machinery,
  electrical,
  valve,
  tower,
  station,
  generic,
}

class InspectionFormProfiles {
  InspectionFormProfiles._();

  static const Map<String, InspectionProfile> _formOverrides = {
    'to-1': InspectionProfile.vessel,
    'to-2': InspectionProfile.crane,
    'to-3': InspectionProfile.crane,
    'to-4': InspectionProfile.pipeline,
    'to-5': InspectionProfile.electrical,
    'to-6': InspectionProfile.electrical,
    'to-7': InspectionProfile.electrical,
    'to-8': InspectionProfile.machinery,
    'to-9': InspectionProfile.station,
    'to-10': InspectionProfile.generic,
    'to-11': InspectionProfile.machinery,
    'to-12': InspectionProfile.machinery,
    'to-13': InspectionProfile.pipeline,
    'to-14': InspectionProfile.generic,
    'to-15': InspectionProfile.station,
    'to-16': InspectionProfile.electrical,
    'to-17': InspectionProfile.machinery,
    'to-18': InspectionProfile.pipeline,
    'to-19': InspectionProfile.pipeline,
    'to-20': InspectionProfile.pipeline,
    'to-21': InspectionProfile.pipeline,
    'to-22': InspectionProfile.pipeline,
    'to-23': InspectionProfile.machinery,
    'to-24': InspectionProfile.valve,
    'to-25': InspectionProfile.tank,
    'to-26': InspectionProfile.pipeline,
    'to-27': InspectionProfile.valve,
    'to-28': InspectionProfile.boiler,
    'to-29': InspectionProfile.machinery,
    'to-30': InspectionProfile.boiler,
    'to-31': InspectionProfile.pipeline,
    'to-32': InspectionProfile.pipeline,
    'to-33': InspectionProfile.pipeline,
    'to-34': InspectionProfile.generic,
    'to-35': InspectionProfile.station,
    'to-36': InspectionProfile.station,
    'to-37': InspectionProfile.station,
    'to-38': InspectionProfile.generic,
    'to-39': InspectionProfile.tower,
    'to-40': InspectionProfile.station,
    'to-41': InspectionProfile.generic,
    'to-42': InspectionProfile.electrical,
    'to-43': InspectionProfile.tank,
    'to-44': InspectionProfile.tower,
  };

  static const Map<String, InspectionProfile> _familyToProfile = {
    'vessel_development': InspectionProfile.vessel,
    'pipeline': InspectionProfile.pipeline,
    'crane': InspectionProfile.crane,
    'tank': InspectionProfile.tank,
    'boiler': InspectionProfile.boiler,
    'machinery': InspectionProfile.machinery,
    'electrical': InspectionProfile.electrical,
    'valve': InspectionProfile.valve,
    'tower': InspectionProfile.tower,
    'station': InspectionProfile.station,
    'generic': InspectionProfile.generic,
  };

  /// Полная карта тип оборудования → форма ТО (как backend EQUIPMENT_TYPE_TO_FORM).
  static const Map<String, String> equipmentTypeToForm = {
    'VESSEL': 'to-1',
    'GAS_SEPARATOR': 'to-1',
    'OIL_SETTLER': 'to-1',
    'CRANE_RUNWAY': 'to-2',
    'CRANE': 'to-3',
    'GPM': 'to-3',
    'LIFTING': 'to-3',
    'GAS_COLLECTOR': 'to-4',
    'TRANSFORMER': 'to-5',
    'LIGHTNING_PROTECTION': 'to-6',
    'DC_SYSTEM': 'to-7',
    'ELECTRIC_MOTOR': 'to-8',
    'GRS': 'to-9',
    'COMPLEX_PERIODIC': 'to-10',
    'GPA': 'to-11',
    'COMPRESSOR': 'to-12',
    'PIPELINE': 'to-13',
    'ACCEPTANCE': 'to-14',
    'DIESEL_STATION': 'to-15',
    'CABLE_LINE': 'to-16',
    'GPA_DRIVE': 'to-17',
    'RIVERBED': 'to-18',
    'DIVER_SURVEY': 'to-19',
    'PIG_TRAP': 'to-20',
    'PIPELINE_CROSSING': 'to-21',
    'MAIN_PIPELINE': 'to-22',
    'AIR_COOLER': 'to-23',
    'PIPELINE_VALVE': 'to-24',
    'TANK': 'to-25',
    'UNDERGROUND_TANK': 'to-25',
    'WELLHEAD_PIPING': 'to-26',
    'WELLHEAD_TREE': 'to-27',
    'BOILER': 'to-28',
    'PU_UNIT': 'to-29',
    'BOILER_AUX': 'to-30',
    'GAS_PIPELINE_GX': 'to-31',
    'ABOVEGROUND_PIPELINE': 'to-32',
    'UNDERGROUND_PIPELINE': 'to-33',
    'VENTILATION': 'to-34',
    'PRG': 'to-35',
    'POWER_STATION': 'to-36',
    'GIS_STATION': 'to-37',
    'AUX_EQUIPMENT': 'to-38',
    'CHIMNEY': 'to-39',
    'METERING': 'to-40',
    'BUILDINGS': 'to-41',
    'SWITCHGEAR': 'to-42',
    'WATER_TANK': 'to-43',
    'FLARE': 'to-44',
  };

  static InspectionProfile forFormId(String? formId) {
    final id = (formId ?? '').trim().toLowerCase();
    if (id.isEmpty) return InspectionProfile.vessel;
    return _formOverrides[id] ?? InspectionProfile.generic;
  }

  static InspectionProfile forFamily(String? family) {
    return _familyToProfile[family ?? ''] ?? InspectionProfile.generic;
  }

  static bool isPipeline(InspectionProfile p) => p == InspectionProfile.pipeline;
  static bool isCrane(InspectionProfile p) => p == InspectionProfile.crane;
  static bool isVessel(InspectionProfile p) => p == InspectionProfile.vessel;
  static bool isTank(InspectionProfile p) => p == InspectionProfile.tank;

  /// Показывать ЗРА/СППК сосуда только для vessel.
  static bool usesVesselSafetyDevices(InspectionProfile p) =>
      p == InspectionProfile.vessel;

  /// Поля «как у сосуда» (давления, толщина корпуса) — vessel/tank/boiler.
  static bool usesPressureVesselFields(InspectionProfile p) =>
      p == InspectionProfile.vessel ||
      p == InspectionProfile.tank ||
      p == InspectionProfile.boiler;

  static String objectLabel(InspectionProfile p, String formTitle) {
    switch (p) {
      case InspectionProfile.vessel:
        return 'сосуда / аппарата';
      case InspectionProfile.pipeline:
        return 'трубопровода';
      case InspectionProfile.crane:
        return 'подъёмного сооружения';
      case InspectionProfile.tank:
        return 'резервуара';
      case InspectionProfile.boiler:
        return 'котла';
      case InspectionProfile.machinery:
        return 'агрегата / машины';
      case InspectionProfile.electrical:
        return 'электрооборудования';
      case InspectionProfile.valve:
        return 'арматуры';
      case InspectionProfile.tower:
        return 'башни / трубы / факела';
      case InspectionProfile.station:
        return 'станции / узла';
      case InspectionProfile.generic:
        return formTitle;
    }
  }

  static String nameFieldLabel(InspectionProfile p) {
    switch (p) {
      case InspectionProfile.pipeline:
        return 'Наименование трубопровода';
      case InspectionProfile.crane:
        return 'Наименование подъёмного сооружения';
      case InspectionProfile.tank:
        return 'Наименование резервуара';
      case InspectionProfile.boiler:
        return 'Наименование котла';
      case InspectionProfile.machinery:
        return 'Наименование агрегата';
      case InspectionProfile.electrical:
        return 'Наименование электрооборудования';
      case InspectionProfile.valve:
        return 'Наименование арматуры / узла';
      case InspectionProfile.tower:
        return 'Наименование башни / трубы / факела';
      case InspectionProfile.station:
        return 'Наименование станции / объекта';
      case InspectionProfile.vessel:
        return 'Наименование сосуда';
      case InspectionProfile.generic:
        return 'Наименование объекта';
    }
  }

  static String page5Title(InspectionProfile p) {
    switch (p) {
      case InspectionProfile.pipeline:
        return 'Сварные соединения, ЭХЗ и геометрия';
      case InspectionProfile.crane:
        return 'Устройства безопасности ГПМ';
      case InspectionProfile.tank:
        return 'Пояса, швы и элементы резервуара';
      case InspectionProfile.boiler:
        return 'Элементы котла и арматура';
      case InspectionProfile.machinery:
        return 'Узлы агрегата и контрольные точки';
      case InspectionProfile.electrical:
        return 'Узлы и точки контроля электрооборудования';
      case InspectionProfile.valve:
        return 'Элементы арматуры / обвязки';
      case InspectionProfile.tower:
        return 'Пояса и элементы ствола';
      case InspectionProfile.station:
        return 'Узлы станции и точки контроля';
      case InspectionProfile.vessel:
        return 'ЗРА и предохранительные клапаны';
      case InspectionProfile.generic:
        return 'Элементы объекта и точки контроля';
    }
  }
}
