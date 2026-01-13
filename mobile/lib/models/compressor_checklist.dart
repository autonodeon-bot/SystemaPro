// Модель данных для чек-листа обследования компрессора

import 'vessel_checklist.dart'; // Для переиспользования общих полей

class CompressorChecklist extends VesselChecklist {
  // Компрессор-специфичные поля
  String? compressorType; // Тип компрессора (поршневой, винтовой, центробежный)
  String? powerRating; // Мощность
  String? pressureRatio; // Степень сжатия
  String? flowRate; // Производительность
  String? rotationSpeed; // Частота вращения
  String? numberOfStages; // Количество ступеней
  String? coolingSystem; // Система охлаждения
  String? lubricationSystem; // Система смазки
  
  // Состояние основных узлов
  String? cylinderState; // Состояние цилиндров
  String? pistonState; // Состояние поршней
  String? valvesState; // Состояние клапанов
  String? crankshaftState; // Состояние коленчатого вала
  String? bearingsState; // Состояние подшипников
  String? sealsState; // Состояние уплотнений
  
  // Вибрация и температура
  List<Map<String, dynamic>> vibrationMeasurements = []; // Измерения вибрации
  List<Map<String, dynamic>> temperatureMeasurements = []; // Измерения температуры
  
  // Масло и фильтры
  String? oilLevel; // Уровень масла
  String? oilCondition; // Состояние масла
  String? oilFilterState; // Состояние масляного фильтра
  String? airFilterState; // Состояние воздушного фильтра
  
  CompressorChecklist() : super();
  
  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    // Удаляем поля, специфичные для сосудов
    json.remove('diameter');
    json.remove('wall_thickness');
    json.remove('working_pressure');
    
    // Добавляем поля компрессора
    json['equipment_type'] = 'COMPRESSOR';
    json['compressor_type'] = compressorType;
    json['power_rating'] = powerRating;
    json['pressure_ratio'] = pressureRatio;
    json['flow_rate'] = flowRate;
    json['rotation_speed'] = rotationSpeed;
    json['number_of_stages'] = numberOfStages;
    json['cooling_system'] = coolingSystem;
    json['lubrication_system'] = lubricationSystem;
    json['cylinder_state'] = cylinderState;
    json['piston_state'] = pistonState;
    json['valves_state'] = valvesState;
    json['crankshaft_state'] = crankshaftState;
    json['bearings_state'] = bearingsState;
    json['seals_state'] = sealsState;
    json['vibration_measurements'] = vibrationMeasurements;
    json['temperature_measurements'] = temperatureMeasurements;
    json['oil_level'] = oilLevel;
    json['oil_condition'] = oilCondition;
    json['oil_filter_state'] = oilFilterState;
    json['air_filter_state'] = airFilterState;
    
    return json;
  }
  
  factory CompressorChecklist.fromJson(Map<String, dynamic> json) {
    final checklist = CompressorChecklist();
    
    // Заполняем общие поля из VesselChecklist
    checklist.inspectionDate = json['inspection_date'];
    checklist.executors = json['executors'];
    checklist.organization = json['organization'];
    checklist.documents = Map<String, bool>.from(json['documents'] ?? {});
    checklist.conclusion = json['conclusion'];
    checklist.factoryPlatePhoto = json['factory_plate_photo'];
    checklist.controlSchemeImage = json['control_scheme_image'];
    
    // Заполняем специфичные для компрессора поля
    checklist.compressorType = json['compressor_type'];
    checklist.powerRating = json['power_rating'];
    checklist.pressureRatio = json['pressure_ratio'];
    checklist.flowRate = json['flow_rate'];
    checklist.rotationSpeed = json['rotation_speed'];
    checklist.numberOfStages = json['number_of_stages'];
    checklist.coolingSystem = json['cooling_system'];
    checklist.lubricationSystem = json['lubrication_system'];
    checklist.cylinderState = json['cylinder_state'];
    checklist.pistonState = json['piston_state'];
    checklist.valvesState = json['valves_state'];
    checklist.crankshaftState = json['crankshaft_state'];
    checklist.bearingsState = json['bearings_state'];
    checklist.sealsState = json['seals_state'];
    checklist.vibrationMeasurements = List<Map<String, dynamic>>.from(json['vibration_measurements'] ?? []);
    checklist.temperatureMeasurements = List<Map<String, dynamic>>.from(json['temperature_measurements'] ?? []);
    checklist.oilLevel = json['oil_level'];
    checklist.oilCondition = json['oil_condition'];
    checklist.oilFilterState = json['oil_filter_state'];
    checklist.airFilterState = json['air_filter_state'];
    
    return checklist;
  }
}

