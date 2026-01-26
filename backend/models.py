from sqlalchemy import Column, String, Integer, Date, DateTime, Text, JSON, ForeignKey, Numeric, Boolean
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

class Enterprise(Base):
    """Предприятия"""
    __tablename__ = "enterprises"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)
    code = Column(String(50), unique=True)  # Код предприятия
    description = Column(Text)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Branch(Base):
    """Филиалы"""
    __tablename__ = "branches"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    enterprise_id = Column(UUID(as_uuid=True), ForeignKey("enterprises.id"), nullable=False, index=True)
    name = Column(String(255), nullable=False)
    code = Column(String(50))  # Код филиала
    description = Column(Text)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Workshop(Base):
    """Цеха"""
    __tablename__ = "workshops"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    branch_id = Column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=False, index=True)
    name = Column(String(255), nullable=False)
    code = Column(String(50))  # Код цеха
    description = Column(Text)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class OPO(Base):
    """ОПО (Опасные производственные объекты)"""
    __tablename__ = "opos"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    enterprise_id = Column(UUID(as_uuid=True), ForeignKey("enterprises.id"), nullable=True, index=True)
    branch_id = Column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=True, index=True)
    workshop_id = Column(UUID(as_uuid=True), ForeignKey("workshops.id"), nullable=True, index=True)
    name = Column(String(255), nullable=False)
    code = Column(String(100))  # Код ОПО
    description = Column(Text)
    registration_number = Column(String(100))  # Регистрационный номер в реестре ОПО
    hazard_class = Column(String(50))  # Класс опасности
    survey_data = Column(JSONB)  # Данные опросного листа ОПО (вопросы 1-9)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Equipment(Base):
    """Оборудование"""
    __tablename__ = "equipment"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    type_id = Column(UUID(as_uuid=True), ForeignKey("equipment_types.id"))
    workshop_id = Column(UUID(as_uuid=True), ForeignKey("workshops.id"), nullable=True, index=True)  # Связь с цехом
    opo_id = Column(UUID(as_uuid=True), ForeignKey("opos.id"), nullable=True, index=True)  # Связь с ОПО
    name = Column(String(255), nullable=False)
    serial_number = Column(String(100))
    manufacturer = Column(String(255))
    model = Column(String(255))
    commissioning_date = Column(Date)
    attributes = Column(JSONB)  # Дополнительные атрибуты в формате JSON
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Client(Base):
    """Клиенты"""
    __tablename__ = "clients"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)
    inn = Column(String(20))
    address = Column(Text)
    contact_person = Column(String(255))
    phone = Column(String(50))
    email = Column(String(255))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Project(Base):
    """Проекты"""
    __tablename__ = "projects"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    client_id = Column(UUID(as_uuid=True), ForeignKey("clients.id"))
    name = Column(String(255), nullable=False)
    description = Column(Text)
    start_date = Column(Date)
    end_date = Column(Date)
    deadline = Column(Date)  # Дедлайн проекта
    budget = Column(Numeric(15, 2))  # Бюджет проекта
    status = Column(String(50), default="PLANNED")  # PLANNED, IN_PROGRESS, COMPLETED, CANCELLED
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Engineer(Base):
    """Инженеры"""
    __tablename__ = "engineers"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    full_name = Column(String(255), nullable=False)
    position = Column(String(255))
    phone = Column(String(50))
    email = Column(String(255))
    qualifications = Column(JSONB)  # Квалификации и сертификаты
    equipment_types = Column(JSONB)  # Типы оборудования, с которыми работает
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Certification(Base):
    """Сертификаты инженеров"""
    __tablename__ = "certifications"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    engineer_id = Column(UUID(as_uuid=True), ForeignKey("engineers.id"), nullable=False)
    certification_type = Column(String(100))  # Тип сертификата
    certificate_number = Column(String(100))  # Номер сертификата
    method_code = Column(String(50), nullable=True)  # Код метода НК (ВИК, УЗК, ПВК и т.д.)
    equipment_type_id = Column(UUID(as_uuid=True), ForeignKey("equipment_types.id"), nullable=True)  # Тип оборудования
    issue_date = Column(Date)
    expiry_date = Column(Date)
    issuing_organization = Column(String(255))  # Организация, выдавшая сертификат
    document_number = Column(String(100))  # Номер документа о продлении
    document_date = Column(Date)
    # Скан/файл подтверждения (фото/PDF)
    scan_file_path = Column(String(500), nullable=True)
    scan_file_name = Column(String(255), nullable=True)
    scan_file_size = Column(Integer, nullable=True)
    scan_mime_type = Column(String(100), nullable=True)
    is_active = Column(Integer, default=1)
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

class User(Base):
    """Пользователи системы"""
    __tablename__ = "users"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username = Column(String(100), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    email = Column(String(255))
    full_name = Column(String(255))
    role = Column(String(50), default="engineer")  # admin, chief_operator, engineer
    engineer_id = Column(UUID(as_uuid=True), ForeignKey("engineers.id"), nullable=True)
    permissions = Column(JSONB)  # Дополнительные права доступа
    is_active = Column(Integer, default=1)
    last_login = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Assignment(Base):
    """Задания на обследование"""
    __tablename__ = "assignments"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id"), nullable=True)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"), nullable=False)
    assigned_to = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    assigned_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    due_date = Column(Date)
    priority = Column(String(20), default="NORMAL")  # LOW, NORMAL, HIGH, URGENT
    status = Column(String(50), default="ASSIGNED")  # ASSIGNED, IN_PROGRESS, COMPLETED, CANCELLED
    description = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Inspection(Base):
    """Обследования/инспекции оборудования"""
    __tablename__ = "inspections"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"), nullable=False, index=True)
    assignment_id = Column(UUID(as_uuid=True), ForeignKey("assignments.id"), nullable=True, index=True)
    questionnaire_id = Column(UUID(as_uuid=True), ForeignKey("questionnaires.id"), nullable=True, index=True)
    date_performed = Column(DateTime(timezone=True))
    performed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    status = Column(String(50), default="DRAFT")  # DRAFT, SIGNED, SUBMITTED, COMPLETED
    conclusion = Column(Text)
    data = Column(JSONB)  # Данные обследования в формате JSON
    gps_coordinates = Column(JSONB)  # GPS координаты места обследования
    is_archived = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class ReportTemplate(Base):
    """Шаблоны отчетов"""
    __tablename__ = "report_templates"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)
    description = Column(Text)
    template_type = Column(String(50))  # TECHNICAL, EXPERTISE
    client_id = Column(UUID(as_uuid=True), ForeignKey("clients.id"), nullable=True)  # Шаблон для конкретного клиента
    template_config = Column(JSONB)  # Конфигурация шаблона (какие разделы включать, стили и т.д.)
    is_default = Column(Boolean, default=False)
    is_active = Column(Integer, default=1)
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Report(Base):
    """Отчеты"""
    __tablename__ = "reports"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    inspection_id = Column(UUID(as_uuid=True), ForeignKey("inspections.id", ondelete="SET NULL"), nullable=True)
    report_type = Column(String(50))  # TECHNICAL, EXPERTISE
    report_number = Column(String(100), nullable=True, unique=True, index=True)  # Автоматический номер отчета
    registration_number = Column(String(100), nullable=True, unique=True, index=True)  # Регистрационный номер
    file_path = Column(String(500))
    file_size = Column(Integer, default=0)
    word_file_path = Column(String(500), nullable=True)
    word_file_size = Column(Integer, default=0)
    excel_file_path = Column(String(500), nullable=True)  # Путь к Excel файлу
    xml_file_path = Column(String(500), nullable=True)  # Путь к XML файлу
    json_file_path = Column(String(500), nullable=True)  # Путь к JSON файлу
    template_id = Column(UUID(as_uuid=True), ForeignKey("report_templates.id"), nullable=True)  # Шаблон отчета
    is_signed = Column(Boolean, default=False)  # Подписан ли отчет
    signed_at = Column(DateTime(timezone=True), nullable=True)  # Дата подписания
    signed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)  # Кто подписал
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    is_archived = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Questionnaire(Base):
    """Опросные листы для диагностики оборудования"""
    __tablename__ = "questionnaires"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"), nullable=False, index=True)
    assignment_id = Column(UUID(as_uuid=True), ForeignKey("assignments.id"), nullable=True, index=True)
    date_performed = Column(DateTime(timezone=True))
    performed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    status = Column(String(50), default="DRAFT")  # DRAFT, SIGNED, SUBMITTED
    data = Column(JSONB)  # Данные опросного листа в формате JSON
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class NDTMethod(Base):
    """Методы неразрушающего контроля"""
    __tablename__ = "ndt_methods"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # Источник/контекст метода НК:
    # - questionnaire_id: методы НК, добавленные к опросному листу (историческая логика)
    # - inspection_id: методы НК, добавленные к обследованию/инспекции (новая логика)
    questionnaire_id = Column(UUID(as_uuid=True), ForeignKey("questionnaires.id"), nullable=True, index=True)
    inspection_id = Column(UUID(as_uuid=True), ForeignKey("inspections.id"), nullable=True, index=True)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"), nullable=False)
    method_code = Column(String(50))  # Код метода (УЗК, ВИК, ПВК и т.д.)
    method_name = Column(String(255))  # Название метода
    is_performed = Column(Integer, default=0)  # Выполнен ли метод
    standard = Column(String(255))  # Стандарт (ГОСТ, РД и т.д.)
    equipment = Column(String(255))  # Оборудование для НК
    inspector_name = Column(String(255))  # ФИО инженера
    inspector_level = Column(String(50))  # Уровень инженера
    results = Column(JSONB)  # Результаты контроля
    defects = Column(JSONB)  # Обнаруженные дефекты
    conclusion = Column(Text)  # Заключение
    photos = Column(JSONB)  # Массив путей к фотографиям
    additional_data = Column(JSONB)  # Дополнительные данные (например, точки толщинометрии)
    performed_date = Column(DateTime(timezone=True))  # Дата выполнения
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class UserEquipmentAccess(Base):
    """Доступ пользователей к оборудованию"""
    __tablename__ = "user_equipment_access"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"), nullable=False, index=True)
    access_type = Column(String(50))  # READ, WRITE, FULL
    granted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    granted_at = Column(DateTime(timezone=True), server_default=func.now())

class VerificationEquipment(Base):
    """Оборудование для поверки"""
    __tablename__ = "verification_equipment"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_type = Column(String(100), nullable=False)  # Тип: ВИК, УЗК, ПВК, РК, МК и т.д.
    category = Column(String(100))  # Категория для группировки
    serial_number = Column(String(100), nullable=False, index=True)  # Серийный номер
    manufacturer = Column(String(255))  # Производитель
    model = Column(String(255))  # Модель
    verification_date = Column(Date)  # Дата поверки
    expiry_date = Column(Date)  # Дата окончания действия поверки
    verification_certificate_number = Column(String(100))  # Номер свидетельства о поверке
    verification_organization = Column(String(255))  # Организация, проводившая поверку
    scan_file_path = Column(String(500), nullable=True)  # Путь к скан-копии свидетельства
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
