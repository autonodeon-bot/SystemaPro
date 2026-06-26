// Модель данных для чек-листа обследования сосуда

class VesselChecklist {
  // Основная информация
  String? inspectionDate;
  String? inspectionType; // VISUAL, NDT, QUESTIONNAIRE, EXPERTISE
  /// Форма ТО: to-1, to-3, to-33 …
  String? reportFormId;
  String? reportFormTitle;
  String? executors; // Исполнители
  String? organization; // Организация (НГДУ, цех, месторождение)
  
  // Перечень документов (17 пунктов)
  Map<String, bool> documents = {}; // Ключ - номер документа, значение - наличие
  // Доп. сведения по документам (номер и дата)
  Map<String, Map<String, String>> documentsInfo = {}; // { "1": {number: "...", date: "YYYY-MM-DD"} }

  // Данные по ОПО (пункты 1-9). Если false — показываем/заполняем только документы 10-17.
  bool includeOpoData = true;

  /// VESSEL | GAS_SEPARATOR | UNDERGROUND_TANK | OIL_SETTLER — терминология отчёта
  String? equipmentTypeCode;
  
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
  List<PreviousInspectionRecord> previousInspections = [];

  // ЭПБ: паспортные данные (приложение Б)
  String? constructionType;
  String? volume;
  String? schemeIndex;
  List<VesselElement> vesselElements = [];
  List<HeatTreatmentRecord> heatTreatmentRecords = [];
  List<HydraulicTestRecord> hydraulicTestHistory = [];
  List<NdtControlRecord> ndtControlHistory = [];
  List<RepairRecord> repairHistory = [];
  List<FittingInstrument> fittingsAndInstruments = [];
  Map<String, dynamic>? calculationData;
  String? residualLifeText;
  
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

  // Множественные схемы контроля УЗТ (П.3.2)
  List<UztScheme> uztSchemes = [];

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

  /// Пункты документов, где допускается несколько комплектов (номер + дата + файл).
  static const Set<String> multiDocumentNumbers = {'15', '17'};

  List<Map<String, String>> getDocumentSets(String docNumber) {
    final setsRaw = additionalData?['document_sets'];
    if (setsRaw is Map) {
      final list = setsRaw[docNumber];
      if (list is List && list.isNotEmpty) {
        return list
            .whereType<Map>()
            .map((e) => <String, String>{
                  'number': (e['number'] ?? '').toString(),
                  'date': (e['date'] ?? '').toString(),
                })
            .toList();
      }
    }
    final info = documentsInfo[docNumber];
    if (info != null &&
        ((info['number'] ?? '').isNotEmpty || (info['date'] ?? '').isNotEmpty)) {
      return [Map<String, String>.from(info)];
    }
    return [];
  }

  void setDocumentSets(String docNumber, List<Map<String, String>> sets) {
    additionalData ??= {};
    final raw = additionalData!['document_sets'];
    if (raw is! Map) {
      additionalData!['document_sets'] = <String, dynamic>{};
    }
    (additionalData!['document_sets'] as Map)[docNumber] = sets
        .map((e) => {'number': e['number'] ?? '', 'date': e['date'] ?? ''})
        .toList();
    if (sets.isNotEmpty) {
      documentsInfo[docNumber] = Map<String, String>.from(sets.first);
    } else {
      documentsInfo.remove(docNumber);
    }
  }

  void ensureAtLeastOneDocumentSet(String docNumber) {
    if (getDocumentSets(docNumber).isEmpty) {
      setDocumentSets(docNumber, [
        {'number': '', 'date': ''},
      ]);
    }
  }

  static String documentFileKey(String docNumber, int setIndex) =>
      '${docNumber}_$setIndex';

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
      'equipment_type': equipmentTypeCode ?? 'VESSEL',
      'inspection_date': inspectionDate,
      'inspection_type': inspectionType,
      'report_form_id': reportFormId,
      'report_form_title': reportFormTitle,
      'executors': executors,
      'organization': organization,
      'documents': documents,
      'documents_info': documentsInfo.map((k, v) {
        final present = documents[k] ?? false;
        return MapEntry(k, {
          'present': present,
          'number': (v['number'] ?? ''),
          'date': (v['date'] ?? ''),
          'pages': (v['pages'] ?? ''),
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
      'previous_inspections': previousInspections.map((e) => e.toJson()).toList(),
      'construction_type': constructionType,
      'volume': volume,
      'scheme_index': schemeIndex,
      'vessel_elements': vesselElements.map((e) => e.toJson()).toList(),
      'heat_treatment_records': heatTreatmentRecords.map((e) => e.toJson()).toList(),
      'hydraulic_test_history': hydraulicTestHistory.map((e) => e.toJson()).toList(),
      'ndt_control_history': ndtControlHistory.map((e) => e.toJson()).toList(),
      'repair_history': repairHistory.map((e) => e.toJson()).toList(),
      'fittings_and_instruments': fittingsAndInstruments.map((e) => e.toJson()).toList(),
      'calculation_data': calculationData,
      'residual_life_text': residualLifeText,
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
      'uzt_schemes': uztSchemes.map((e) => e.toJson()).toList(),
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
    checklist.reportFormId = json['report_form_id'] as String?;
    checklist.reportFormTitle = json['report_form_title'] as String?;
    checklist.executors = json['executors'] as String?;
    checklist.organization = json['organization'] as String?;

    checklist.includeOpoData = _asBool(json['include_opo_data']) ?? true;
    checklist.equipmentTypeCode = json['equipment_type']?.toString();

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
    checklist.previousInspections = _parseList(
      json['previous_inspections'],
      PreviousInspectionRecord.fromJson,
    );
    checklist.constructionType = json['construction_type']?.toString();
    checklist.volume = json['volume']?.toString();
    checklist.schemeIndex = json['scheme_index']?.toString();
    checklist.residualLifeText = json['residual_life_text']?.toString();

    checklist.vesselElements = _parseList(json['vessel_elements'], VesselElement.fromJson);
    checklist.heatTreatmentRecords =
        _parseList(json['heat_treatment_records'], HeatTreatmentRecord.fromJson);
    checklist.hydraulicTestHistory =
        _parseList(json['hydraulic_test_history'], HydraulicTestRecord.fromJson);
    checklist.ndtControlHistory =
        _parseList(json['ndt_control_history'], NdtControlRecord.fromJson);
    checklist.repairHistory = _parseList(json['repair_history'], RepairRecord.fromJson);
    checklist.fittingsAndInstruments =
        _parseList(json['fittings_and_instruments'], FittingInstrument.fromJson);

    final calcRaw = json['calculation_data'];
    if (calcRaw is Map) {
      checklist.calculationData = Map<String, dynamic>.from(calcRaw);
    }

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

    final uztRaw = json['uzt_schemes'];
    if (uztRaw is List) {
      checklist.uztSchemes = uztRaw
          .whereType<Map>()
          .map((e) => UztScheme.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final ieRaw = json['inspection_engineers'];
    if (ieRaw is List) {
      checklist.inspectionEngineers = ieRaw
          .whereType<Map>()
          .map((e) => InspectionEngineer.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final ndtRaw = json['ndt_methods'];
    if (ndtRaw is List) {
      checklist.ndtMethods = ndtRaw.map((e) => e.toString()).toList();
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

  static List<T> _parseList<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => fromJson(Map<String, dynamic>.from(e)))
        .toList();
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
  String? location;
  String? allowedHardnessBase;
  String? allowedHardnessWeld;
  String? hardnessBase;
  String? hardnessWeld;
  String? hardnessHaz;
  String? hardnessBaseT1;
  String? hardnessBaseT5;
  String? hardnessHazT2;
  String? hardnessHazT4;
  
  HardnessTest({required this.weldNumber});
  
  Map<String, dynamic> toJson() => {
    'weld_number': weldNumber,
    'location': location ?? weldNumber,
    'area_number': areaNumber,
    'allowed_hardness_base': allowedHardnessBase,
    'allowed_hardness_weld': allowedHardnessWeld,
    'hardness_base': hardnessBase ?? hardnessBaseT1,
    'hardness_weld': hardnessWeld,
    'hardness_haz': hardnessHaz ?? hardnessHazT2,
    'hardness_base_t1': hardnessBaseT1 ?? hardnessBase,
    'hardness_base_t5': hardnessBaseT5 ?? hardnessBase,
    'hardness_haz_t2': hardnessHazT2 ?? hardnessHaz,
    'hardness_haz_t4': hardnessHazT4 ?? hardnessHaz,
  };

  factory HardnessTest.fromJson(Map<String, dynamic> json) {
    final t = HardnessTest(weldNumber: (json['weld_number'] ?? json['location'] ?? '').toString());
    t.areaNumber = json['area_number']?.toString();
    t.location = json['location']?.toString();
    t.allowedHardnessBase = json['allowed_hardness_base']?.toString();
    t.allowedHardnessWeld = json['allowed_hardness_weld']?.toString();
    t.hardnessBase = json['hardness_base']?.toString();
    t.hardnessWeld = json['hardness_weld']?.toString();
    t.hardnessHaz = json['hardness_haz']?.toString();
    t.hardnessBaseT1 = json['hardness_base_t1']?.toString();
    t.hardnessBaseT5 = json['hardness_base_t5']?.toString();
    t.hardnessHazT2 = json['hardness_haz_t2']?.toString();
    t.hardnessHazT4 = json['hardness_haz_t4']?.toString();
    return t;
  }
}

class WeldInspection {
  String weldNumber;
  String? locationOnControlMap;
  String? controlMethod; // MPK | UZK
  String? pvkDefect;
  String? uzkDefect;
  String? defectDescription;
  String? conclusion;
  double? xPercent;
  double? yPercent;
  
  WeldInspection({required this.weldNumber});
  
  Map<String, dynamic> toJson() => {
    'weld_number': weldNumber,
    'location_on_control_map': locationOnControlMap,
    'control_method': controlMethod,
    'pvk_defect': pvkDefect,
    'uzk_defect': uzkDefect,
    'defect_description': defectDescription ??
        (controlMethod?.toUpperCase() == 'UZK' ? uzkDefect : pvkDefect),
    'conclusion': conclusion,
    'x_percent': xPercent,
    'y_percent': yPercent,
  };

  factory WeldInspection.fromJson(Map<String, dynamic> json) {
    final w = WeldInspection(weldNumber: (json['weld_number'] ?? '').toString());
    w.locationOnControlMap = json['location_on_control_map']?.toString();
    w.controlMethod = json['control_method']?.toString() ?? json['method']?.toString();
    w.pvkDefect = json['pvk_defect']?.toString();
    w.uzkDefect = json['uzk_defect']?.toString();
    w.defectDescription = json['defect_description']?.toString();
    w.conclusion = json['conclusion']?.toString();
    w.xPercent = VesselChecklist._asDouble(json['x_percent']);
    w.yPercent = VesselChecklist._asDouble(json['y_percent']);
    return w;
  }
}

class ThicknessMeasurement {
  String location; // Наименование элемента (обечайка, днище, патрубок)
  String sectionNumber; // № точки
  double? nominalThickness; // Номинальная толщина, мм
  double? thickness; // Фактическая толщина, мм
  double? minAllowedThickness; // Отбраковочная толщина, мм
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
    'nominal_thickness': nominalThickness,
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
    t.nominalThickness = VesselChecklist._asDouble(json['nominal_thickness']);
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

/// Схема контроля УЗТ (связка «схема + таблица замеров»). П.3.2
class UztScheme {
  String label; // Название схемы, напр. «Схема 1 — Обечайка»
  String? schemeImagePath; // Путь к фото/схеме
  List<ThicknessMeasurement> measurements = [];

  UztScheme({required this.label});

  Map<String, dynamic> toJson() => {
        'label': label,
        'scheme_image_path': schemeImagePath,
        'measurements': measurements.map((e) => e.toJson()).toList(),
      };

  factory UztScheme.fromJson(Map<String, dynamic> json) {
    final s = UztScheme(label: (json['label'] ?? 'Схема').toString());
    s.schemeImagePath = json['scheme_image_path']?.toString();
    final mRaw = json['measurements'];
    if (mRaw is List) {
      s.measurements = mRaw
          .whereType<Map>()
          .map((e) => ThicknessMeasurement.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return s;
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

class VesselElement {
  String? name;
  String? diameterMm;
  String? lengthMm;
  String? wallThicknessMm;
  String? material;
  String? gost;
  String? weldData;

  VesselElement();

  Map<String, dynamic> toJson() => {
        'name': name,
        'diameter_mm': diameterMm,
        'length_mm': lengthMm,
        'wall_thickness_mm': wallThicknessMm,
        'material': material,
        'gost': gost,
        'weld_data': weldData,
      };

  factory VesselElement.fromJson(Map<String, dynamic> json) {
    final e = VesselElement();
    e.name = json['name']?.toString();
    e.diameterMm = json['diameter_mm']?.toString();
    e.lengthMm = json['length_mm']?.toString();
    e.wallThicknessMm = json['wall_thickness_mm']?.toString();
    e.material = json['material']?.toString();
    e.gost = json['gost']?.toString();
    e.weldData = json['weld_data']?.toString();
    return e;
  }
}

class PreviousInspectionRecord {
  String? kind;
  String? date;
  String? reportNumber;
  String? result;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'date': date,
        'report_number': reportNumber,
        'result': result,
      };

  static PreviousInspectionRecord fromJson(Map<String, dynamic> json) {
    final r = PreviousInspectionRecord();
    r.kind = json['kind']?.toString();
    r.date = json['date']?.toString();
    r.reportNumber = json['report_number']?.toString();
    r.result = json['result']?.toString();
    return r;
  }
}

class HeatTreatmentRecord {
  String? element;
  String? type;
  String? temperature;
  String? duration;
  String? cooling;

  HeatTreatmentRecord();

  Map<String, dynamic> toJson() => {
        'element': element,
        'type': type,
        'temperature': temperature,
        'duration': duration,
        'cooling': cooling,
      };

  factory HeatTreatmentRecord.fromJson(Map<String, dynamic> json) {
    final r = HeatTreatmentRecord();
    r.element = json['element']?.toString();
    r.type = json['type']?.toString();
    r.temperature = json['temperature']?.toString();
    r.duration = json['duration']?.toString();
    r.cooling = json['cooling']?.toString();
    return r;
  }
}

class HydraulicTestRecord {
  String? date;
  String? testType;
  String? pressure;
  String? medium;
  String? note;

  HydraulicTestRecord();

  Map<String, dynamic> toJson() => {
        'date': date,
        'test_type': testType,
        'pressure': pressure,
        'medium': medium,
        'note': note,
      };

  factory HydraulicTestRecord.fromJson(Map<String, dynamic> json) {
    final r = HydraulicTestRecord();
    r.date = json['date']?.toString();
    r.testType = json['test_type']?.toString();
    r.pressure = json['pressure']?.toString();
    r.medium = json['medium']?.toString();
    r.note = json['note']?.toString();
    return r;
  }
}

class NdtControlRecord {
  String? date;
  String? scope;
  String? result;
  String? organization;

  NdtControlRecord();

  Map<String, dynamic> toJson() => {
        'date': date,
        'scope': scope,
        'result': result,
        'organization': organization,
      };

  factory NdtControlRecord.fromJson(Map<String, dynamic> json) {
    final r = NdtControlRecord();
    r.date = json['date']?.toString();
    r.scope = json['scope']?.toString();
    r.result = json['result']?.toString();
    r.organization = json['organization']?.toString();
    return r;
  }
}

class RepairRecord {
  String? year;
  String? description;
  String? ndtResult;

  RepairRecord();

  Map<String, dynamic> toJson() => {
        'year': year,
        'description': description,
        'ndt_result': ndtResult,
      };

  factory RepairRecord.fromJson(Map<String, dynamic> json) {
    final r = RepairRecord();
    r.year = json['year']?.toString();
    r.description = json['description']?.toString();
    r.ndtResult = json['ndt_result']?.toString();
    return r;
  }
}

class FittingInstrument {
  String? name;
  String? quantity;
  String? dn;
  String? pressure;

  FittingInstrument();

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'dn': dn,
        'pressure': pressure,
      };

  factory FittingInstrument.fromJson(Map<String, dynamic> json) {
    final f = FittingInstrument();
    f.name = json['name']?.toString();
    f.quantity = json['quantity']?.toString();
    f.dn = json['dn']?.toString();
    f.pressure = json['pressure']?.toString();
    return f;
  }
}

