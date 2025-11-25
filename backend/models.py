from sqlalchemy import Column, String, Integer, Float, Date, DateTime, JSON, ForeignKey, Text, Boolean
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from datetime import datetime
import uuid
from database import Base

class EquipmentType(Base):
    __tablename__ = "equipment_types"
    
    id = Column(Integer, primary_key=True, index=True)
    code = Column(String(50), unique=True, nullable=False, index=True)
    name = Column(String(255), nullable=False)
    schema_definition = Column(JSONB, nullable=False)
    is_active = Column(Boolean, default=True)

class Equipment(Base):
    __tablename__ = "equipment"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    type_id = Column(Integer, ForeignKey("equipment_types.id"), nullable=False)
    name = Column(String(255), nullable=False)
    serial_number = Column(String(100))
    commissioning_date = Column(Date)
    geo_location = Column(Text)  # PostGIS GEOGRAPHY will be handled via raw SQL
    attributes = Column(JSONB)
    company_id = Column(UUID(as_uuid=True))
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    type = relationship("EquipmentType", backref="equipment")

class PipelineSegment(Base):
    __tablename__ = "pipeline_segments"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"))
    name = Column(String(255))
    segment_type = Column(String(50))  # ABOVE_GROUND, UNDERGROUND, CROSSING
    geometry = Column(Text)  # PostGIS LINESTRING
    corrosion_rate = Column(Float)
    thickness = Column(Float)
    last_inspection_date = Column(Date)
    remaining_life = Column(Float)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    equipment = relationship("Equipment", backref="pipeline_segments")

class Inspection(Base):
    __tablename__ = "inspections"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    equipment_id = Column(UUID(as_uuid=True), ForeignKey("equipment.id"), nullable=False)
    inspector_id = Column(UUID(as_uuid=True))
    date_performed = Column(DateTime(timezone=True), default=datetime.utcnow)
    data = Column(JSONB, nullable=False)
    conclusion = Column(Text)
    next_inspection_date = Column(Date)
    status = Column(String(50), default="DRAFT")  # DRAFT, SIGNED, APPROVED
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    equipment = relationship("Equipment", backref="inspections")

