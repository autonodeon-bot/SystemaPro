
import { EquipmentType, InspectionTask, ModuleSchema, PipelineSegment, RiskLevel, TechSpecSection, HierarchyNode, NodeType, DocCategory, Inspector, CadastralParcel } from './types';

// --- TECHNICAL SPECIFICATIONS ---

export const ARCHITECTURE_SPECS: TechSpecSection[] = [
  {
    id: '1',
    title: '1. Общая Архитектура (C4 Model)',
    content: `Архитектура построена на принципе микроядра (Core) и подключаемых модулей (Plugins).
Взаимодействие через API Gateway (Traefik/Nginx).`,
    codeBlock: `graph TD
    User[Пользователь] --> Web[React Web Portal]
    User --> Mobile[Flutter Mobile App]
    
    subgraph "DMZ / API Gateway"
        Gateway[Traefik Proxy]
    end
    
    Web --> Gateway
    Mobile --> Gateway
    
    subgraph "Backend Core Services"
        Auth[Auth Service (FastAPI)]
        Core[Core API (Equipment Registry)]
        Files[MinIO / S3 Storage]
    end
    
    subgraph "Module Plugins (Microservices)"
        Vessel[Vessel Module]
        Pipeline[Pipeline Module]
        Tank[Tank Module]
        Gemini[AI Analysis Service]
    end
    
    Gateway --> Auth
    Gateway --> Core
    Gateway --> Vessel
    Gateway --> Pipeline
    
    subgraph "Data Layer"
        DB_Master[(PostgreSQL 16 + PostGIS)]
        DB_Time[(TimescaleDB)]
    end
    
    Core --> DB_Master
    Pipeline --> DB_Master
    Pipeline --> DB_Time`,
    language: 'mermaid'
  },
  {
    id: '2',
    title: '2. Схема Базы Данных (PostgreSQL + PostGIS)',
    content: `Ключевая особенность - JSONB для гибких полей модулей и PostGIS для геометрии трубопроводов.`,
    codeBlock: `-- Таблица типов оборудования (Реестр модулей)
CREATE TABLE equipment_types (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL, -- e.g., 'VESSEL', 'PIPELINE'
    name VARCHAR(255) NOT NULL,
    schema_definition JSONB NOT NULL, -- JSON Schema формы
    is_active BOOLEAN DEFAULT TRUE
);

-- Основной реестр оборудования
CREATE TABLE equipment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type_id INTEGER REFERENCES equipment_types(id),
    name VARCHAR(255) NOT NULL,
    serial_number VARCHAR(100),
    commissioning_date DATE,
    geo_location GEOGRAPHY(POINT, 4326), -- Для точечных объектов
    attributes JSONB, -- Специфичные поля (объем, давление и т.д.)
    company_id UUID NOT NULL
);

-- Линейная часть (расширение для трубопроводов)
CREATE TABLE pipeline_segments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    equipment_id UUID REFERENCES equipment(id),
    name VARCHAR(255),
    segment_type VARCHAR(50), -- ABOVE_GROUND, UNDERGROUND
    geometry GEOGRAPHY(LINESTRING, 4326), -- Трасса
    corrosion_rate NUMERIC(10,4)
);

-- Инспекции (Замеры)
CREATE TABLE inspections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    equipment_id UUID REFERENCES equipment(id),
    inspector_id UUID,
    date_performed TIMESTAMP WITH TIME ZONE,
    data JSONB NOT NULL, -- Результаты замеров по схеме
    conclusion TEXT,
    next_inspection_date DATE,
    status VARCHAR(50) -- DRAFT, SIGNED, APPROVED
);`,
    language: 'sql'
  },
  {
    id: '3',
    title: '3. Бэкенд (FastAPI)',
    content: `Пример эндпоинта для динамической обработки инспекций.`,
    codeBlock: `from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Json
from typing import Dict, Any

router = APIRouter(prefix="/inspections", tags=["inspections"])

class InspectionCreate(BaseModel):
    equipment_id: str
    data: Dict[str, Any] # Валидируется JSON Schema на лету

@router.post("/")
async def create_inspection(
    inspection: InspectionCreate, 
    user = Depends(get_current_user)
):
    # 1. Получаем тип оборудования
    eq = await equipment_repo.get(inspection.equipment_id)
    
    # 2. Получаем схему валидации для этого типа
    schema = await schema_repo.get(eq.type_id)
    
    # 3. Валидируем JSON (Logic)
    validate_inspection_data(inspection.data, schema)
    
    # 4. Сохраняем
    new_id = await inspection_repo.save(inspection)
    return {"id": new_id, "status": "created"}`,
    language: 'python'
  },
  {
    id: '4',
    title: '4. Мобильное приложение (Flutter)',
    content: `Архитектура динамических форм во Flutter.`,
    codeBlock: `// dynamic_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';

class DynamicInspectionScreen extends StatelessWidget {
  final ModuleSchema schema; // Загружается из API
  final String equipmentId;

  const DynamicInspectionScreen({required this.schema, required this.equipmentId});

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormBuilderState>();

    return Scaffold(
      appBar: AppBar(title: Text(schema.title)),
      body: SingleChildScrollView(
        child: FormBuilder(
          key: formKey,
          child: Column(
            children: schema.sections.map((section) {
              return ExpansionTile(
                title: Text(section.title),
                children: section.fields.map((field) {
                  return _buildField(field);
                }).toList(),
              );
            }).toList(),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (formKey.currentState?.saveAndValidate() ?? false) {
            // Отправка JSON + ЭЦП
            submitInspection(formKey.currentState!.value);
          }
        },
        child: Icon(Icons.save),
      ),
    );
  }

  Widget _buildField(FormFieldSchema field) {
    switch (field.type) {
      case 'text':
        return FormBuilderTextField(name: field.id, decoration: InputDecoration(labelText: field.label));
      case 'number':
        return FormBuilderTextField(name: field.id, keyboardType: TextInputType.number);
      case 'photo':
         return PhotoPickerField(name: field.id); // Кастомный виджет
      default:
        return SizedBox.shrink();
    }
  }
}`,
    language: 'dart'
  }
];

// --- MOCK DATA FOR UI ---

// REAL WORLD COORDINATES (Surgut Region - Oil & Gas Fields)
export const PIPELINES_DATA: PipelineSegment[] = [
  {
    id: 'P-101-Main',
    name: 'Магистральный нефтепровод "Сургут-Полоцк" (Участок 154)',
    type: 'UNDERGROUND',
    coordinates: [
      { lat: 61.2540, lng: 73.3960 },
      { lat: 61.2590, lng: 73.4050 },
      { lat: 61.2650, lng: 73.4200 },
      { lat: 61.2680, lng: 73.4350 },
      { lat: 61.2700, lng: 73.4500 }
    ],
    thickness: 12.5,
    lastInspectionDate: '2024-10-15',
    corrosionRate: 0.12,
    remainingLife: 15.4
  },
  {
    id: 'P-102-River',
    name: 'Дюкерный переход через протоку',
    type: 'CROSSING',
    coordinates: [
      { lat: 61.2700, lng: 73.4500 },
      { lat: 61.2720, lng: 73.4550 },
      { lat: 61.2730, lng: 73.4600 },
      { lat: 61.2735, lng: 73.4650 }
    ],
    thickness: 16.0,
    lastInspectionDate: '2024-11-01',
    corrosionRate: 0.05,
    remainingLife: 22.1
  },
  {
    id: 'P-103-Tech',
    name: 'Технологическая обвязка ДНС-2',
    type: 'ABOVE_GROUND',
    coordinates: [
      { lat: 61.2500, lng: 73.4100 },
      { lat: 61.2510, lng: 73.4100 },
      { lat: 61.2510, lng: 73.4120 },
      { lat: 61.2500, lng: 73.4120 },
      { lat: 61.2500, lng: 73.4100 }
    ],
    thickness: 8.2,
    lastInspectionDate: '2023-05-20',
    corrosionRate: 0.35,
    remainingLife: 3.2
  }
];

export const MOCK_INSPECTORS: Inspector[] = [
  { id: 'u1', name: 'Иванов И.И.', role: 'Обходчик', lat: 61.2550, lng: 73.4000, batteryLevel: 85, lastSignal: '1 мин' },
  { id: 'u2', name: 'Петров П.П.', role: 'Дефектоскопист', lat: 61.2680, lng: 73.4300, batteryLevel: 42, lastSignal: 'Online' },
];

export const MOCK_CADASTRAL: CadastralParcel[] = [
  {
    id: 'cad-1',
    number: '86:10:0001001:23',
    owner: 'Лесной фонд (Участок 45)',
    coordinates: [
      { lat: 61.2600, lng: 73.4100 },
      { lat: 61.2620, lng: 73.4100 },
      { lat: 61.2620, lng: 73.4150 },
      { lat: 61.2600, lng: 73.4150 },
    ]
  }
];

export const API_BASE = 'http://5.129.203.182:8000';

export const INSPECTION_TASKS: InspectionTask[] = [
  { id: 'T-001', equipmentId: 'V-501', equipmentName: 'Сепаратор С-1', type: EquipmentType.VESSEL, status: 'OVERDUE', date: '2024-12-01', assignee: 'Иванов И.И.', riskLevel: RiskLevel.CRITICAL },
  { id: 'T-002', equipmentId: 'P-101', equipmentName: 'Трубопровод Т-1', type: EquipmentType.PIPELINE, status: 'IN_PROGRESS', date: '2025-01-15', assignee: 'Петров П.П.', riskLevel: RiskLevel.HIGH },
  { id: 'T-003', equipmentId: 'R-200', equipmentName: 'Резервуар РВС-5000', type: EquipmentType.TANK, status: 'PENDING', date: '2025-02-01', assignee: 'Сидоров С.С.', riskLevel: RiskLevel.MEDIUM },
  { id: 'T-004', equipmentId: 'F-101', equipmentName: 'Печь П-1', type: EquipmentType.FURNACE, status: 'COMPLETED', date: '2024-11-20', assignee: 'Иванов И.И.', riskLevel: RiskLevel.LOW },
];

export const VESSEL_SCHEMA: ModuleSchema = {
  type: EquipmentType.VESSEL,
  title: 'Техническое диагностирование сосуда',
  sections: [
    {
      title: '1. Условия эксплуатации',
      fields: [
        { id: 'pressure_current', label: 'Текущее рабочее давление (МПа)', type: 'number', required: true, unit: 'МПа' },
        { id: 'temp_wall', label: 'Температура стенки (°C)', type: 'number', required: true, unit: '°C' },
      ]
    },
    {
      title: '2. Визуально-измерительный контроль',
      fields: [
        { id: 'vik_conclusion', label: 'Заключение ВИК', type: 'select', required: true, options: ['Годен', 'Годен с ограничениями', 'Не годен'] },
        { id: 'defects_found', label: 'Выявленные дефекты', type: 'text', required: false },
        { id: 'photo_defects', label: 'Фотофиксация дефектов', type: 'photo', required: true },
      ]
    },
    {
      title: '3. Ультразвуковая толщинометрия (Карта замеров)',
      fields: [
        { 
          id: 'thickness_map', 
          label: 'Схема замера толщины стенки', 
          type: 'drawing_thickness', // NEW COMPLEX TYPE
          required: true 
        },
      ]
    }
  ]
};

// --- MOCK HIERARCHY TREE WITH DIGITAL PASSPORT DATA ---

const MOCK_USERS = {
  ENGINEER: { name: 'Иванов П.С.', role: 'Ведущий инженер', avatar: 'ИП' },
  EXPERT: { name: 'Смирнов А.А.', role: 'Эксперт ЭПБ', avatar: 'СА' },
  ARCHIVIST: { name: 'Сидорова Е.М.', role: 'Техник ПТО', avatar: 'СЕ' }
};

export const HIERARCHY_TREE: HierarchyNode = {
  id: 'root',
  name: 'Диагностика и ЭПБ (Холдинг)',
  type: NodeType.ROOT,
  children: [
    {
      id: 'cmp-1',
      name: 'ООО "Газпром переработка"',
      type: NodeType.COMPANY,
      children: [
        {
          id: 'br-1',
          name: 'Сургутский ЗСК (Филиал)',
          type: NodeType.BRANCH,
          children: [
            {
              id: 'dep-1',
              name: 'Цех №1 (Подготовка сырья)',
              type: NodeType.DEPARTMENT,
              children: [
                {
                   id: 'grp-vessels',
                   name: 'Сосуды, работающие под давлением',
                   type: NodeType.GROUP,
                   equipmentType: EquipmentType.VESSEL,
                   children: [
                      { 
                        id: 'eq-v-101', 
                        name: 'Сепаратор С-101 (Входной)', 
                        type: NodeType.EQUIPMENT, 
                        equipmentType: EquipmentType.VESSEL, 
                        status: 'OK',
                        nextInspectionDate: '2025-06-12',
                        attributes: {
                          manufacturer: 'ОАО "Волгограднефтемаш"',
                          manufactureYear: 2012,
                          serialNumber: '582-12-Б',
                          regNumber: '14-582-2012',
                          designLife: 20,
                          volume: 50,
                          pressureDesign: 6.3,
                          pressureWork: 5.8,
                          tempDesign: 80,
                          tempWork: 45,
                          medium: 'Нестабильный газовый конденсат',
                          material: '09Г2С (ГОСТ 5520-79)',
                        },
                        history: [
                          { id: 'h1', date: '2024-06-12', type: 'MAINTENANCE', title: 'ТО запорной арматуры', description: 'Замена прокладок на фланцевых соединениях люка-лаза.', performer: 'РМУ-3 (Бригадир Петров)' },
                          { id: 'h2', date: '2023-06-10', type: 'INSPECTION', title: 'Внутренний осмотр', description: 'Коррозии внутренней поверхности не выявлено.', performer: 'Служба ТД (Инженер Сидоров)', documentRef: 'Акт №45/23' },
                          { id: 'h3', date: '2012-08-01', type: 'MAINTENANCE', title: 'Ввод в эксплуатацию', description: 'Первичный пуск и наладка.', performer: 'СМУ-1' }
                        ],
                        documents: [
                          { id: 'd1', name: 'Паспорт сосуда С-101.pdf', category: DocCategory.PASSPORT, uploadDate: '2012-08-01', uploadedBy: MOCK_USERS.ARCHIVIST, size: '12.5 MB', extension: 'pdf' },
                          { id: 'd2', name: 'Схема обвязки.dwg', category: DocCategory.DRAWING, uploadDate: '2012-08-01', uploadedBy: MOCK_USERS.ARCHIVIST, size: '2.1 MB', extension: 'dwg' },
                          { id: 'd3', name: 'Заключение ЭПБ №154-2023.pdf', category: DocCategory.EPB_REPORT, uploadDate: '2023-06-15', uploadedBy: MOCK_USERS.EXPERT, size: '4.8 MB', extension: 'pdf' },
                          { id: 'd4', name: 'Сертификат ТР ТС 032.pdf', category: DocCategory.CERTIFICATE, uploadDate: '2012-07-20', uploadedBy: MOCK_USERS.ARCHIVIST, size: '1.2 MB', extension: 'pdf' }
                        ]
                      },
                      { 
                        id: 'eq-v-102', 
                        name: 'Сепаратор С-102 (Факельный)', 
                        type: NodeType.EQUIPMENT, 
                        equipmentType: EquipmentType.VESSEL, 
                        status: 'CRITICAL',
                        nextInspectionDate: '2025-02-01',
                        attributes: {
                          manufacturer: 'Пензхиммаш',
                          manufactureYear: 1998,
                          serialNumber: '9921',
                          regNumber: '14-102-1998',
                          designLife: 25,
                          volume: 25,
                          pressureDesign: 1.6,
                          pressureWork: 0.5,
                          tempWork: 30,
                          medium: 'Факельный газ',
                          material: '16ГС',
                        },
                         history: [
                          { id: 'h1', date: '2024-11-20', type: 'INCIDENT', title: 'Пропуск среды', description: 'Обнаружен свищ в штуцере дренажа.', performer: 'Оператор Петров' },
                        ],
                        documents: [
                           { id: 'd1', name: 'Паспорт.pdf', category: DocCategory.PASSPORT, uploadDate: '1998-05-20', uploadedBy: MOCK_USERS.ARCHIVIST, size: '5 MB', extension: 'pdf' }
                        ]
                      }
                   ]
                },
              ]
            }
          ]
        },
        {
           id: 'br-2',
           name: 'Астраханский ГПЗ',
           type: NodeType.BRANCH,
           children: [] 
        }
      ]
    },
    {
       id: 'cmp-2',
       name: 'АО "Транснефть - Сибирь"',
       type: NodeType.COMPANY,
       children: [
          {
             id: 'br-tn-1',
             name: 'Нефтеюганское УМН',
             type: NodeType.BRANCH,
             children: [
                {
                   id: 'dep-tn-1',
                   name: 'ЛПДС "Каркатеевы"',
                   type: NodeType.DEPARTMENT,
                   children: [
                      {
                         id: 'grp-pipes',
                         name: 'Магистральные трубопроводы',
                         type: NodeType.GROUP,
                         equipmentType: EquipmentType.PIPELINE,
                         children: [
                            { 
                              id: 'eq-p-1', 
                              name: 'МН "Усть-Балык - Курган" (124-150 км)', 
                              type: NodeType.EQUIPMENT, 
                              equipmentType: EquipmentType.PIPELINE, 
                              status: 'WARNING',
                              nextInspectionDate: '2025-05-01',
                              attributes: {
                                manufacturer: 'Выксунский МЗ',
                                manufactureYear: 1985,
                                commissioningDate: '1986-10-15',
                                length: 26000,
                                diameter: 1220,
                                wallThickness: 14,
                                category: 'II',
                                material: '17Г1С',
                                pressureDesign: 6.4,
                                pressureWork: 5.5
                              },
                              history: [],
                              documents: []
                            }
                         ]
                      },
                      {
                         id: 'grp-pumps',
                         name: 'Насосное оборудование',
                         type: NodeType.GROUP,
                         equipmentType: EquipmentType.PUMP,
                         children: [
                             { 
                               id: 'eq-pump-1', 
                               name: 'НМ-10000-210 №1', 
                               type: NodeType.EQUIPMENT, 
                               equipmentType: EquipmentType.PUMP, 
                               status: 'OK',
                               attributes: {
                                 manufacturer: 'Насосэнергомаш',
                                 manufactureYear: 2015,
                                 power: 8000,
                                 pressureWork: 21, // Напор
                                 medium: 'Сырая нефть'
                               }
                             }
                         ]
                      }
                   ]
                }
             ]
          }
       ]
    }
  ]
};
