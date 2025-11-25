from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime, date
import os
import uuid as uuid_lib
from database import get_db, engine, Base
from models import (
    Equipment, EquipmentType, PipelineSegment, Inspection,
    Client, Project, EquipmentResource, RegulatoryDocument,
    Engineer, Certification, Report
)
from report_generator import ReportGenerator
from pathlib import Path

app = FastAPI(
    title="ES TD NGO Platform API",
    description="API для системы учета оборудования и диагностирования",
    version="1.0.0"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # В продакшене указать конкретные домены
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup():
    """Initialize database on startup"""
    try:
        # Test database connection
        async with engine.begin() as conn:
            await conn.execute(text("SELECT 1"))
        print("✅ Database connection successful")
        
        # Create tables if they don't exist
        try:
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
            print("✅ Database tables checked/created")
        except Exception as e:
            print(f"⚠️  Warning: Could not create tables: {e}")
            
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
        import traceback
        traceback.print_exc()

@app.get("/")
async def root():
    return {
        "message": "ES TD NGO Platform API",
        "version": "1.0.0",
        "status": "running"
    }

# Аутентификация
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

@app.post("/api/auth/login")
async def login(form_data: OAuth2PasswordRequestForm = Depends()):
    """Вход в систему"""
    user = USERS_DB.get(form_data.username)
    if not user or user["password"] != form_data.password:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=60 * 24)
    access_token = create_access_token(
        data={"sub": form_data.username, "role": user["role"]},
        expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer", "role": user["role"]}

@app.get("/api/auth/me")
async def get_current_user(username: str = Depends(verify_token)):
    """Получить информацию о текущем пользователе"""
    user = USERS_DB.get(username)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "username": username,
        "role": user["role"],
        "permissions": user["permissions"]
    }

@app.get("/health")
async def health_check(db: AsyncSession = Depends(get_db)):
    """Health check endpoint"""
    try:
        result = await db.execute(text("SELECT 1"))
        return {
            "status": "healthy",
            "database": "connected"
        }
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database connection failed: {str(e)}")

# Аутентификация
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

@app.post("/api/auth/login")
async def login(form_data: OAuth2PasswordRequestForm = Depends()):
    """Вход в систему"""
    user = USERS_DB.get(form_data.username)
    if not user or user["password"] != form_data.password:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=60 * 24)
    access_token = create_access_token(
        data={"sub": form_data.username, "role": user["role"]},
        expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer", "role": user["role"]}

@app.get("/api/auth/me")
async def get_current_user(username: str = Depends(verify_token)):
    """Получить информацию о текущем пользователе"""
    user = USERS_DB.get(username)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "username": username,
        "role": user["role"],
        "permissions": user["permissions"]
    }

# Pydantic models for request/response
class EquipmentCreate(BaseModel):
    name: str
    type_id: Optional[str] = None
    serial_number: Optional[str] = None
    location: Optional[str] = None
    commissioning_date: Optional[str] = None
    attributes: Optional[dict] = None

class EquipmentUpdate(BaseModel):
    name: Optional[str] = None
    type_id: Optional[str] = None
    serial_number: Optional[str] = None
    location: Optional[str] = None
    commissioning_date: Optional[str] = None
    attributes: Optional[dict] = None

# Equipment endpoints
@app.get("/api/equipment")
async def get_equipment(
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Get list of equipment"""
    try:
        # Check if table exists
        try:
            result = await db.execute(
                select(Equipment).offset(skip).limit(limit)
            )
            equipment = result.scalars().all()
        except Exception as table_error:
            # If table doesn't exist, try to create it
            error_msg = str(table_error).lower()
            if "does not exist" in error_msg or "relation" in error_msg:
                print("⚠️  Table 'equipment' not found, creating tables...")
                try:
                    async with engine.begin() as conn:
                        await conn.run_sync(Base.metadata.create_all)
                    # Retry query after creating tables
                    result = await db.execute(
                        select(Equipment).offset(skip).limit(limit)
                    )
                    equipment = result.scalars().all()
                    print("✅ Tables created, returning empty list")
                except Exception as create_error:
                    print(f"❌ Failed to create tables: {create_error}")
                    raise HTTPException(
                        status_code=500,
                        detail=f"Database table creation failed: {str(create_error)}"
                    )
            else:
                raise table_error
        
        return {
            "items": [
                {
                    "id": str(eq.id),
                    "name": eq.name,
                    "type_id": str(eq.type_id) if eq.type_id else None,
                    "serial_number": eq.serial_number,
                    "location": eq.location,
                    "attributes": eq.attributes or {},
                    "commissioning_date": str(eq.commissioning_date) if eq.commissioning_date else None,
                    "created_at": str(eq.created_at) if eq.created_at else None,
                }
                for eq in equipment
            ],
            "total": len(equipment)
        }
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        print(f"❌ Error in get_equipment: {error_detail}")
        print(traceback.format_exc())
        raise HTTPException(
            status_code=500, 
            detail=f"Database error: {error_detail}"
        )

@app.get("/api/equipment/{equipment_id}")
async def get_equipment_by_id(
    equipment_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Get equipment by ID"""
    try:
        result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")
        return {
            "id": str(eq.id),
            "name": eq.name,
            "type_id": str(eq.type_id) if eq.type_id else None,
            "serial_number": eq.serial_number,
            "location": eq.location,
            "attributes": eq.attributes or {},
            "commissioning_date": str(eq.commissioning_date) if eq.commissioning_date else None,
            "created_at": str(eq.created_at) if eq.created_at else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/equipment")
async def create_equipment(
    equipment_data: EquipmentCreate,
    db: AsyncSession = Depends(get_db)
):
    """Create new equipment"""
    try:
        # Parse commissioning_date if provided
        commissioning_date = None
        if equipment_data.commissioning_date:
            try:
                commissioning_date = datetime.fromisoformat(equipment_data.commissioning_date.replace('Z', '+00:00')).date()
            except:
                pass
        
        # Parse type_id if provided
        type_id = None
        if equipment_data.type_id:
            try:
                type_id = uuid_lib.UUID(equipment_data.type_id)
            except:
                pass
        
        new_equipment = Equipment(
            name=equipment_data.name,
            type_id=type_id,
            serial_number=equipment_data.serial_number,
            location=equipment_data.location,
            commissioning_date=commissioning_date,
            attributes=equipment_data.attributes or {}
        )
        db.add(new_equipment)
        await db.commit()
        await db.refresh(new_equipment)
        return {
            "id": str(new_equipment.id),
            "name": new_equipment.name,
            "type_id": str(new_equipment.type_id) if new_equipment.type_id else None,
            "serial_number": new_equipment.serial_number,
            "location": new_equipment.location,
            "attributes": new_equipment.attributes or {},
            "status": "created"
        }
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to create equipment: {str(e)}")

@app.put("/api/equipment/{equipment_id}")
async def update_equipment(
    equipment_id: str,
    equipment_data: EquipmentUpdate,
    db: AsyncSession = Depends(get_db)
):
    """Update equipment"""
    try:
        result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        # Update fields if provided
        if equipment_data.name is not None:
            eq.name = equipment_data.name
        if equipment_data.serial_number is not None:
            eq.serial_number = equipment_data.serial_number
        if equipment_data.location is not None:
            eq.location = equipment_data.location
        if equipment_data.attributes is not None:
            eq.attributes = equipment_data.attributes
        if equipment_data.commissioning_date is not None:
            try:
                eq.commissioning_date = datetime.fromisoformat(equipment_data.commissioning_date.replace('Z', '+00:00')).date()
            except:
                pass
        if equipment_data.type_id is not None:
            try:
                eq.type_id = uuid_lib.UUID(equipment_data.type_id)
            except:
                pass
        
        await db.commit()
        await db.refresh(eq)
        return {
            "id": str(eq.id),
            "name": eq.name,
            "type_id": str(eq.type_id) if eq.type_id else None,
            "serial_number": eq.serial_number,
            "location": eq.location,
            "attributes": eq.attributes or {},
            "status": "updated"
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to update equipment: {str(e)}")

@app.delete("/api/equipment/{equipment_id}")
async def delete_equipment(
    equipment_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Delete equipment"""
    try:
        result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        await db.delete(eq)
        await db.commit()
        return {"status": "deleted", "id": equipment_id}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete equipment: {str(e)}")

# Equipment types endpoints
@app.get("/api/equipment-types")
async def get_equipment_types(
    db: AsyncSession = Depends(get_db)
):
    """Get list of equipment types"""
    try:
        result = await db.execute(
            select(EquipmentType).where(EquipmentType.is_active == 1)
        )
        types = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(et.id),
                    "name": et.name,
                    "description": et.description,
                    "code": et.code,
                }
                for et in types
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Pipeline segments endpoints
@app.get("/api/pipelines")
async def get_pipelines(db: AsyncSession = Depends(get_db)):
    """Get pipeline segments"""
    try:
        result = await db.execute(select(PipelineSegment))
        segments = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(seg.id),
                    "name": seg.name,
                    "segment_type": seg.segment_type,
                    "corrosion_rate": seg.corrosion_rate,
                    "thickness": seg.thickness,
                    "last_inspection_date": str(seg.last_inspection_date) if seg.last_inspection_date else None,
                    "remaining_life": seg.remaining_life,
                }
                for seg in segments
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Inspections endpoints
@app.get("/api/inspections")
async def get_inspections(
    equipment_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Get inspections"""
    try:
        query = select(Inspection)
        if equipment_id:
            try:
                equipment_uuid = uuid_lib.UUID(equipment_id)
                query = query.where(Inspection.equipment_id == equipment_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        query = query.order_by(Inspection.date_performed.desc() if Inspection.date_performed else Inspection.created_at.desc())
        query = query.offset(skip).limit(limit)
        
        result = await db.execute(query)
        inspections = result.scalars().all()
        
        # Получаем информацию об оборудовании для каждого inspection
        equipment_ids = [str(insp.equipment_id) for insp in inspections if insp.equipment_id]
        equipment_map = {}
        if equipment_ids:
            equipment_result = await db.execute(
                select(Equipment).where(Equipment.id.in_([uuid_lib.UUID(eid) for eid in equipment_ids]))
            )
            for eq in equipment_result.scalars().all():
                equipment_map[str(eq.id)] = {
                    "name": eq.name,
                    "location": eq.location
                }
        
        return {
            "items": [
                {
                    "id": str(ins.id),
                    "equipment_id": str(ins.equipment_id),
                    "equipment_name": equipment_map.get(str(ins.equipment_id), {}).get("name"),
                    "equipment_location": equipment_map.get(str(ins.equipment_id), {}).get("location"),
                    "date_performed": ins.date_performed.isoformat() if ins.date_performed else None,
                    "data": ins.data,
                    "conclusion": ins.conclusion,
                    "status": ins.status,
                    "created_at": ins.created_at.isoformat() if ins.created_at else None,
                }
                for ins in inspections
            ],
            "total": len(inspections)
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/inspections")
async def create_inspection(
    inspection_data: dict,
    db: AsyncSession = Depends(get_db)
):
    """Create new inspection"""
    try:
        # Parse equipment_id
        equipment_id = None
        if inspection_data.get("equipment_id"):
            try:
                equipment_id = uuid_lib.UUID(inspection_data.get("equipment_id"))
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        # Parse date_performed if provided
        date_performed = None
        if inspection_data.get("date_performed"):
            try:
                date_performed = datetime.fromisoformat(inspection_data.get("date_performed").replace('Z', '+00:00'))
            except:
                pass
        
        new_inspection = Inspection(
            equipment_id=equipment_id,
            data=inspection_data.get("data", {}),
            conclusion=inspection_data.get("conclusion"),
            status=inspection_data.get("status", "DRAFT"),
            date_performed=date_performed
        )
        db.add(new_inspection)
        await db.commit()
        await db.refresh(new_inspection)
        return {
            "id": str(new_inspection.id),
            "equipment_id": str(new_inspection.equipment_id),
            "status": "created",
            "date_performed": new_inspection.date_performed.isoformat() if new_inspection.date_performed else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to create inspection: {str(e)}")

# Clients endpoints
@app.get("/api/clients")
async def get_clients(
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Get list of clients"""
    try:
        result = await db.execute(
            select(Client).where(Client.is_active == 1).offset(skip).limit(limit)
        )
        clients = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(c.id),
                    "name": c.name,
                    "inn": c.inn,
                    "address": c.address,
                    "contact_person": c.contact_person,
                    "contact_phone": c.contact_phone,
                    "contact_email": c.contact_email,
                }
                for c in clients
            ],
            "total": len(clients)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/clients")
async def create_client(client_data: dict, db: AsyncSession = Depends(get_db)):
    """Create new client"""
    try:
        new_client = Client(
            name=client_data.get("name"),
            inn=client_data.get("inn"),
            address=client_data.get("address"),
            contact_person=client_data.get("contact_person"),
            contact_phone=client_data.get("contact_phone"),
            contact_email=client_data.get("contact_email"),
            notes=client_data.get("notes")
        )
        db.add(new_client)
        await db.commit()
        await db.refresh(new_client)
        return {"id": str(new_client.id), "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Projects endpoints
@app.get("/api/projects")
async def get_projects(
    client_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Get list of projects"""
    try:
        query = select(Project)
        if client_id:
            try:
                client_uuid = uuid_lib.UUID(client_id)
                query = query.where(Project.client_id == client_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid client_id format")
        query = query.offset(skip).limit(limit)
        
        result = await db.execute(query)
        projects = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(p.id),
                    "client_id": str(p.client_id),
                    "name": p.name,
                    "description": p.description,
                    "status": p.status,
                    "start_date": str(p.start_date) if p.start_date else None,
                    "end_date": str(p.end_date) if p.end_date else None,
                    "deadline": str(p.deadline) if p.deadline else None,
                    "budget": float(p.budget) if p.budget else None,
                }
                for p in projects
            ],
            "total": len(projects)
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/projects")
async def create_project(project_data: dict, db: AsyncSession = Depends(get_db)):
    """Create new project"""
    try:
        client_id = None
        if project_data.get("client_id"):
            try:
                client_id = uuid_lib.UUID(project_data.get("client_id"))
            except:
                raise HTTPException(status_code=400, detail="Invalid client_id format")
        
        new_project = Project(
            client_id=client_id,
            name=project_data.get("name"),
            description=project_data.get("description"),
            status=project_data.get("status", "PLANNED"),
            start_date=datetime.fromisoformat(project_data.get("start_date")).date() if project_data.get("start_date") else None,
            end_date=datetime.fromisoformat(project_data.get("end_date")).date() if project_data.get("end_date") else None,
            deadline=datetime.fromisoformat(project_data.get("deadline")).date() if project_data.get("deadline") else None,
            budget=project_data.get("budget")
        )
        db.add(new_project)
        await db.commit()
        await db.refresh(new_project)
        return {"id": str(new_project.id), "status": "created"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Equipment Resource endpoints
@app.get("/api/equipment-resources")
async def get_equipment_resources(
    equipment_id: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """Get equipment resources"""
    try:
        query = select(EquipmentResource)
        if equipment_id:
            try:
                eq_uuid = uuid_lib.UUID(equipment_id)
                query = query.where(EquipmentResource.equipment_id == eq_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        result = await db.execute(query.order_by(EquipmentResource.created_at.desc()))
        resources = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(r.id),
                    "equipment_id": str(r.equipment_id),
                    "remaining_resource_years": float(r.remaining_resource_years) if r.remaining_resource_years else None,
                    "resource_end_date": str(r.resource_end_date) if r.resource_end_date else None,
                    "extension_years": float(r.extension_years) if r.extension_years else None,
                    "extension_date": str(r.extension_date) if r.extension_date else None,
                    "status": r.status,
                    "document_number": r.document_number,
                }
                for r in resources
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/equipment-resources")
async def create_equipment_resource(resource_data: dict, db: AsyncSession = Depends(get_db)):
    """Create equipment resource record"""
    try:
        equipment_id = None
        if resource_data.get("equipment_id"):
            try:
                equipment_id = uuid_lib.UUID(resource_data.get("equipment_id"))
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        new_resource = EquipmentResource(
            equipment_id=equipment_id,
            remaining_resource_years=resource_data.get("remaining_resource_years"),
            resource_end_date=datetime.fromisoformat(resource_data.get("resource_end_date")).date() if resource_data.get("resource_end_date") else None,
            extension_years=resource_data.get("extension_years"),
            extension_date=datetime.fromisoformat(resource_data.get("extension_date")).date() if resource_data.get("extension_date") else None,
            calculation_method=resource_data.get("calculation_method"),
            calculation_data=resource_data.get("calculation_data", {}),
            document_number=resource_data.get("document_number"),
            status=resource_data.get("status", "ACTIVE")
        )
        db.add(new_resource)
        await db.commit()
        await db.refresh(new_resource)
        return {"id": str(new_resource.id), "status": "created"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Regulatory Documents endpoints
@app.get("/api/regulatory-documents")
async def get_regulatory_documents(
    document_type: Optional[str] = None,
    equipment_type: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """Get regulatory documents"""
    try:
        query = select(RegulatoryDocument).where(RegulatoryDocument.is_active == 1)
        if document_type:
            query = query.where(RegulatoryDocument.document_type == document_type)
        
        result = await db.execute(query)
        docs = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(d.id),
                    "document_type": d.document_type,
                    "number": d.number,
                    "name": d.name,
                    "description": d.description,
                    "equipment_types": d.equipment_types,
                    "effective_date": str(d.effective_date) if d.effective_date else None,
                    "expiry_date": str(d.expiry_date) if d.expiry_date else None,
                }
                for d in docs
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/regulatory-documents")
async def create_regulatory_document(doc_data: dict, db: AsyncSession = Depends(get_db)):
    """Create regulatory document"""
    try:
        new_doc = RegulatoryDocument(
            document_type=doc_data.get("document_type"),
            number=doc_data.get("number"),
            name=doc_data.get("name"),
            description=doc_data.get("description"),
            content=doc_data.get("content"),
            file_path=doc_data.get("file_path"),
            equipment_types=doc_data.get("equipment_types", []),
            requirements=doc_data.get("requirements", {}),
            effective_date=datetime.fromisoformat(doc_data.get("effective_date")).date() if doc_data.get("effective_date") else None,
            expiry_date=datetime.fromisoformat(doc_data.get("expiry_date")).date() if doc_data.get("expiry_date") else None,
        )
        db.add(new_doc)
        await db.commit()
        await db.refresh(new_doc)
        return {"id": str(new_doc.id), "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Engineers endpoints
@app.get("/api/engineers")
async def get_engineers(db: AsyncSession = Depends(get_db)):
    """Get list of engineers"""
    try:
        result = await db.execute(
            select(Engineer).where(Engineer.is_active == 1)
        )
        engineers = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(e.id),
                    "full_name": e.full_name,
                    "position": e.position,
                    "email": e.email,
                    "phone": e.phone,
                    "qualifications": e.qualifications,
                    "certifications": e.certifications,
                    "equipment_types": e.equipment_types,
                }
                for e in engineers
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/engineers")
async def create_engineer(engineer_data: dict, db: AsyncSession = Depends(get_db)):
    """Create engineer"""
    try:
        new_engineer = Engineer(
            full_name=engineer_data.get("full_name"),
            position=engineer_data.get("position"),
            email=engineer_data.get("email"),
            phone=engineer_data.get("phone"),
            qualifications=engineer_data.get("qualifications", []),
            certifications=engineer_data.get("certifications", []),
            equipment_types=engineer_data.get("equipment_types", []),
        )
        db.add(new_engineer)
        await db.commit()
        await db.refresh(new_engineer)
        return {"id": str(new_engineer.id), "status": "created"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Certifications endpoints
@app.get("/api/certifications")
async def get_certifications(
    engineer_id: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """Get certifications"""
    try:
        query = select(Certification).where(Certification.is_active == 1)
        if engineer_id:
            try:
                eng_uuid = uuid_lib.UUID(engineer_id)
                query = query.where(Certification.engineer_id == eng_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid engineer_id format")
        
        result = await db.execute(query)
        certs = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(c.id),
                    "engineer_id": str(c.engineer_id),
                    "certification_type": c.certification_type,
                    "number": c.number,
                    "issued_by": c.issued_by,
                    "issue_date": str(c.issue_date) if c.issue_date else None,
                    "expiry_date": str(c.expiry_date) if c.expiry_date else None,
                }
                for c in certs
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Reports endpoints
@app.get("/api/reports")
async def get_reports(
    inspection_id: Optional[str] = None,
    equipment_id: Optional[str] = None,
    project_id: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """Get reports"""
    try:
        query = select(Report)
        if inspection_id:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                query = query.where(Report.inspection_id == insp_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid inspection_id format")
        if equipment_id:
            try:
                eq_uuid = uuid_lib.UUID(equipment_id)
                query = query.where(Report.equipment_id == eq_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        if project_id:
            try:
                proj_uuid = uuid_lib.UUID(project_id)
                query = query.where(Report.project_id == proj_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid project_id format")
        
        result = await db.execute(query.order_by(Report.created_at.desc()))
        reports = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(r.id),
                    "inspection_id": str(r.inspection_id) if r.inspection_id else None,
                    "equipment_id": str(r.equipment_id),
                    "project_id": str(r.project_id) if r.project_id else None,
                    "report_type": r.report_type,
                    "title": r.title,
                    "file_path": r.file_path,
                    "file_size": r.file_size,
                    "status": r.status,
                    "created_at": r.created_at.isoformat() if r.created_at else None,
                }
                for r in reports
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/reports/generate")
async def generate_report(report_data: dict, db: AsyncSession = Depends(get_db)):
    """Generate technical report or expertise"""
    try:
        inspection_id = None
        if report_data.get("inspection_id"):
            try:
                inspection_id = uuid_lib.UUID(report_data.get("inspection_id"))
            except:
                raise HTTPException(status_code=400, detail="Invalid inspection_id format")
        
        # Get inspection data
        if inspection_id:
            result = await db.execute(
                select(Inspection).where(Inspection.id == inspection_id)
            )
            inspection = result.scalar_one_or_none()
            if not inspection:
                raise HTTPException(status_code=404, detail="Inspection not found")
            
            # Get equipment data
            eq_result = await db.execute(
                select(Equipment).where(Equipment.id == inspection.equipment_id)
            )
            equipment = eq_result.scalar_one_or_none()
            if not equipment:
                raise HTTPException(status_code=404, detail="Equipment not found")
            
            # Get resource data if expertise
            resource_data = None
            if report_data.get("report_type") == "EXPERTISE":
                res_result = await db.execute(
                    select(EquipmentResource).where(EquipmentResource.equipment_id == equipment.id)
                    .order_by(EquipmentResource.created_at.desc())
                )
                resource = res_result.scalar_one_or_none()
                if resource:
                    resource_data = {
                        "remaining_resource_years": float(resource.remaining_resource_years) if resource.remaining_resource_years else None,
                        "resource_end_date": str(resource.resource_end_date) if resource.resource_end_date else None,
                        "extension_years": float(resource.extension_years) if resource.extension_years else None,
                        "extension_date": str(resource.extension_date) if resource.extension_date else None,
                    }
            
            # Generate report
            generator = ReportGenerator()
            reports_dir = Path("/app/reports")
            reports_dir.mkdir(exist_ok=True)
            
            report_type = report_data.get("report_type", "TECHNICAL_REPORT")
            filename = f"{report_type}_{inspection.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
            file_path = reports_dir / filename
            
            if report_type == "EXPERTISE":
                generator.generate_expertise_report(
                    {
                        "date_performed": inspection.date_performed.isoformat() if inspection.date_performed else None,
                        "data": inspection.data,
                        "conclusion": inspection.conclusion,
                        "status": inspection.status,
                    },
                    {
                        "id": str(equipment.id),
                        "name": equipment.name,
                        "serial_number": equipment.serial_number,
                        "location": equipment.location,
                        "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                        "attributes": equipment.attributes or {},
                    },
                    resource_data,
                    str(file_path)
                )
            else:
                generator.generate_technical_report(
                    {
                        "date_performed": inspection.date_performed.isoformat() if inspection.date_performed else None,
                        "data": inspection.data,
                        "conclusion": inspection.conclusion,
                        "status": inspection.status,
                    },
                    {
                        "id": str(equipment.id),
                        "name": equipment.name,
                        "serial_number": equipment.serial_number,
                        "location": equipment.location,
                        "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                        "attributes": equipment.attributes or {},
                    },
                    str(file_path)
                )
            
            # Save report record
            new_report = Report(
                inspection_id=inspection_id,
                equipment_id=equipment.id,
                project_id=inspection.project_id,
                report_type=report_type,
                title=report_data.get("title", f"{report_type} для {equipment.name}"),
                file_path=str(file_path),
                file_size=file_path.stat().st_size if file_path.exists() else 0,
                status="DRAFT"
            )
            db.add(new_report)
            await db.commit()
            await db.refresh(new_report)
            
            return {
                "id": str(new_report.id),
                "file_path": str(file_path),
                "file_size": new_report.file_size,
                "status": "generated"
            }
        else:
            raise HTTPException(status_code=400, detail="inspection_id is required")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to generate report: {str(e)}")

@app.get("/api/reports/{report_id}/download")
async def download_report(report_id: str, db: AsyncSession = Depends(get_db)):
    """Download report file"""
    try:
        result = await db.execute(
            select(Report).where(Report.id == report_id)
        )
        report = result.scalar_one_or_none()
        if not report:
            raise HTTPException(status_code=404, detail="Report not found")
        
        if not report.file_path or not os.path.exists(report.file_path):
            raise HTTPException(status_code=404, detail="Report file not found")
        
        from fastapi.responses import FileResponse
        return FileResponse(
            report.file_path,
            media_type='application/pdf',
            filename=os.path.basename(report.file_path)
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
