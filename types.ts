
export enum EquipmentType {
  VESSEL = 'VESSEL', // СРпД — сосуды
  GAS_SEPARATOR = 'GAS_SEPARATOR', // Газосепаратор (СРпД)
  UNDERGROUND_TANK = 'UNDERGROUND_TANK', // Ёмкость подземная (СРпД)
  OIL_SETTLER = 'OIL_SETTLER', // Отстойник нефти (СРпД)
  PIPELINE = 'PIPELINE', // Трубопроводы
  TANK = 'TANK', // РВС
  FURNACE = 'FURNACE', // Печи
  PUMP = 'PUMP', // Насосы
  TRANSFORMER = 'TRANSFORMER', // Трансформаторы
  VALVE = 'VALVE', // Арматура
  COLUMN = 'COLUMN' // Колонны
}

export enum RiskLevel {
  LOW = 'LOW',
  MEDIUM = 'MEDIUM',
  HIGH = 'HIGH',
  CRITICAL = 'CRITICAL'
}

export interface GeoPoint {
  lat: number;
  lng: number;
}

export interface PipelineSegment {
  id: string;
  name: string;
  type: 'ABOVE_GROUND' | 'UNDERGROUND' | 'CROSSING';
  coordinates: GeoPoint[];
  thickness: number;
  lastInspectionDate: string;
  corrosionRate: number; // мм/год
  remainingLife: number; // лет
}

export interface InspectionTask {
  id: string;
  equipmentId: string;
  equipmentName: string;
  type: EquipmentType;
  status: 'PENDING' | 'IN_PROGRESS' | 'COMPLETED' | 'OVERDUE';
  date: string;
  assignee: string;
  riskLevel: RiskLevel;
}

export interface FormField {
  id: string;
  label: string;
  type: 'text' | 'number' | 'date' | 'select' | 'boolean' | 'drawing_thickness' | 'photo';
  required: boolean;
  options?: string[];
  unit?: string;
}

export interface ModuleSchema {
  type: EquipmentType;
  title: string;
  sections: {
    title: string;
    fields: FormField[];
  }[];
}

export interface TechSpecSection {
  id: string;
  title: string;
  content: string; 
  codeBlock?: string;
  language?: string;
}

// --- HIERARCHY & PASSPORT TYPES ---

export enum NodeType {
  ROOT = 'ROOT',
  COMPANY = 'COMPANY',
  BRANCH = 'BRANCH',
  DIVISION = 'DIVISION', 
  DEPARTMENT = 'DEPARTMENT', 
  GROUP = 'GROUP', 
  EQUIPMENT = 'EQUIPMENT' 
}

// Specific attributes for different equipment types
export interface EquipmentAttributes {
  // Common
  manufacturer?: string;
  manufactureYear?: number;
  commissioningDate?: string;
  serialNumber?: string;
  regNumber?: string; // Рег. номер в РТН
  designLife?: number; // Расчетный срок службы (лет)
  
  // Vessel / Gas separator / Underground tank / Column
  volume?: number; // м3
  constructionType?: string; // горизонтальный, вертикальный
  purpose?: string; // назначение
  schemeIndex?: string; // индекс по схеме (ДЕ-1 и т.д.)
  internalDiameter?: number; // мм — внутренний диаметр ёмкости
  pressureCategory?: 'low' | 'high'; // до 0,07 МПа или выше
  testPressureType?: string; // налив, гидравлическое
  pressureDesign?: number; // МПа
  pressureWork?: number; // МПа
  tempDesign?: number; // C
  tempWork?: number; // C
  medium?: string; // Рабочая среда
  material?: string; // Марка стали

  // Pipeline
  diameter?: number; // мм
  wallThickness?: number; // мм
  length?: number; // м
  category?: string; // Категория трубопровода

  // Tank (RVS)
  height?: number; // м
  fillLevelMax?: number; // м

  // Transformer
  power?: number; // кВА
  voltageHV?: number; // кВ
  voltageLV?: number; // кВ
  oilType?: string;
}

export interface MaintenanceEvent {
  id: string;
  date: string;
  type: 'INSPECTION' | 'REPAIR' | 'INCIDENT' | 'MAINTENANCE' | 'ATTRIBUTE_CHANGE';
  title: string;
  description: string;
  performer: string; // ФИО исполнителя
  documentRef?: string; // Ссылка на акт
}

export enum DocCategory {
  PASSPORT = 'PASSPORT',       // Паспорта, формуляры
  DRAWING = 'DRAWING',         // Чертежи, схемы
  MANUAL = 'MANUAL',           // Руководства по эксплуатации
  CERTIFICATE = 'CERTIFICATE', // Сертификаты соответствия
  PROTOCOL = 'PROTOCOL',       // Протоколы испытаний/диагностики
  EPB_REPORT = 'EPB_REPORT'    // Заключения ЭПБ (Юридически значимые)
}

export interface UserInfo {
  name: string;
  role: string;
  avatar?: string; // Initials
}

export interface AttachedDocument {
  id: string;
  name: string;
  category: DocCategory;
  uploadDate: string;
  uploadedBy: UserInfo;
  size: string;
  extension: string;
}

export interface HierarchyNode {
  id: string;
  name: string;
  type: NodeType;
  equipmentType?: EquipmentType;
  children?: HierarchyNode[];
  status?: 'OK' | 'WARNING' | 'CRITICAL';
  
  // Rich Data for Equipment Level
  attributes?: EquipmentAttributes;
  nextInspectionDate?: string;
  history?: MaintenanceEvent[];
  documents?: AttachedDocument[];
}

// --- HIERARCHY API TYPES ---

export interface Enterprise {
  id: string;
  name: string;
  code?: string;
  description?: string;
  director?: string;
  phone?: string;
  email?: string;
  legal_address?: string;
  is_active?: number;
}

export interface Branch {
  id: string;
  enterprise_id: string;
  name: string;
  code?: string;
  description?: string;
  is_active?: number;
}

export interface Workshop {
  id: string;
  branch_id: string;
  name: string;
  code?: string;
  description?: string;
  is_active?: number;
}

export interface HierarchyEquipment {
  id: string;
  equipment_code?: string;
  name: string;
  type_id?: string;
  workshop_id?: string;
  opo_id?: string;
  serial_number?: string;
  location?: string;
  manufacturer?: string;
  model?: string;
  attributes?: Record<string, any>;
  is_active?: number;
}

export interface AssignmentData {
  id: string;
  equipment_id: string;
  equipment_code: string;
  equipment_name: string;
  assignment_type: string;
  assigned_by?: string;
  assigned_to: string;
  assigned_to_name?: string;
  status: string;
  priority: string;
  due_date?: string;
  description?: string;
  created_at: string;
  updated_at?: string;
  completed_at?: string;
  enterprise_id?: string;
  enterprise_name?: string;
  branch_id?: string;
  branch_name?: string;
  workshop_id?: string;
  workshop_name?: string;
  opo_id?: string;
  opo_name?: string;
  opo_code?: string;
}

// --- GIS & MONITORING TYPES ---

export interface Inspector {
  id: string;
  name: string;
  role: string;
  lat: number;
  lng: number;
  batteryLevel: number; // %
  lastSignal: string;
}

export interface CadastralParcel {
  id: string;
  number: string; // Кадастровый номер
  owner: string;
  coordinates: GeoPoint[];
}

export interface WeatherState {
  temp: number;
  windSpeed: number; // м/с
  windDeg: number; // Градусы (0-360)
  condition: string;
}
