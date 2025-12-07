from sqlalchemy import Column, String, Integer, Date, DateTime, Text, JSON, ForeignKey, Numeric, Boolean, Table, ARRAY
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import uuid
from database import Base

class EquipmentType(Base):
    """Типы оборудования"""
    __tablename__ = "equipment_types"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)
    description = Column(Text)
    code = Column(String(50), unique=True)
    is_active = Column(Integer, default=1)

class Branch(Base):
    """Филиалы предприятий"""
    __tablename__ = "branches"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)  # Название филиала
    code = Column(String(50))  # Код филиала
    client_id = Column(UUID(as_uuid=True), ForeignKey("clients.id"), nullable=False)  # Предприятие
    location = Column(String(500))  # Адрес/местоположение
    description = Column(Text)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Workshop(Base):
    """Цеха/подразделения предприятий"""
    __tablename__ = "workshops"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)  # Название цеха
    code = Column(String(50))  # Код цеха
    client_id = Column(UUID(as_uuid=True), ForeignKey("clients.id"), nullable=True)  # Предприятие (для обратной совместимости)
    branch_id = Column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=True)  # Филиал
    location = Column(String(500))  # Адрес/местоположение
    description = Column(Text)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class ClientEngineerAccess(Base):
    """Разрешения инженеров на доступ к предприятиям"""
    __tablename__ = "client_engineer_access"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    client_id = Column(UUID(as_uuid=True), ForeignKey("clients.id"), nullable=False)
    engineer_id = Column(UUID(as_uuid=True), ForeignKey("engineers.id"), nullable=False)
    access_type = Column(String(50), default="read_write")  # read, read_write
    granted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    granted_at = Column(DateTime(timezone=True), server_default=func.now())
    is_active = Column(Boolean, default=True)

class BranchEngineerAccess(Base):
    """Разрешения инженеров на доступ к филиалам"""
    __tablename__ = "branch_engineer_access"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    branch_id = Column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=False)
    engineer_id = Column(UUID(as_uuid=True), ForeignKey("engineers.id"), nullable=False)
    access_type = Column(String(50), default="read_write")  # read, read_write
    granted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    granted_at = Column(DateTime(timezone=True), server_default=func.now())
    is_active = Column(Boolean, default=True)

class WorkshopEngineerAccess(Base):
    """Разрешения инженеров на доступ к цехам"""
    __tablename__ = "workshop_engineer_access"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    workshop_id = Column(UUID(as_uuid=True), ForeignKey("workshops.id"), nullable=False)
    engineer_id = Column(UUID(as_uuid=True), ForeignKey("engineers.id"), nullable=False)
    access_type = Column(String(50), default="read_write")  # read, read_write, create_equipment
    granted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    granted_at = Column(DateTime(timezone=True), server_default=func.now())
    is_active = Column(Boolean, default=True)

class EquipmentTypeEngineerAccess(Base):
    """Разрешения инженеров на доступ к типам оборудования"""
    __tablename__ = "equipment_type_engineer_access"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_type_id = Column(UUID(as_uuid=True), ForeignKey("equipment_types.id"), nullable=False)
    engineer_id = Column(UUID(as_uuid=True), ForeignKey("engineers.id"), nullable=False)
    access_type = Column(String(50), default="read_write")  # read, read_write
    granted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    granted_at = Column(DateTime(timezone=True), server_default=func.now())
    is_active = Column(Boolean, default=True)

class Equipment(Base):
    """Оборудование"""
    __tablename__ = "equipment"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    type_id = Column(UUID(as_uuid=True), ForeignKey("equipment_types.id"))
    workshop_id = Column(UUID(as_uuid=True), ForeignKey("workshops.id"), nullable=True)  # Цех
    name = Column(String(255), nullable=False)
    serial_number = Column(String(100))
    location = Column(String(500))  # Место расположения (НГДУ, цех, месторождение)
    commissioning_date = Column(Date)
    attributes = Column(JSONB)  # Гибкие атрибуты в формате JSON
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)  # Кто создал
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class PipelineSegment(Base):
    """Сегменты трубопроводов"""
    __tablename__ = "pipeline_segments"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"))
    name = Column(String(255))
    segment_type = Column(String(50))  # ABOVE_GROUND, UNDERGROUND
    corrosion_rate = Column(Numeric(10, 4))
    thickness = Column(Numeric(10, 2))
    last_inspection_date = Column(Date)
    remaining_life = Column(Numeric(10, 2))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Inspection(Base):
    """Инспекции/обследования оборудования"""
    __tablename__ = "inspections"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"))
    inspector_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id"), nullable=True)
    date_performed = Column(DateTime(timezone=True))
    data = Column(JSONB, nullable=False)  # Результаты обследования в формате JSON
    conclusion = Column(Text)
    next_inspection_date = Column(Date)
    status = Column(String(50), default="DRAFT")  # DRAFT, SIGNED, APPROVED
    # Offline-first поля
    client_id = Column(UUID(as_uuid=True), nullable=True)  # Локальный UUID с мобильного устройства (для конфликтов)
    is_synced = Column(Boolean, default=False)  # Синхронизировано ли с сервером
    synced_at = Column(DateTime(timezone=True), nullable=True)  # Время синхронизации
    offline_task_id = Column(UUID(as_uuid=True), ForeignKey("offline_tasks.id"), nullable=True)  # Ссылка на задание
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Client(Base):
    """Клиенты (предприятия)"""
    __tablename__ = "clients"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)
    inn = Column(String(20))  # ИНН
    address = Column(Text)
    contact_person = Column(String(255))
    contact_phone = Column(String(50))
    contact_email = Column(String(255))
    notes = Column(Text)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Project(Base):
    """Проекты диагностики для клиентов"""
    __tablename__ = "projects"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    client_id = Column(UUID(as_uuid=True), ForeignKey("clients.id"))
    name = Column(String(255), nullable=False)
    description = Column(Text)
    status = Column(String(50), default="PLANNED")  # PLANNED, IN_PROGRESS, COMPLETED, CANCELLED
    start_date = Column(Date)
    end_date = Column(Date)
    deadline = Column(Date)
    manager_id = Column(UUID(as_uuid=True), nullable=True)
    budget = Column(Numeric(15, 2))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class EquipmentResource(Base):
    """Ресурс оборудования и продление сроков"""
    __tablename__ = "equipment_resources"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"))
    inspection_id = Column(UUID(as_uuid=True), ForeignKey("inspections.id"), nullable=True)
    initial_resource_years = Column(Numeric(10, 2))  # Начальный ресурс в годах
    remaining_resource_years = Column(Numeric(10, 2))  # Остаточный ресурс в годах
    resource_end_date = Column(Date)  # Дата окончания ресурса
    extension_date = Column(Date)  # Дата продления
    extension_years = Column(Numeric(10, 2))  # На сколько лет продлен
    calculation_method = Column(String(100))  # Методика расчета
    calculation_data = Column(JSONB)  # Данные для расчета
    document_number = Column(String(100))  # Номер документа о продлении
    document_date = Column(Date)
    status = Column(String(50), default="ACTIVE")  # ACTIVE, EXPIRED, EXTENDED
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class RegulatoryDocument(Base):
    """Нормативные документы"""
    __tablename__ = "regulatory_documents"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    document_type = Column(String(50))  # GOST, RD, FNP, etc.
    number = Column(String(100))  # Номер документа (ГОСТ 14249-89)
    name = Column(String(500), nullable=False)
    description = Column(Text)
    content = Column(Text)  # Текст документа или путь к файлу
    file_path = Column(String(500))  # Путь к файлу документа
    equipment_types = Column(JSONB)  # Типы оборудования, к которым относится
    requirements = Column(JSONB)  # Требования из документа
    effective_date = Column(Date)
    expiry_date = Column(Date)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Engineer(Base):
    """Инженеры и их компетенции"""
    __tablename__ = "engineers"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    full_name = Column(String(255), nullable=False)
    position = Column(String(255))
    email = Column(String(255))
    phone = Column(String(50))
    qualifications = Column(JSONB)  # Квалификации и компетенции
    certifications = Column(JSONB)  # Сертификаты и допуски
    equipment_types = Column(JSONB)  # Типы оборудования, с которыми работает
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Certification(Base):
    """Сертификаты и допуски инженеров"""
    __tablename__ = "certifications"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    engineer_id = Column(UUID(as_uuid=True), ForeignKey("engineers.id"))
    certification_type = Column(String(100))  # Тип сертификата
    method = Column(String(100))  # Метод контроля (УЗК, РК, ВИК, ПВК и т.д.)
    level = Column(String(50))  # Уровень (I, II, III)
    number = Column(String(100))
    issued_by = Column(String(255))
    issue_date = Column(Date)
    expiry_date = Column(Date)
    file_path = Column(String(500))
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Report(Base):
    """Сгенерированные отчеты и экспертизы"""
    __tablename__ = "reports"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    inspection_id = Column(UUID(as_uuid=True), ForeignKey("inspections.id"))
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"))
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id"), nullable=True)
    report_type = Column(String(50))  # TECHNICAL_REPORT, EXPERTISE, RESOURCE_EXTENSION
    title = Column(String(500))
    file_path = Column(String(500))
    file_size = Column(Integer)
    status = Column(String(50), default="DRAFT")  # DRAFT, SIGNED, APPROVED, SENT
    signed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    signed_at = Column(DateTime(timezone=True), nullable=True)
    sent_to_client_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class User(Base):
    """Пользователи системы"""
    __tablename__ = "users"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username = Column(String(100), unique=True, nullable=False, index=True)
    email = Column(String(255), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)  # Хеш пароля (bcrypt)
    full_name = Column(String(255))
    role = Column(String(50), nullable=False, default="engineer")  # admin, chief_operator, operator, engineer
    is_active = Column(Boolean, default=True)
    engineer_id = Column(UUID(as_uuid=True), ForeignKey("engineers.id"), nullable=True)  # Связь с инженером
    offline_pin_hash = Column(String(64), nullable=True)  # Хеш офлайн-PIN для проверки при синхронизации
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    last_login = Column(DateTime(timezone=True), nullable=True)

class Questionnaire(Base):
    """Опросные листы для диагностики оборудования"""
    __tablename__ = "questionnaires"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"), nullable=False, index=True)
    equipment_inventory_number = Column(String(100))  # Инвентарный номер
    equipment_name = Column(String(255))  # Наименование оборудования
    inspection_date = Column(Date)
    inspector_name = Column(String(255))  # ФИО инженера
    inspector_position = Column(String(255))  # Должность инженера
    questionnaire_data = Column(JSONB)  # Все данные опросного листа в JSON
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

# Таблица связи пользователей с оборудованием (доступ инженеров к оборудованию)
class UserEquipmentAccess(Base):
    """Доступ пользователей к оборудованию"""
    __tablename__ = "user_equipment_access"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"), nullable=False, index=True)
    access_type = Column(String(50), default="read_write")  # read_only, read_write
    granted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)  # Кто предоставил доступ
    granted_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=True)  # Дата окончания доступа
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

# Таблица связи пользователей с проектами
class UserProjectAccess(Base):
    """Доступ пользователей к проектам"""
    __tablename__ = "user_project_access"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id"), nullable=False, index=True)
    access_type = Column(String(50), default="read_write")  # read_only, read_write, manage
    granted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    granted_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class OfflineTask(Base):
    """Офлайн-задания для инженеров в командировках"""
    __tablename__ = "offline_tasks"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    name = Column(String(255), nullable=False)  # Название задания
    equipment_ids = Column(JSONB)  # Список UUID оборудования (только с доступом)
    downloaded_at = Column(DateTime(timezone=True), nullable=True)  # Когда скачан пакет
    expires_at = Column(DateTime(timezone=True), server_default=func.text("NOW() + INTERVAL '95 days'"))  # Срок действия (95 дней)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())


class SyncHistory(Base):
    """История синхронизаций инспекций инженерами"""
    __tablename__ = "sync_history"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)  # Инженер, который синхронизировал
    inspection_ids = Column(ARRAY(UUID(as_uuid=True)), nullable=False)  # Список синхронизированных инспекций
    synced_count = Column(Integer, nullable=False)  # Количество успешно синхронизированных
    failed_count = Column(Integer, default=0)  # Количество неудачных
    sync_type = Column(String(50), default="offline")  # Тип синхронизации: offline, manual, auto
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Связь с пользователем для удобных запросов
    user = relationship("User", backref="sync_history")
