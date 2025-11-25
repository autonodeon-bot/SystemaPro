// Модель данных для чек-листа обследования сосуда

class VesselChecklist {
  // Основная информация
  String? inspectionDate;
  String? executors; // Исполнители
  String? organization; // Организация (НГДУ, цех, месторождение)
  
  // Перечень документов (17 пунктов)
  Map<String, bool> documents = {}; // Ключ - номер документа, значение - наличие
  
  // Карта обследования
  String? vesselName; // Наименование сосуда
  String? serialNumber; // Заводской номер
  String? regNumber; // Регистрационный номер
  String? manufacturer; // Изготовитель
  String? manufactureYear; // Год изготовления
  String? diameter; // Диаметр сосуда
  String? workingPressure; // Рабочее давление
  String? wallThickness; // Толщина стенки (обечайка / днище)
  
  // Фото заводской таблички
  String? factoryPlatePhoto;
  
  // Проверки
  bool? matchesDrawing; // Соответствует ли сосуду чертежу
  bool? hasThermalInsulation; // Наличие тепловой изоляции
  String? anticorrosionCoatingState; // Состояние антикоррозионного покрытия
  String? supportState; // Состояние опор
  String? fastenersState; // Состояние крепежных элементов
  bool? hasFlangeMisalignment; // Перекосы фланцевых соединений
  bool? hasNozzleMisalignment; // Непрямолинейность патрубков
  bool? hasVesselRepairs; // Имеются ли места ремонта сосуда
  bool? hasTpaRepairs; // Имеются ли места ремонта ТПА
  String? internalDevicesState; // Состояние внутренних устройств
  
  // ЗРА (Запорно-регулирующая арматура)
  List<ZraItem> zraItems = [];
  
  // СППК (Система предохранительных клапанов)
  List<SppkItem> sppkItems = [];
  
  // Переключающее устройство
  SwitchingDevice? switchingDevice;
  
  // Манометр
  Gauge? gauge;
  
  // Датчик уровня
  LevelSensor? levelSensor;
  
  // Сигнализатор уровня
  LevelAlarm? levelAlarm;
  
  // ВИК и УЗТ клапанов
  List<ValveInspection> valveInspections = [];
  
  // Измерительный контроль - овальность
  List<OvalityMeasurement> ovalityMeasurements = [];
  
  // Измерительный контроль - прогиб
  List<DeflectionMeasurement> deflectionMeasurements = [];
  
  // Дефекты
  bool? hasLocalDeformations; // Локально деформированные зоны
  bool? hasExternalDefects; // Дефекты при наружном осмотре
  bool? hasInternalDefects; // Дефекты при внутреннем осмотре
  bool? hasArmatureDefects; // Дефекты арматуры
  
  // Результаты контроля твердости
  List<HardnessTest> hardnessTests = [];
  
  // Результаты ПВК (МК) и УЗК
  List<WeldInspection> weldInspections = [];
  
  // УЗТ (Ультразвуковая толщинометрия)
  List<ThicknessMeasurement> thicknessMeasurements = [];
  
  // Схема контроля (фото/рисунок)
  String? controlSchemeImage;
  
  // Заключение
  String? conclusion;
  
  VesselChecklist();
  
  Map<String, dynamic> toJson() {
    return {
      'inspection_date': inspectionDate,
      'executors': executors,
      'organization': organization,
      'documents': documents,
      'vessel_name': vesselName,
      'serial_number': serialNumber,
      'reg_number': regNumber,
      'manufacturer': manufacturer,
      'manufacture_year': manufactureYear,
      'diameter': diameter,
      'working_pressure': workingPressure,
      'wall_thickness': wallThickness,
      'factory_plate_photo': factoryPlatePhoto,
      'matches_drawing': matchesDrawing,
      'has_thermal_insulation': hasThermalInsulation,
      'anticorrosion_coating_state': anticorrosionCoatingState,
      'support_state': supportState,
      'fasteners_state': fastenersState,
      'has_flange_misalignment': hasFlangeMisalignment,
      'has_nozzle_misalignment': hasNozzleMisalignment,
      'has_vessel_repairs': hasVesselRepairs,
      'has_tpa_repairs': hasTpaRepairs,
      'internal_devices_state': internalDevicesState,
      'zra_items': zraItems.map((e) => e.toJson()).toList(),
      'sppk_items': sppkItems.map((e) => e.toJson()).toList(),
      'switching_device': switchingDevice?.toJson(),
      'gauge': gauge?.toJson(),
      'level_sensor': levelSensor?.toJson(),
      'level_alarm': levelAlarm?.toJson(),
      'valve_inspections': valveInspections.map((e) => e.toJson()).toList(),
      'ovality_measurements': ovalityMeasurements.map((e) => e.toJson()).toList(),
      'deflection_measurements': deflectionMeasurements.map((e) => e.toJson()).toList(),
      'has_local_deformations': hasLocalDeformations,
      'has_external_defects': hasExternalDefects,
      'has_internal_defects': hasInternalDefects,
      'has_armature_defects': hasArmatureDefects,
      'hardness_tests': hardnessTests.map((e) => e.toJson()).toList(),
      'weld_inspections': weldInspections.map((e) => e.toJson()).toList(),
      'thickness_measurements': thicknessMeasurements.map((e) => e.toJson()).toList(),
      'control_scheme_image': controlSchemeImage,
      'conclusion': conclusion,
    };
  }
  
  factory VesselChecklist.fromJson(Map<String, dynamic> json) {
    final checklist = VesselChecklist();
    checklist.inspectionDate = json['inspection_date'] as String?;
    checklist.executors = json['executors'] as String?;
    checklist.organization = json['organization'] as String?;
    checklist.documents = Map<String, bool>.from(json['documents'] ?? {});
    checklist.vesselName = json['vessel_name'] as String?;
    checklist.serialNumber = json['serial_number'] as String?;
    checklist.regNumber = json['reg_number'] as String?;
    checklist.manufacturer = json['manufacturer'] as String?;
    checklist.manufactureYear = json['manufacture_year'] as String?;
    checklist.diameter = json['diameter'] as String?;
    checklist.workingPressure = json['working_pressure'] as String?;
    checklist.wallThickness = json['wall_thickness'] as String?;
    // ... остальные поля
    return checklist;
  }
}

class ZraItem {
  String? quantity;
  String? typeSize;
  String? techNumber;
  String? serialNumber;
  String? locationOnScheme;
  
  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'type_size': typeSize,
    'tech_number': techNumber,
    'serial_number': serialNumber,
    'location_on_scheme': locationOnScheme,
  };
}

class SppkItem {
  String? quantity;
  String? typeSize;
  String? techNumber;
  String? serialNumber;
  String? locationOnScheme;
  
  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'type_size': typeSize,
    'tech_number': techNumber,
    'serial_number': serialNumber,
    'location_on_scheme': locationOnScheme,
  };
}

class SwitchingDevice {
  String? quantity;
  String? typeSize;
  String? techNumber;
  String? serialNumber;
  bool? hasVik;
  bool? hasUzt;
  
  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'type_size': typeSize,
    'tech_number': techNumber,
    'serial_number': serialNumber,
    'has_vik': hasVik,
    'has_uzt': hasUzt,
  };
}

class Gauge {
  bool? hasMetrologicalVerification;
  String? verificationDate;
  String? serialNumber;
  
  Map<String, dynamic> toJson() => {
    'has_metrological_verification': hasMetrologicalVerification,
    'verification_date': verificationDate,
    'serial_number': serialNumber,
  };
}

class LevelSensor {
  String? type;
  String? serialNumber;
  String? location;
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'serial_number': serialNumber,
    'location': location,
  };
}

class LevelAlarm {
  String? type;
  String? serialNumber;
  String? location;
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'serial_number': serialNumber,
    'location': location,
  };
}

class ValveInspection {
  String elementName;
  String locationOnScheme;
  String? technicalState;
  bool? hasUzt;
  
  ValveInspection({
    required this.elementName,
    required this.locationOnScheme,
    this.technicalState,
    this.hasUzt,
  });
  
  Map<String, dynamic> toJson() => {
    'element_name': elementName,
    'location_on_scheme': locationOnScheme,
    'technical_state': technicalState,
    'has_uzt': hasUzt,
  };
}

class OvalityMeasurement {
  String sectionNumber;
  double? maxDiameter;
  double? minDiameter;
  double? deviationPercent;
  
  OvalityMeasurement({
    required this.sectionNumber,
    this.maxDiameter,
    this.minDiameter,
    this.deviationPercent,
  });
  
  Map<String, dynamic> toJson() => {
    'section_number': sectionNumber,
    'max_diameter': maxDiameter,
    'min_diameter': minDiameter,
    'deviation_percent': deviationPercent,
  };
}

class DeflectionMeasurement {
  String sectionNumber;
  double? deflectionMm;
  double? deflectionPercent;
  
  DeflectionMeasurement({
    required this.sectionNumber,
    this.deflectionMm,
    this.deflectionPercent,
  });
  
  Map<String, dynamic> toJson() => {
    'section_number': sectionNumber,
    'deflection_mm': deflectionMm,
    'deflection_percent': deflectionPercent,
  };
}

class HardnessTest {
  String weldNumber;
  String? areaNumber;
  String? allowedHardnessBase;
  String? allowedHardnessWeld;
  String? hardnessBase;
  String? hardnessWeld;
  String? hardnessHaz;
  
  HardnessTest({required this.weldNumber});
  
  Map<String, dynamic> toJson() => {
    'weld_number': weldNumber,
    'area_number': areaNumber,
    'allowed_hardness_base': allowedHardnessBase,
    'allowed_hardness_weld': allowedHardnessWeld,
    'hardness_base': hardnessBase,
    'hardness_weld': hardnessWeld,
    'hardness_haz': hardnessHaz,
  };
}

class WeldInspection {
  String weldNumber;
  String? locationOnControlMap;
  String? pvkDefect;
  String? uzkDefect;
  String? conclusion; // годен, ремонт и т.д.
  
  WeldInspection({required this.weldNumber});
  
  Map<String, dynamic> toJson() => {
    'weld_number': weldNumber,
    'location_on_control_map': locationOnControlMap,
    'pvk_defect': pvkDefect,
    'uzk_defect': uzkDefect,
    'conclusion': conclusion,
  };
}

class ThicknessMeasurement {
  String location; // Обечайка, днище, патрубок
  String sectionNumber;
  double? thickness;
  double? minAllowedThickness;
  String? comment;
  double? xPercent; // Позиция на схеме X
  double? yPercent; // Позиция на схеме Y
  
  ThicknessMeasurement({
    required this.location,
    required this.sectionNumber,
  });
  
  Map<String, dynamic> toJson() => {
    'location': location,
    'section_number': sectionNumber,
    'thickness': thickness,
    'min_allowed_thickness': minAllowedThickness,
    'comment': comment,
    'x_percent': xPercent,
    'y_percent': yPercent,
  };
}




