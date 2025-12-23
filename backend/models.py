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

class Equipment(Base):
    """Оборудование - единая база с уникальными кодами (версия 3.3.0)"""
    __tablename__ = "equipment"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_code = Column(String(100), unique=True, nullable=False, index=True)  # Уникальный код оборудования
    type_id = Column(UUID(as_uuid=True), ForeignKey("equipment_types.id"))
    workshop_id = Column(UUID(as_uuid=True), ForeignKey("workshops.id"), nullable=True, index=True)  # Связь с цехом
    name = Column(String(255), nullable=False)
    serial_number = Column(String(100))
    location = Column(String(500))  # Место расположения (НГДУ, цех, месторождение) - для обратной совместимости
    commissioning_date = Column(Date)
    attributes = Column(JSONB)  # Гибкие атрибуты в формате JSON
    is_active = Column(Integer, default=1)  # Активно ли оборудование
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
    is_archived = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Client(Base):
    """Клиенты"""
    __tablename__ = "clients"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)
    inn = Column(String(20))
    kpp = Column(String(20))
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
    status = Column(String(50), default="ACTIVE")  # ACTIVE, COMPLETED, CANCELLED
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
    email = Column(String(255), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    full_name = Column(String(255))
    role = Column(String(50), nullable=False)  # admin, chief_operator, operator, engineer, client
    engineer_id = Column(UUID(as_uuid=True), ForeignKey("engineers.id"), nullable=True)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class EquipmentResource(Base):
    """Ресурс оборудования"""
    __tablename__ = "equipment_resources"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"), nullable=False)
    resource_type = Column(String(50))  # PRESSURE_CYCLES, TEMPERATURE_CYCLES, OPERATING_HOURS
    current_value = Column(Numeric(15, 2))
    limit_value = Column(Numeric(15, 2))
    unit = Column(String(50))
    last_updated = Column(DateTime(timezone=True), server_default=func.now())
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Report(Base):
    """Отчеты"""
    __tablename__ = "reports"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    inspection_id = Column(UUID(as_uuid=True), ForeignKey("inspections.id"), nullable=False)
    report_type = Column(String(50))  # TECHNICAL, EXPERTISE
    file_path = Column(String(500))
    file_size = Column(Integer, default=0)
    word_file_path = Column(String(500), nullable=True)
    word_file_size = Column(Integer, default=0)
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    is_archived = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

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
    file_path = Column(String(500), nullable=True)  # Путь к сгенерированному PDF
    file_size = Column(Integer, default=0)  # Размер файла в байтах
    word_file_path = Column(String(500), nullable=True)  # Путь к сгенерированному Word документу
    word_file_size = Column(Integer, default=0)  # Размер Word файла в байтах
    created_by = Column(UUID(as_uuid=True), nullable=True)  # ID пользователя, создавшего опросный лист
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class QuestionnaireDocumentFile(Base):
    """Файлы документов чек-листа"""
    __tablename__ = "questionnaire_document_files"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    questionnaire_id = Column(UUID(as_uuid=True), ForeignKey("questionnaires.id"), nullable=False, index=True)
    document_number = Column(String(10), nullable=False)  # Номер документа из чек-листа (1-17)
    file_name = Column(String(255), nullable=False)  # Оригинальное имя файла
    file_path = Column(String(500), nullable=False)  # Путь к файлу на сервере
    file_size = Column(Integer, nullable=False)  # Размер файла в байтах
    file_type = Column(String(50))  # image/jpeg, image/png, application/pdf
    mime_type = Column(String(100))  # MIME тип файла
    uploaded_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
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
    
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"), primary_key=True)
    access_type = Column(String(50), default="READ")  # READ, WRITE, FULL
    granted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    granted_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=True)
    is_active = Column(Integer, default=1)  # 1 - активен, 0 - неактивен

class HierarchyEngineerAssignment(Base):
    """Назначение инженеров на уровни иерархии оборудования"""
    __tablename__ = "hierarchy_engineer_assignments"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    enterprise_id = Column(UUID(as_uuid=True), ForeignKey("enterprises.id"), nullable=True, index=True)
    branch_id = Column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=True, index=True)
    workshop_id = Column(UUID(as_uuid=True), ForeignKey("workshops.id"), nullable=True, index=True)
    equipment_type_id = Column(UUID(as_uuid=True), ForeignKey("equipment_types.id"), nullable=True, index=True)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"), nullable=True, index=True)
    granted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    granted_at = Column(DateTime(timezone=True), server_default=func.now())
    is_active = Column(Integer, default=1)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

class Assignment(Base):
    """Задания на диагностику/экспертизу оборудования (версия 3.3.0)"""
    __tablename__ = "assignments"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id", ondelete="CASCADE"), nullable=False, index=True)
    assignment_type = Column(String(50), nullable=False)  # 'DIAGNOSTICS', 'EXPERTISE', 'INSPECTION'
    assigned_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    assigned_to = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    status = Column(String(50), default='PENDING')  # 'PENDING', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'
    priority = Column(String(20), default='NORMAL')  # 'LOW', 'NORMAL', 'HIGH', 'URGENT'
    due_date = Column(DateTime(timezone=True), nullable=True)
    description = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    completed_at = Column(DateTime(timezone=True), nullable=True)

class InspectionHistory(Base):
    """История обследований оборудования (версия 3.3.0)"""
    __tablename__ = "inspection_history"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id", ondelete="CASCADE"), nullable=False, index=True)
    assignment_id = Column(UUID(as_uuid=True), ForeignKey("assignments.id", ondelete="SET NULL"), nullable=True)
    inspection_type = Column(String(50), nullable=False)  # 'QUESTIONNAIRE', 'NDT', 'VISUAL', 'EXPERTISE'
    inspector_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    inspection_date = Column(DateTime(timezone=True), nullable=False, index=True)
    data = Column(JSONB, nullable=False, default={})
    conclusion = Column(Text)
    next_inspection_date = Column(Date, nullable=True)
    status = Column(String(50), default='DRAFT')  # 'DRAFT', 'SIGNED', 'APPROVED'
    report_path = Column(String(500), nullable=True)
    word_report_path = Column(String(500), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class RepairJournal(Base):
    """Журнал ремонта оборудования (версия 3.3.0)"""
    __tablename__ = "repair_journal"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id", ondelete="CASCADE"), nullable=False, index=True)
    repair_date = Column(DateTime(timezone=True), nullable=False, index=True)
    repair_type = Column(String(100), nullable=False)  # 'MAINTENANCE', 'REPAIR', 'REPLACEMENT', 'MODIFICATION'
    description = Column(Text, nullable=False)
    performed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    cost = Column(Numeric(15, 2), nullable=True)
    documents = Column(JSONB, default=[])  # Массив путей к документам
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class VerificationEquipment(Base):
    """Оборудование для поверок (система управления поверками)"""
    __tablename__ = "verification_equipment"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)  # Название оборудования (например, "Ультразвуковой толщиномер УТ-93")
    equipment_type = Column(String(100), nullable=False)  # Тип: ВИК, УЗК, ПВК, РК, МК и т.д.
    category = Column(String(100))  # Категория для группировки
    serial_number = Column(String(100), nullable=False, index=True)  # Серийный номер
    manufacturer = Column(String(255))  # Производитель
    model = Column(String(255))  # Модель
    inventory_number = Column(String(100))  # Инвентарный номер
    verification_date = Column(Date, nullable=False, index=True)  # Дата последней поверки
    next_verification_date = Column(Date, nullable=False, index=True)  # Срок следующей поверки
    verification_certificate_number = Column(String(100))  # Номер свидетельства о поверке
    verification_organization = Column(String(255))  # Организация, проводившая поверку
    scan_file_path = Column(String(500))  # Путь к скану свидетельства о поверке
    scan_file_name = Column(String(255))  # Имя файла
    scan_file_size = Column(Integer)  # Размер файла
    scan_mime_type = Column(String(100))  # MIME тип
    is_active = Column(Integer, default=1)  # Активно ли оборудование
    notes = Column(Text)  # Примечания
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class VerificationHistory(Base):
    """История поверок оборудования"""
    __tablename__ = "verification_history"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    verification_equipment_id = Column(UUID(as_uuid=True), ForeignKey("verification_equipment.id", ondelete="CASCADE"), nullable=False, index=True)
    verification_date = Column(Date, nullable=False)
    next_verification_date = Column(Date, nullable=False)
    certificate_number = Column(String(100))
    verification_organization = Column(String(255))
    scan_file_path = Column(String(500))
    scan_file_name = Column(String(255))
    notes = Column(Text)
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class InspectionEquipment(Base):
    """Связь обследований с используемым оборудованием для поверок"""
    __tablename__ = "inspection_equipment"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    inspection_id = Column(UUID(as_uuid=True), ForeignKey("inspections.id", ondelete="CASCADE"), nullable=True, index=True)
    questionnaire_id = Column(UUID(as_uuid=True), ForeignKey("questionnaires.id", ondelete="CASCADE"), nullable=True, index=True)
    verification_equipment_id = Column(UUID(as_uuid=True), ForeignKey("verification_equipment.id", ondelete="RESTRICT"), nullable=False, index=True)
    used_at = Column(DateTime(timezone=True), server_default=func.now())  # Когда использовалось
    created_at = Column(DateTime(timezone=True), server_default=func.now())
