from sqlalchemy import Column, String, Integer, Date, DateTime, Text, JSON, ForeignKey, Numeric
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.sql import func
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

class Equipment(Base):
    """Оборудование"""
    __tablename__ = "equipment"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    type_id = Column(UUID(as_uuid=True), ForeignKey("equipment_types.id"))
    name = Column(String(255), nullable=False)
    serial_number = Column(String(100))
    location = Column(String(500))  # Место расположения (НГДУ, цех, месторождение)
    commissioning_date = Column(Date)
    attributes = Column(JSONB)  # Гибкие атрибуты в формате JSON
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
    inspector_id = Column(UUID(as_uuid=True), nullable=True)
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id"), nullable=True)
    date_performed = Column(DateTime(timezone=True))
    data = Column(JSONB, nullable=False)  # Результаты обследования в формате JSON
    conclusion = Column(Text)
    next_inspection_date = Column(Date)
    status = Column(String(50), default="DRAFT")  # DRAFT, SIGNED, APPROVED
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
    signed_by = Column(UUID(as_uuid=True), nullable=True)
    signed_at = Column(DateTime(timezone=True), nullable=True)
    sent_to_client_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
