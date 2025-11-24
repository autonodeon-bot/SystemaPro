
export enum EquipmentType {
  VESSEL = 'VESSEL', // СРпД
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
  
  // Vessel / Column
  volume?: number; // м3
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
