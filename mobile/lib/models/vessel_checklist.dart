// Модель данных для чек-листа обследования сосуда

class VesselChecklist {
  // Основная информация
  String? inspectionDate;
  String? inspectionType; // VISUAL, NDT, QUESTIONNAIRE, EXPERTISE
  String? executors; // Исполнители
  String? organization; // Организация (НГДУ, цех, месторождение)
  
  // Перечень документов (17 пунктов)
  Map<String, bool> documents = {}; // Ключ - номер документа, значение - наличие
  // Доп. сведения по документам (номер и дата)
  Map<String, Map<String, String>> documentsInfo = {}; // { "1": {number: "...", date: "YYYY-MM-DD"} }

  // Данные по ОПО (пункты 1-9). Если false — показываем/заполняем только документы 10-17.
  bool includeOpoData = true;
  
  // Карта обследования
  String? vesselName; // Наименование сосуда
  String? serialNumber; // Заводской номер
  String? regNumber; // Регистрационный номер
  String? manufacturer; // Изготовитель
  String? manufactureYear; // Год изготовления
  String? diameter; // Диаметр сосуда
  String? workingPressure; // Рабочее давление
  String? wallThickness; // Толщина стенки (обечайка / днище)
  // Краткая техническая характеристика (таблица 6)
  String? purpose; // Назначение
  String? commissioningYear; // Год ввода в эксплуатацию
  String? designPressure; // Расчётное давление, МПа
  String? testPressure; // Пробное давление, МПа
  String? workingTemperature; // Допустимая рабочая температура, ℃
  String? designTemperature; // Расчётная температура, ℃
  String? workingMedium; // Наименование рабочей среды
  String? mediumCharacteristics; // Характеристика рабочей среды
  String? vesselGroup; // Группа сосуда
  String? mediumGroup; // Группа рабочей среды
  String? corrosionAllowance; // Прибавка для компенсации коррозии, мм
  // Анализ результатов предыдущих обследований
  String? previousInspectionResult;
  
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

  // Инженеры по видам обследований (ВИК/УЗК/УЗТ/ПВК и др.)
  List<InspectionEngineer> inspectionEngineers = [];
  
  // Выбранные методы контроля (список кодов: VIK, UZK, UZT, PVK)
  List<String> ndtMethods = [];

  // Дефекты ВИК с фото и размерами
  List<VisualDefect> visualDefects = [];
  
  // Схема контроля (фото/рисунок)
  String? controlSchemeImage;
  
  // Заключение
  String? conclusion;
  
  // Дополнительные данные (JSON)
  Map<String, dynamic>? additionalData;
  
  VesselChecklist();

  static bool? _asBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return null;
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll(',', '.').trim();
    return double.tryParse(s);
  }
  
  Map<String, dynamic> toJson() {
    return {
      'equipment_type': 'VESSEL', // Тип оборудования для правильного определения при синхронизации
      'inspection_date': inspectionDate,
      'inspection_type': inspectionType,
      'executors': executors,
      'organization': organization,
      'documents': documents,
      'documents_info': documentsInfo.map((k, v) {
        final present = documents[k] ?? false;
        return MapEntry(k, {
          'present': present,
          'number': (v['number'] ?? ''),
          'date': (v['date'] ?? ''),
        });
      }),
      'include_opo_data': includeOpoData,
      'vessel_name': vesselName,
      'serial_number': serialNumber,
      'reg_number': regNumber,
      'manufacturer': manufacturer,
      'manufacture_year': manufactureYear,
      'diameter': diameter,
      'working_pressure': workingPressure,
      'wall_thickness': wallThickness,
      'purpose': purpose,
      'commissioning_year': commissioningYear,
      'design_pressure': designPressure,
      'test_pressure': testPressure,
      'working_temperature': workingTemperature,
      'design_temperature': designTemperature,
      'working_medium': workingMedium,
      'medium_characteristics': mediumCharacteristics,
      'vessel_group': vesselGroup,
      'medium_group': mediumGroup,
      'corrosion_allowance': corrosionAllowance,
      'previous_inspection_result': previousInspectionResult,
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
      'inspection_engineers': inspectionEngineers.map((e) => e.toJson()).toList(),
      'ndt_methods': ndtMethods, // Выбранные методы контроля
      'visual_defects': visualDefects.map((e) => e.toJson()).toList(),
      'control_scheme_image': controlSchemeImage,
      'conclusion': conclusion,
      'additional_data': additionalData,
    };
  }
  
  factory VesselChecklist.fromJson(Map<String, dynamic> json) {
    final checklist = VesselChecklist();

    checklist.inspectionDate = json['inspection_date'] as String?;
    checklist.inspectionType = json['inspection_type'] as String?;
    checklist.executors = json['executors'] as String?;
    checklist.organization = json['organization'] as String?;

    checklist.includeOpoData = _asBool(json['include_opo_data']) ?? true;

    final docsRaw = json['documents'];
    if (docsRaw is Map) {
      final m = Map<String, dynamic>.from(docsRaw);
      checklist.documents = m.map((k, v) {
        if (v is Map) {
          final mv = Map<String, dynamic>.from(v);
          final present = _asBool(mv['present']) ?? _asBool(mv['has']) ?? _asBool(mv['value']) ?? false;
          return MapEntry(k.toString(), present);
        }
        return MapEntry(k.toString(), (_asBool(v) ?? false));
      });
    } else {
      checklist.documents = {};
    }

    final docsInfoRaw = json['documents_info'];
    if (docsInfoRaw is Map) {
      final m = Map<String, dynamic>.from(docsInfoRaw);
      checklist.documentsInfo = m.map((k, v) {
        if (v is Map) {
          final mv = Map<String, dynamic>.from(v);
          if (!checklist.documents.containsKey(k.toString())) {
            final present = _asBool(mv['present']) ?? _asBool(mv['has']) ?? _asBool(mv['value']);
            if (present != null) {
              checklist.documents[k.toString()] = present;
            }
          }
          return MapEntry(
            k.toString(),
            {
              'number': (mv['number'] ?? mv['doc_number'] ?? '').toString(),
              'date': (mv['date'] ?? mv['doc_date'] ?? '').toString(),
            },
          );
        }
        return MapEntry(k.toString(), {'number': '', 'date': ''});
      });
    } else {
      checklist.documentsInfo = {};
    }

    checklist.vesselName = json['vessel_name'] as String?;
    checklist.serialNumber = json['serial_number'] as String?;
    checklist.regNumber = json['reg_number'] as String?;
    checklist.manufacturer = json['manufacturer'] as String?;
    checklist.manufactureYear = json['manufacture_year'] as String?;
    checklist.diameter = json['diameter'] as String?;
    checklist.workingPressure = json['working_pressure'] as String?;
    checklist.wallThickness = json['wall_thickness'] as String?;
    checklist.purpose = json['purpose'] as String?;
    checklist.commissioningYear = json['commissioning_year'] as String?;
    checklist.designPressure = json['design_pressure'] as String?;
    checklist.testPressure = json['test_pressure'] as String?;
    checklist.workingTemperature = json['working_temperature'] as String?;
    checklist.designTemperature = json['design_temperature'] as String?;
    checklist.workingMedium = json['working_medium'] as String?;
    checklist.mediumCharacteristics = json['medium_characteristics'] as String?;
    checklist.vesselGroup = json['vessel_group'] as String?;
    checklist.mediumGroup = json['medium_group'] as String?;
    checklist.corrosionAllowance = json['corrosion_allowance'] as String?;
    checklist.previousInspectionResult = json['previous_inspection_result'] as String?;

    checklist.factoryPlatePhoto = json['factory_plate_photo'] as String?;
    checklist.controlSchemeImage = json['control_scheme_image'] as String?;

    checklist.matchesDrawing = _asBool(json['matches_drawing']);
    checklist.hasThermalInsulation = _asBool(json['has_thermal_insulation']);
    checklist.anticorrosionCoatingState = json['anticorrosion_coating_state'] as String?;
    checklist.supportState = json['support_state'] as String?;
    checklist.fastenersState = json['fasteners_state'] as String?;
    checklist.hasFlangeMisalignment = _asBool(json['has_flange_misalignment']);
    checklist.hasNozzleMisalignment = _asBool(json['has_nozzle_misalignment']);
    checklist.hasVesselRepairs = _asBool(json['has_vessel_repairs']);
    checklist.hasTpaRepairs = _asBool(json['has_tpa_repairs']);
    checklist.internalDevicesState = json['internal_devices_state'] as String?;

    // ЗРА
    final zraRaw = json['zra_items'];
    if (zraRaw is List) {
      checklist.zraItems = zraRaw
          .whereType<Map>()
          .map((e) => ZraItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    // СППК
    final sppkRaw = json['sppk_items'];
    if (sppkRaw is List) {
      checklist.sppkItems = sppkRaw
          .whereType<Map>()
          .map((e) => SppkItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final swRaw = json['switching_device'];
    if (swRaw is Map) {
      checklist.switchingDevice = SwitchingDevice.fromJson(Map<String, dynamic>.from(swRaw));
    }

    final gaugeRaw = json['gauge'];
    if (gaugeRaw is Map) {
      checklist.gauge = Gauge.fromJson(Map<String, dynamic>.from(gaugeRaw));
    }

    final lsRaw = json['level_sensor'];
    if (lsRaw is Map) {
      checklist.levelSensor = LevelSensor.fromJson(Map<String, dynamic>.from(lsRaw));
    }

    final laRaw = json['level_alarm'];
    if (laRaw is Map) {
      checklist.levelAlarm = LevelAlarm.fromJson(Map<String, dynamic>.from(laRaw));
    }

    final viRaw = json['valve_inspections'];
    if (viRaw is List) {
      checklist.valveInspections = viRaw
          .whereType<Map>()
          .map((e) => ValveInspection.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final ovRaw = json['ovality_measurements'];
    if (ovRaw is List) {
      checklist.ovalityMeasurements = ovRaw
          .whereType<Map>()
          .map((e) => OvalityMeasurement.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final defRaw = json['deflection_measurements'];
    if (defRaw is List) {
      checklist.deflectionMeasurements = defRaw
          .whereType<Map>()
          .map((e) => DeflectionMeasurement.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    checklist.hasLocalDeformations = _asBool(json['has_local_deformations']);
    checklist.hasExternalDefects = _asBool(json['has_external_defects']);
    checklist.hasInternalDefects = _asBool(json['has_internal_defects']);
    checklist.hasArmatureDefects = _asBool(json['has_armature_defects']);

    final htRaw = json['hardness_tests'];
    if (htRaw is List) {
      checklist.hardnessTests = htRaw
          .whereType<Map>()
          .map((e) => HardnessTest.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final wiRaw = json['weld_inspections'];
    if (wiRaw is List) {
      checklist.weldInspections = wiRaw
          .whereType<Map>()
          .map((e) => WeldInspection.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final tmRaw = json['thickness_measurements'];
    if (tmRaw is List) {
      checklist.thicknessMeasurements = tmRaw
          .whereType<Map>()
          .map((e) => ThicknessMeasurement.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final ieRaw = json['inspection_engineers'];
    if (ieRaw is List) {
      checklist.inspectionEngineers = ieRaw
          .whereType<Map>()
          .map((e) => InspectionEngineer.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final vdRaw = json['visual_defects'];
    if (vdRaw is List) {
      checklist.visualDefects = vdRaw
          .whereType<Map>()
          .map((e) => VisualDefect.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    checklist.conclusion = json['conclusion'] as String?;
    
    final adRaw = json['additional_data'];
    if (adRaw is Map) {
      checklist.additionalData = Map<String, dynamic>.from(adRaw);
    }

    return checklist;
  }
}

class ZraItem {
  String? quantity;
  String? typeSize;
  String? techNumber;
  String? serialNumber;
  String? locationOnScheme;

  ZraItem();
  
  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'type_size': typeSize,
    'tech_number': techNumber,
    'serial_number': serialNumber,
    'location_on_scheme': locationOnScheme,
  };

  factory ZraItem.fromJson(Map<String, dynamic> json) {
    final item = ZraItem();
    item.quantity = json['quantity']?.toString();
    item.typeSize = json['type_size']?.toString();
    item.techNumber = json['tech_number']?.toString();
    item.serialNumber = json['serial_number']?.toString();
    item.locationOnScheme = json['location_on_scheme']?.toString();
    return item;
  }
}

class SppkItem {
  String? quantity;
  String? typeSize;
  String? techNumber;
  String? serialNumber;
  String? locationOnScheme;

  SppkItem();
  
  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'type_size': typeSize,
    'tech_number': techNumber,
    'serial_number': serialNumber,
    'location_on_scheme': locationOnScheme,
  };

  factory SppkItem.fromJson(Map<String, dynamic> json) {
    final item = SppkItem();
    item.quantity = json['quantity']?.toString();
    item.typeSize = json['type_size']?.toString();
    item.techNumber = json['tech_number']?.toString();
    item.serialNumber = json['serial_number']?.toString();
    item.locationOnScheme = json['location_on_scheme']?.toString();
    return item;
  }
}

class SwitchingDevice {
  String? quantity;
  String? typeSize;
  String? techNumber;
  String? serialNumber;
  bool? hasVik;
  bool? hasUzt;

  SwitchingDevice();
  
  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'type_size': typeSize,
    'tech_number': techNumber,
    'serial_number': serialNumber,
    'has_vik': hasVik,
    'has_uzt': hasUzt,
  };

  factory SwitchingDevice.fromJson(Map<String, dynamic> json) {
    final d = SwitchingDevice();
    d.quantity = json['quantity']?.toString();
    d.typeSize = json['type_size']?.toString();
    d.techNumber = json['tech_number']?.toString();
    d.serialNumber = json['serial_number']?.toString();
    d.hasVik = VesselChecklist._asBool(json['has_vik']);
    d.hasUzt = VesselChecklist._asBool(json['has_uzt']);
    return d;
  }
}

class Gauge {
  bool? hasMetrologicalVerification;
  String? verificationDate;
  String? serialNumber;

  Gauge();
  
  Map<String, dynamic> toJson() => {
    'has_metrological_verification': hasMetrologicalVerification,
    'verification_date': verificationDate,
    'serial_number': serialNumber,
  };

  factory Gauge.fromJson(Map<String, dynamic> json) {
    final g = Gauge();
    g.hasMetrologicalVerification =
        VesselChecklist._asBool(json['has_metrological_verification']);
    g.verificationDate = json['verification_date']?.toString();
    g.serialNumber = json['serial_number']?.toString();
    return g;
  }
}

class LevelSensor {
  String? type;
  String? serialNumber;
  String? location;

  LevelSensor();
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'serial_number': serialNumber,
    'location': location,
  };

  factory LevelSensor.fromJson(Map<String, dynamic> json) {
    final s = LevelSensor();
    s.type = json['type']?.toString();
    s.serialNumber = json['serial_number']?.toString();
    s.location = json['location']?.toString();
    return s;
  }
}

class LevelAlarm {
  String? type;
  String? serialNumber;
  String? location;

  LevelAlarm();
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'serial_number': serialNumber,
    'location': location,
  };

  factory LevelAlarm.fromJson(Map<String, dynamic> json) {
    final a = LevelAlarm();
    a.type = json['type']?.toString();
    a.serialNumber = json['serial_number']?.toString();
    a.location = json['location']?.toString();
    return a;
  }
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

  factory ValveInspection.fromJson(Map<String, dynamic> json) {
    return ValveInspection(
      elementName: (json['element_name'] ?? '').toString(),
      locationOnScheme: (json['location_on_scheme'] ?? '').toString(),
      technicalState: json['technical_state']?.toString(),
      hasUzt: VesselChecklist._asBool(json['has_uzt']),
    );
  }
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

  factory OvalityMeasurement.fromJson(Map<String, dynamic> json) {
    return OvalityMeasurement(
      sectionNumber: (json['section_number'] ?? '').toString(),
      maxDiameter: VesselChecklist._asDouble(json['max_diameter']),
      minDiameter: VesselChecklist._asDouble(json['min_diameter']),
      deviationPercent: VesselChecklist._asDouble(json['deviation_percent']),
    );
  }
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

  factory DeflectionMeasurement.fromJson(Map<String, dynamic> json) {
    return DeflectionMeasurement(
      sectionNumber: (json['section_number'] ?? '').toString(),
      deflectionMm: VesselChecklist._asDouble(json['deflection_mm']),
      deflectionPercent: VesselChecklist._asDouble(json['deflection_percent']),
    );
  }
}

class HardnessTest {
  String weldNumber;
  String? areaNumber;
  String? location; // Обечайка, Днище 1, Днище 2 — для группировки в протоколе
  String? allowedHardnessBase;
  String? allowedHardnessWeld;
  String? hardnessBase;
  String? hardnessWeld;
  String? hardnessHaz;
  
  HardnessTest({required this.weldNumber});
  
  Map<String, dynamic> toJson() => {
    'weld_number': weldNumber,
    'area_number': areaNumber,
    'location': location,
    'allowed_hardness_base': allowedHardnessBase,
    'allowed_hardness_weld': allowedHardnessWeld,
    'hardness_base': hardnessBase,
    'hardness_weld': hardnessWeld,
    'hardness_haz': hardnessHaz,
  };

  factory HardnessTest.fromJson(Map<String, dynamic> json) {
    final t = HardnessTest(weldNumber: (json['weld_number'] ?? '').toString());
    t.areaNumber = json['area_number']?.toString();
    t.location = json['location']?.toString();
    t.allowedHardnessBase = json['allowed_hardness_base']?.toString();
    t.allowedHardnessWeld = json['allowed_hardness_weld']?.toString();
    t.hardnessBase = json['hardness_base']?.toString();
    t.hardnessWeld = json['hardness_weld']?.toString();
    t.hardnessHaz = json['hardness_haz']?.toString();
    return t;
  }
}

class WeldInspection {
  String weldNumber;
  String? locationOnControlMap;
  String? pvkDefect;
  String? uzkDefect;
  String? conclusion; // годен, ремонт и т.д.
  double? xPercent; // Позиция на схеме X (0–100)
  double? yPercent; // Позиция на схеме Y (0–100)
  
  WeldInspection({required this.weldNumber});
  
  Map<String, dynamic> toJson() => {
    'weld_number': weldNumber,
    'location_on_control_map': locationOnControlMap,
    'pvk_defect': pvkDefect,
    'uzk_defect': uzkDefect,
    'conclusion': conclusion,
    'x_percent': xPercent,
    'y_percent': yPercent,
  };

  factory WeldInspection.fromJson(Map<String, dynamic> json) {
    final w = WeldInspection(weldNumber: (json['weld_number'] ?? '').toString());
    w.locationOnControlMap = json['location_on_control_map']?.toString();
    w.pvkDefect = json['pvk_defect']?.toString();
    w.uzkDefect = json['uzk_defect']?.toString();
    w.conclusion = json['conclusion']?.toString();
    w.xPercent = VesselChecklist._asDouble(json['x_percent']);
    w.yPercent = VesselChecklist._asDouble(json['y_percent']);
    return w;
  }
}

class ThicknessMeasurement {
  String location; // Обечайка, днище, патрубок
  String sectionNumber;
  double? thickness;
  double? minAllowedThickness;
  String? comment;
  double? xPercent; // Позиция на схеме X
  double? yPercent; // Позиция на схеме Y
  List<String> photos = []; // Фото замеров для отчёта

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
    'photos': photos,
  };

  factory ThicknessMeasurement.fromJson(Map<String, dynamic> json) {
    final t = ThicknessMeasurement(
      location: (json['location'] ?? '').toString(),
      sectionNumber: (json['section_number'] ?? '').toString(),
    );
    t.thickness = VesselChecklist._asDouble(json['thickness']);
    t.minAllowedThickness = VesselChecklist._asDouble(json['min_allowed_thickness']);
    t.comment = json['comment']?.toString();
    t.xPercent = VesselChecklist._asDouble(json['x_percent']);
    t.yPercent = VesselChecklist._asDouble(json['y_percent']);
    final ph = json['photos'];
    if (ph is List) {
      t.photos = ph.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return t;
  }
}

class InspectionEngineer {
  String method; // ВИК, УЗК, УЗТ, ПВК и т.д.
  String? engineerId;
  String? fullName;
  String? certificateNumber;
  String? validUntil;

  InspectionEngineer({required this.method});

  Map<String, dynamic> toJson() => {
    'method': method,
    'engineer_id': engineerId,
    'full_name': fullName,
    'certificate_number': certificateNumber,
    'valid_until': validUntil,
  };

  factory InspectionEngineer.fromJson(Map<String, dynamic> json) {
    final e = InspectionEngineer(method: (json['method'] ?? '').toString());
    e.engineerId = json['engineer_id']?.toString();
    e.fullName = json['full_name']?.toString();
    e.certificateNumber = json['certificate_number']?.toString();
    e.validUntil = json['valid_until']?.toString();
    return e;
  }
}

class VisualDefect {
  String? defectType; // коррозия, вмятина, трещина, и т.д.
  String? location;
  String? size;
  String? description;
  List<String> photos = [];

  VisualDefect();

  Map<String, dynamic> toJson() => {
    'defect_type': defectType,
    'location': location,
    'size': size,
    'description': description,
    'photos': photos,
  };

  factory VisualDefect.fromJson(Map<String, dynamic> json) {
    final d = VisualDefect();
    d.defectType = json['defect_type']?.toString();
    d.location = json['location']?.toString();
    d.size = json['size']?.toString();
    d.description = json['description']?.toString();
    final ph = json['photos'];
    if (ph is List) {
      d.photos = ph.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return d;
  }
}




