// Модель опросного листа для диагностики сосудов
// На основе СО 153-34.17.439-2003


class Questionnaire {
  String? equipmentId;
  String? equipmentInventoryNumber; // Инвентарный номер
  String? equipmentName; // Наименование оборудования
  String? inspectionDate;
  String? inspectorName; // ФИО инженера
  String? inspectorPosition; // Должность инженера
  
  // Раздел 1: Общие сведения об объекте
  Section1GeneralInfo section1 = Section1GeneralInfo();
  
  // Раздел 2: Технические характеристики
  Section2TechnicalSpecs section2 = Section2TechnicalSpecs();
  
  // Раздел 3: Состояние основного металла
  Section3MetalCondition section3 = Section3MetalCondition();
  
  // Раздел 4: Сварные соединения
  Section4Welds section4 = Section4Welds();
  
  // Раздел 5: Арматура и КИП
  Section5Armature section5 = Section5Armature();
  
  // Раздел 6: Опоры и крепления
  Section6Supports section6 = Section6Supports();
  
  // Раздел 7: Внутренние устройства
  Section7InternalDevices section7 = Section7InternalDevices();
  
  // Раздел 8: Результаты неразрушающего контроля
  Section8NDT section8 = Section8NDT();
  
  // Раздел 9: Заключение о техническом состоянии
  Section9Conclusion section9 = Section9Conclusion();
  
  // Раздел 10: Рекомендации по продлению срока эксплуатации
  Section10Recommendations section10 = Section10Recommendations();
  
  Questionnaire();
  
  Map<String, dynamic> toJson() {
    return {
      'equipment_id': equipmentId,
      'equipment_inventory_number': equipmentInventoryNumber,
      'equipment_name': equipmentName,
      'inspection_date': inspectionDate,
      'inspector_name': inspectorName,
      'inspector_position': inspectorPosition,
      'section1': section1.toJson(),
      'section2': section2.toJson(),
      'section3': section3.toJson(),
      'section4': section4.toJson(),
      'section5': section5.toJson(),
      'section6': section6.toJson(),
      'section7': section7.toJson(),
      'section8': section8.toJson(),
      'section9': section9.toJson(),
      'section10': section10.toJson(),
    };
  }
}

// Базовый класс для пункта опросного листа с фото
class QuestionnaireItem {
  String id; // Уникальный ID пункта
  String title; // Название пункта
  String? value; // Значение (текст, число и т.д.)
  String? comment; // Комментарий
  List<String> photos; // Пути к фотофайлам
  bool? booleanValue; // Для чекбоксов
  
  QuestionnaireItem({
    required this.id,
    required this.title,
    this.value,
    this.comment,
    this.booleanValue,
    List<String>? photos,
  }) : photos = photos ?? [];
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'value': value,
    'comment': comment,
    'photos': photos,
    'boolean_value': booleanValue,
  };
}

// Раздел 1: Общие сведения об объекте
class Section1GeneralInfo {
  QuestionnaireItem? location; // Место установки
  QuestionnaireItem? installationDate; // Дата установки
  QuestionnaireItem? lastInspectionDate; // Дата последнего обследования
  QuestionnaireItem? operatingMode; // Режим работы
  QuestionnaireItem? workingEnvironment; // Рабочая среда
  QuestionnaireItem? operatingPressure; // Рабочее давление
  QuestionnaireItem? operatingTemperature; // Рабочая температура
  List<QuestionnaireItem> generalPhotos = []; // Общие фото объекта
  
  Map<String, dynamic> toJson() => {
    'location': location?.toJson(),
    'installation_date': installationDate?.toJson(),
    'last_inspection_date': lastInspectionDate?.toJson(),
    'operating_mode': operatingMode?.toJson(),
    'working_environment': workingEnvironment?.toJson(),
    'operating_pressure': operatingPressure?.toJson(),
    'operating_temperature': operatingTemperature?.toJson(),
    'general_photos': generalPhotos.map((p) => p.toJson()).toList(),
  };
}

// Раздел 2: Технические характеристики
class Section2TechnicalSpecs {
  QuestionnaireItem? designPressure; // Расчетное давление
  QuestionnaireItem? designTemperature; // Расчетная температура
  QuestionnaireItem? volume; // Объем
  QuestionnaireItem? diameter; // Диаметр
  QuestionnaireItem? wallThickness; // Толщина стенки
  QuestionnaireItem? material; // Материал изготовления
  QuestionnaireItem? manufacturer; // Изготовитель
  QuestionnaireItem? manufactureYear; // Год изготовления
  QuestionnaireItem? serialNumber; // Заводской номер
  QuestionnaireItem? regNumber; // Регистрационный номер
  QuestionnaireItem? factoryPlatePhoto; // Фото заводской таблички
  
  Map<String, dynamic> toJson() => {
    'design_pressure': designPressure?.toJson(),
    'design_temperature': designTemperature?.toJson(),
    'volume': volume?.toJson(),
    'diameter': diameter?.toJson(),
    'wall_thickness': wallThickness?.toJson(),
    'material': material?.toJson(),
    'manufacturer': manufacturer?.toJson(),
    'manufacture_year': manufactureYear?.toJson(),
    'serial_number': serialNumber?.toJson(),
    'reg_number': regNumber?.toJson(),
    'factory_plate_photo': factoryPlatePhoto?.toJson(),
  };
}

// Раздел 3: Состояние основного металла
class Section3MetalCondition {
  QuestionnaireItem? externalCondition; // Состояние наружной поверхности
  QuestionnaireItem? internalCondition; // Состояние внутренней поверхности
  QuestionnaireItem? corrosionState; // Состояние коррозии
  QuestionnaireItem? hasDeformations; // Наличие деформаций
  QuestionnaireItem? deformationDescription; // Описание деформаций
  QuestionnaireItem? hasCracks; // Наличие трещин
  QuestionnaireItem? cracksDescription; // Описание трещин
  QuestionnaireItem? hasWear; // Наличие износа
  QuestionnaireItem? wearDescription; // Описание износа
  List<QuestionnaireItem> metalPhotos = []; // Фото состояния металла
  
  Map<String, dynamic> toJson() => {
    'external_condition': externalCondition?.toJson(),
    'internal_condition': internalCondition?.toJson(),
    'corrosion_state': corrosionState?.toJson(),
    'has_deformations': hasDeformations?.toJson(),
    'deformation_description': deformationDescription?.toJson(),
    'has_cracks': hasCracks?.toJson(),
    'cracks_description': cracksDescription?.toJson(),
    'has_wear': hasWear?.toJson(),
    'wear_description': wearDescription?.toJson(),
    'metal_photos': metalPhotos.map((p) => p.toJson()).toList(),
  };
}

// Раздел 4: Сварные соединения
class Section4Welds {
  QuestionnaireItem? totalWeldCount; // Общее количество сварных соединений
  QuestionnaireItem? inspectedWeldCount; // Количество обследованных соединений
  QuestionnaireItem? weldCondition; // Состояние сварных соединений
  QuestionnaireItem? hasWeldDefects; // Наличие дефектов
  QuestionnaireItem? weldDefectsDescription; // Описание дефектов
  List<QuestionnaireItem> weldPhotos = []; // Фото сварных соединений
  
  Map<String, dynamic> toJson() => {
    'total_weld_count': totalWeldCount?.toJson(),
    'inspected_weld_count': inspectedWeldCount?.toJson(),
    'weld_condition': weldCondition?.toJson(),
    'has_weld_defects': hasWeldDefects?.toJson(),
    'weld_defects_description': weldDefectsDescription?.toJson(),
    'weld_photos': weldPhotos.map((p) => p.toJson()).toList(),
  };
}

// Раздел 5: Арматура и КИП
class Section5Armature {
  QuestionnaireItem? armatureCondition; // Состояние арматуры
  QuestionnaireItem? armatureType; // Тип арматуры
  QuestionnaireItem? armatureCount; // Количество арматуры
  QuestionnaireItem? hasSafetyValves; // Наличие предохранительных клапанов
  QuestionnaireItem? safetyValvesCondition; // Состояние ПК
  QuestionnaireItem? hasGauges; // Наличие манометров
  QuestionnaireItem? gaugesCondition; // Состояние манометров
  QuestionnaireItem? hasLevelSensors; // Наличие датчиков уровня
  QuestionnaireItem? levelSensorsCondition; // Состояние датчиков уровня
  List<QuestionnaireItem> armaturePhotos = []; // Фото арматуры и КИП
  
  Map<String, dynamic> toJson() => {
    'armature_condition': armatureCondition?.toJson(),
    'armature_type': armatureType?.toJson(),
    'armature_count': armatureCount?.toJson(),
    'has_safety_valves': hasSafetyValves?.toJson(),
    'safety_valves_condition': safetyValvesCondition?.toJson(),
    'has_gauges': hasGauges?.toJson(),
    'gauges_condition': gaugesCondition?.toJson(),
    'has_level_sensors': hasLevelSensors?.toJson(),
    'level_sensors_condition': levelSensorsCondition?.toJson(),
    'armature_photos': armaturePhotos.map((p) => p.toJson()).toList(),
  };
}

// Раздел 6: Опоры и крепления
class Section6Supports {
  QuestionnaireItem? supportsType; // Тип опор
  QuestionnaireItem? supportsCondition; // Состояние опор
  QuestionnaireItem? hasSupportDefects; // Наличие дефектов опор
  QuestionnaireItem? supportDefectsDescription; // Описание дефектов
  QuestionnaireItem? fastenersCondition; // Состояние крепежных элементов
  List<QuestionnaireItem> supportPhotos = []; // Фото опор и креплений
  
  Map<String, dynamic> toJson() => {
    'supports_type': supportsType?.toJson(),
    'supports_condition': supportsCondition?.toJson(),
    'has_support_defects': hasSupportDefects?.toJson(),
    'support_defects_description': supportDefectsDescription?.toJson(),
    'fasteners_condition': fastenersCondition?.toJson(),
    'support_photos': supportPhotos.map((p) => p.toJson()).toList(),
  };
}

// Раздел 7: Внутренние устройства
class Section7InternalDevices {
  QuestionnaireItem? hasInternalDevices; // Наличие внутренних устройств
  QuestionnaireItem? internalDevicesType; // Тип внутренних устройств
  QuestionnaireItem? internalDevicesCondition; // Состояние внутренних устройств
  QuestionnaireItem? internalDevicesDescription; // Описание внутренних устройств
  List<QuestionnaireItem> internalPhotos = []; // Фото внутренних устройств
  
  Map<String, dynamic> toJson() => {
    'has_internal_devices': hasInternalDevices?.toJson(),
    'internal_devices_type': internalDevicesType?.toJson(),
    'internal_devices_condition': internalDevicesCondition?.toJson(),
    'internal_devices_description': internalDevicesDescription?.toJson(),
    'internal_photos': internalPhotos.map((p) => p.toJson()).toList(),
  };
}

// Раздел 8: Результаты неразрушающего контроля
class Section8NDT {
  QuestionnaireItem? hasVisualInspection; // Проведен ВИК
  QuestionnaireItem? visualInspectionResults; // Результаты ВИК
  QuestionnaireItem? hasUltrasonicTesting; // Проведен УЗК
  QuestionnaireItem? ultrasonicTestingResults; // Результаты УЗК
  QuestionnaireItem? hasThicknessMeasurement; // Проведена УЗТ
  QuestionnaireItem? thicknessMeasurementResults; // Результаты УЗТ
  QuestionnaireItem? minThickness; // Минимальная толщина
  QuestionnaireItem? maxThickness; // Максимальная толщина
  QuestionnaireItem? hasHardnessTest; // Проведен контроль твердости
  QuestionnaireItem? hardnessTestResults; // Результаты контроля твердости
  List<QuestionnaireItem> ndtPhotos = []; // Фото НК
  
  Map<String, dynamic> toJson() => {
    'has_visual_inspection': hasVisualInspection?.toJson(),
    'visual_inspection_results': visualInspectionResults?.toJson(),
    'has_ultrasonic_testing': hasUltrasonicTesting?.toJson(),
    'ultrasonic_testing_results': ultrasonicTestingResults?.toJson(),
    'has_thickness_measurement': hasThicknessMeasurement?.toJson(),
    'thickness_measurement_results': thicknessMeasurementResults?.toJson(),
    'min_thickness': minThickness?.toJson(),
    'max_thickness': maxThickness?.toJson(),
    'has_hardness_test': hasHardnessTest?.toJson(),
    'hardness_test_results': hardnessTestResults?.toJson(),
    'ndt_photos': ndtPhotos.map((p) => p.toJson()).toList(),
  };
}

// Раздел 9: Заключение о техническом состоянии
class Section9Conclusion {
  QuestionnaireItem? technicalState; // Техническое состояние
  QuestionnaireItem? canOperate; // Может ли эксплуатироваться
  QuestionnaireItem? operatingConditions; // Условия эксплуатации
  QuestionnaireItem? hasRestrictions; // Наличие ограничений
  QuestionnaireItem? restrictionsDescription; // Описание ограничений
  QuestionnaireItem? remainingResource; // Остаточный ресурс
  QuestionnaireItem? nextInspectionDate; // Дата следующего обследования
  List<QuestionnaireItem> conclusionPhotos = []; // Фото для заключения
  
  Map<String, dynamic> toJson() => {
    'technical_state': technicalState?.toJson(),
    'can_operate': canOperate?.toJson(),
    'operating_conditions': operatingConditions?.toJson(),
    'has_restrictions': hasRestrictions?.toJson(),
    'restrictions_description': restrictionsDescription?.toJson(),
    'remaining_resource': remainingResource?.toJson(),
    'next_inspection_date': nextInspectionDate?.toJson(),
    'conclusion_photos': conclusionPhotos.map((p) => p.toJson()).toList(),
  };
}

// Раздел 10: Рекомендации по продлению срока эксплуатации
class Section10Recommendations {
  QuestionnaireItem? canExtendServiceLife; // Можно ли продлить срок эксплуатации
  QuestionnaireItem? recommendedExtensionPeriod; // Рекомендуемый период продления
  QuestionnaireItem? requiredRepairs; // Требуемые ремонты
  QuestionnaireItem? repairsDescription; // Описание ремонтов
  QuestionnaireItem? requiredMaintenance; // Требуемое обслуживание
  QuestionnaireItem? maintenanceDescription; // Описание обслуживания
  QuestionnaireItem? additionalRequirements; // Дополнительные требования
  List<QuestionnaireItem> recommendationPhotos = []; // Фото для рекомендаций
  
  Map<String, dynamic> toJson() => {
    'can_extend_service_life': canExtendServiceLife?.toJson(),
    'recommended_extension_period': recommendedExtensionPeriod?.toJson(),
    'required_repairs': requiredRepairs?.toJson(),
    'repairs_description': repairsDescription?.toJson(),
    'required_maintenance': requiredMaintenance?.toJson(),
    'maintenance_description': maintenanceDescription?.toJson(),
    'additional_requirements': additionalRequirements?.toJson(),
    'recommendation_photos': recommendationPhotos.map((p) => p.toJson()).toList(),
  };
}

