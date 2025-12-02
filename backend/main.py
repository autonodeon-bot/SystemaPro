from fastapi import FastAPI, Depends, HTTPException, status, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text, func
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime, date, timedelta
import os
import uuid as uuid_lib
from database import get_db, engine, Base
from models import (
    Equipment, EquipmentType, PipelineSegment, Inspection,
    Client, Project, EquipmentResource, RegulatoryDocument,
    Engineer, Certification, Report, User as UserModel,
    UserEquipmentAccess, UserProjectAccess, Questionnaire,
    Workshop, WorkshopEngineerAccess
)
from report_generator import ReportGenerator
from auth import (
    create_access_token, verify_token, hash_password, verify_password,
    get_user_by_username, get_user_by_email, get_user_by_id,
    check_equipment_access, check_project_access,
    get_user_accessible_equipment_ids, get_user_accessible_project_ids,
    require_permission, require_role, get_user_permissions
)
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
async def login(form_data: OAuth2PasswordRequestForm = Depends(), db: AsyncSession = Depends(get_db)):
    """Вход в систему"""
    try:
        # Ищем пользователя по username или email
        user = await get_user_by_username(db, form_data.username)
        if not user:
            user = await get_user_by_email(db, form_data.username)
        
        if not user:
            print(f"❌ Пользователь не найден: {form_data.username}")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect username or password",
                headers={"WWW-Authenticate": "Bearer"},
            )
        
        if not user.is_active:
            print(f"❌ Пользователь неактивен: {form_data.username}")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect username or password",
                headers={"WWW-Authenticate": "Bearer"},
            )
        
        # Проверяем пароль
        if not verify_password(form_data.password, user.password_hash):
            print(f"❌ Неверный пароль для пользователя: {form_data.username}")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect username or password",
                headers={"WWW-Authenticate": "Bearer"},
            )
        
        # Обновляем время последнего входа
        user.last_login = datetime.utcnow()
        await db.commit()
        
        access_token_expires = timedelta(minutes=60 * 24)
        access_token = create_access_token(
            data={"sub": user.username, "role": user.role, "user_id": str(user.id)},
            expires_delta=access_token_expires
        )
        print(f"✅ Успешный вход: {user.username} ({user.role})")
        return {
            "access_token": access_token,
            "token_type": "bearer",
            "role": user.role,
            "user_id": str(user.id)
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Ошибка при входе: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Internal server error: {str(e)}"
        )

@app.get("/api/auth/me")
async def get_current_user(user: UserModel = Depends(verify_token), db: AsyncSession = Depends(get_db)):
    """Получить информацию о текущем пользователе"""
    engineer = None
    if user.engineer_id:
        result = await db.execute(
            select(Engineer).where(Engineer.id == user.engineer_id)
        )
        engineer = result.scalar_one_or_none()
    
    response = {
        "id": str(user.id),
        "username": user.username,
        "email": user.email,
        "full_name": user.full_name or user.username,
        "role": user.role,
        "permissions": get_user_permissions(user.role),
        "is_active": user.is_active
    }
    
    if engineer:
        response.update({
            "engineer_id": str(engineer.id),
            "position": engineer.position,
            "phone": engineer.phone,
            "qualifications": engineer.qualifications or {},
            "certifications": engineer.certifications or [],
            "equipment_types": engineer.equipment_types or [],
        })
    
    return response

# Pydantic models for request/response
class EquipmentCreate(BaseModel):
    name: str
    type_id: Optional[str] = None
    workshop_id: Optional[str] = None
    serial_number: Optional[str] = None
    location: Optional[str] = None
    commissioning_date: Optional[str] = None
    attributes: Optional[dict] = None

class EquipmentUpdate(BaseModel):
    name: Optional[str] = None
    type_id: Optional[str] = None
    workshop_id: Optional[str] = None
    serial_number: Optional[str] = None
    location: Optional[str] = None
    commissioning_date: Optional[str] = None
    attributes: Optional[dict] = None

# Equipment endpoints
@app.get("/api/equipment")
async def get_equipment(
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """Get list of equipment (filtered by user access)"""
    try:
        # Получаем доступное оборудование для пользователя
        accessible_ids = await get_user_accessible_equipment_ids(db, user)
        
        # Check if table exists
        try:
            query = select(Equipment)
            # Если инженер - фильтруем по доступным ID
            if user.role == "engineer" and accessible_ids:
                from uuid import UUID
                query = query.where(Equipment.id.in_([UUID(eid) for eid in accessible_ids]))
            elif user.role == "engineer" and not accessible_ids:
                # Нет доступа ни к одному оборудованию
                return {"items": [], "total": 0}
            
            result = await db.execute(query.offset(skip).limit(limit))
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
                    "workshop_id": str(eq.workshop_id) if eq.workshop_id else None,
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
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """Get equipment by ID (with access check)"""
    try:
        result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        # Проверяем доступ
        has_access = await check_equipment_access(db, user, equipment_id, "read")
        if not has_access:
            raise HTTPException(status_code=403, detail="Access denied to this equipment")
        
        return {
            "id": str(eq.id),
            "name": eq.name,
            "type_id": str(eq.type_id) if eq.type_id else None,
            "workshop_id": str(eq.workshop_id) if eq.workshop_id else None,
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
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """Create new equipment"""
    try:
        # Проверяем права доступа
        # Админ, главный оператор и оператор могут создавать везде
        # Инженер может создавать только в своих цехах
        if user.role not in ["admin", "chief_operator", "operator"]:
            # Для инженера проверяем доступ к цеху
            if user.role == "engineer" and user.engineer_id:
                if equipment_data.workshop_id:
                    # Проверяем, есть ли у инженера доступ к этому цеху
                    from sqlalchemy import select
                    from models import WorkshopEngineerAccess
                    result = await db.execute(
                        select(WorkshopEngineerAccess).where(
                            WorkshopEngineerAccess.workshop_id == uuid_lib.UUID(equipment_data.workshop_id),
                            WorkshopEngineerAccess.engineer_id == user.engineer_id,
                            WorkshopEngineerAccess.is_active == True
                        )
                    )
                    access = result.scalar_one_or_none()
                    if not access:
                        raise HTTPException(status_code=403, detail="Access denied to this workshop")
                else:
                    raise HTTPException(status_code=400, detail="Engineer must specify workshop_id")
            else:
                raise HTTPException(status_code=403, detail="Insufficient permissions")
        
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
        
        # Parse workshop_id if provided
        workshop_id = None
        if equipment_data.workshop_id:
            try:
                workshop_id = uuid_lib.UUID(equipment_data.workshop_id)
            except:
                pass
        
        new_equipment = Equipment(
            name=equipment_data.name,
            type_id=type_id,
            workshop_id=workshop_id,
            serial_number=equipment_data.serial_number,
            location=equipment_data.location,
            commissioning_date=commissioning_date,
            attributes=equipment_data.attributes or {},
            created_by=user.id
        )
        db.add(new_equipment)
        await db.commit()
        await db.refresh(new_equipment)
        return {
            "id": str(new_equipment.id),
            "name": new_equipment.name,
            "type_id": str(new_equipment.type_id) if new_equipment.type_id else None,
            "workshop_id": str(new_equipment.workshop_id) if new_equipment.workshop_id else None,
            "serial_number": new_equipment.serial_number,
            "location": new_equipment.location,
            "attributes": new_equipment.attributes or {},
            "status": "created"
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to create equipment: {str(e)}")

@app.put("/api/equipment/{equipment_id}")
async def update_equipment(
    equipment_id: str,
    equipment_data: EquipmentUpdate,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """Update equipment (with access check)"""
    try:
        result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        eq = result.scalar_one_or_none()
        if not eq:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        # Проверяем доступ (для инженера - только к своему оборудованию)
        has_access = await check_equipment_access(db, user, equipment_id, "write")
        if not has_access:
            raise HTTPException(status_code=403, detail="Access denied to modify this equipment")
        
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
            "workshop_id": str(eq.workshop_id) if eq.workshop_id else None,
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
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(require_permission("delete"))
):
    """Delete equipment (requires delete permission)"""
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
        from sqlalchemy import desc, nullslast
        query = select(Inspection)
        if equipment_id:
            try:
                equipment_uuid = uuid_lib.UUID(equipment_id)
                query = query.where(Inspection.equipment_id == equipment_uuid)
            except ValueError:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        # Правильная сортировка: сначала по date_performed, потом по created_at
        query = query.order_by(
            nullslast(desc(Inspection.date_performed)),
            desc(Inspection.created_at)
        )
        query = query.offset(skip).limit(limit)
        
        result = await db.execute(query)
        inspections = result.scalars().all()
        
        # Получаем информацию об оборудовании для каждого inspection
        equipment_ids = [str(insp.equipment_id) for insp in inspections if insp.equipment_id]
        equipment_map = {}
        if equipment_ids:
            try:
                equipment_result = await db.execute(
                    select(Equipment).where(Equipment.id.in_([uuid_lib.UUID(eid) for eid in equipment_ids]))
                )
                for eq in equipment_result.scalars().all():
                    equipment_map[str(eq.id)] = {
                        "name": eq.name,
                        "location": eq.location
                    }
            except Exception as e:
                print(f"Ошибка при загрузке оборудования: {e}")
        
        return {
            "items": [
                {
                    "id": str(ins.id),
                    "equipment_id": str(ins.equipment_id) if ins.equipment_id else None,
                    "equipment_name": equipment_map.get(str(ins.equipment_id), {}).get("name") if ins.equipment_id else None,
                    "equipment_location": equipment_map.get(str(ins.equipment_id), {}).get("location") if ins.equipment_id else None,
                    "date_performed": ins.date_performed.isoformat() if ins.date_performed else None,
                    "data": ins.data or {},
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
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to get inspections: {str(e)}")

@app.post("/api/inspections")
async def create_inspection(
    inspection_data: dict,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """Create new inspection (with access check)"""
    try:
        # Parse equipment_id
        equipment_id = None
        equipment_id_str = inspection_data.get("equipment_id")
        if equipment_id_str:
            try:
                equipment_id = uuid_lib.UUID(equipment_id_str)
                # Проверяем доступ к оборудованию
                has_access = await check_equipment_access(db, user, equipment_id_str, "write")
                if not has_access:
                    raise HTTPException(status_code=403, detail="Access denied to this equipment")
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
            inspector_id=user.id,  # Сохраняем ID пользователя, создавшего инспекцию
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
        
        result = await db.execute(query.order_by(Certification.issue_date.desc() if Certification.issue_date else Certification.created_at.desc()))
        certifications = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(c.id),
                    "engineer_id": str(c.engineer_id),
                    "certification_type": c.certification_type,
                    "method": c.method,
                    "level": c.level,
                    "number": c.number,
                    "issued_by": c.issued_by,
                    "issue_date": c.issue_date.isoformat() if c.issue_date else None,
                    "expiry_date": c.expiry_date.isoformat() if c.expiry_date else None,
                    "file_path": c.file_path,
                }
                for c in certifications
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/certifications")
async def create_certification(
    engineer_id: str = Form(...),
    certification_type: str = Form(...),
    method: str = Form(...),
    level: str = Form(...),
    number: str = Form(...),
    issued_by: str = Form(...),
    issue_date: Optional[str] = Form(None),
    expiry_date: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """Create certification with optional file upload"""
    try:
        engineer_uuid = uuid_lib.UUID(engineer_id)
        
        # Проверка существования инженера
        engineer_result = await db.execute(
            select(Engineer).where(Engineer.id == engineer_uuid)
        )
        engineer = engineer_result.scalar_one_or_none()
        if not engineer:
            raise HTTPException(status_code=404, detail="Engineer not found")
        
        # Сохранение файла, если загружен
        file_path = None
        if file and file.filename:
            # Создаем директорию для сертификатов
            certs_dir = Path("/app/certs")
            certs_dir.mkdir(exist_ok=True)
            
            # Генерируем уникальное имя файла
            file_ext = Path(file.filename).suffix
            file_name = f"{uuid_lib.uuid4()}{file_ext}"
            file_path_full = certs_dir / file_name
            
            # Сохраняем файл
            with open(file_path_full, "wb") as f:
                content = await file.read()
                f.write(content)
            
            file_path = str(file_path_full)
        
        # Парсинг дат
        issue_date_obj = None
        if issue_date:
            try:
                issue_date_obj = datetime.fromisoformat(issue_date.replace('Z', '+00:00')).date()
            except:
                pass
        
        expiry_date_obj = None
        if expiry_date:
            try:
                expiry_date_obj = datetime.fromisoformat(expiry_date.replace('Z', '+00:00')).date()
            except:
                pass
        
        # Создание сертификата
        new_cert = Certification(
            engineer_id=engineer_uuid,
            certification_type=certification_type,
            method=method,
            level=level,
            number=number,
            issued_by=issued_by,
            issue_date=issue_date_obj,
            expiry_date=expiry_date_obj,
            file_path=file_path,
            is_active=1
        )
        
        db.add(new_cert)
        await db.commit()
        await db.refresh(new_cert)
        
        return {
            "id": str(new_cert.id),
            "engineer_id": str(new_cert.engineer_id),
            "certification_type": new_cert.certification_type,
            "method": new_cert.method,
            "level": new_cert.level,
            "number": new_cert.number,
            "issued_by": new_cert.issued_by,
            "issue_date": new_cert.issue_date.isoformat() if new_cert.issue_date else None,
            "expiry_date": new_cert.expiry_date.isoformat() if new_cert.expiry_date else None,
            "file_path": new_cert.file_path,
            "status": "created"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid engineer_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to create certification: {str(e)}")

# Engineer statistics endpoint
@app.get("/api/engineers/{engineer_id}/stats")
async def get_engineer_stats(engineer_id: str, db: AsyncSession = Depends(get_db)):
    """Get statistics for an engineer"""
    try:
        engineer_uuid = uuid_lib.UUID(engineer_id)
        
        # Count inspections
        inspections_result = await db.execute(
            select(func.count(Inspection.id)).where(Inspection.inspector_id == engineer_uuid)
        )
        total_inspections = inspections_result.scalar() or 0
        
        # Count reports
        reports_result = await db.execute(
            select(func.count(Report.id))
            .join(Inspection, Report.inspection_id == Inspection.id)
            .where(Inspection.inspector_id == engineer_uuid)
        )
        total_reports = reports_result.scalar() or 0
        
        # Count active projects
        projects_result = await db.execute(
            select(func.count(Project.id))
            .where(Project.manager_id == engineer_uuid)
            .where(Project.status == "IN_PROGRESS")
        )
        active_projects = projects_result.scalar() or 0
        
        # Count certifications
        certs_result = await db.execute(
            select(func.count(Certification.id)).where(Certification.engineer_id == engineer_uuid)
        )
        certifications_count = certs_result.scalar() or 0
        
        return {
            "total_inspections": total_inspections,
            "total_reports": total_reports,
            "active_projects": active_projects,
            "certifications_count": certifications_count,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid engineer_id format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Engineer documents endpoint
@app.get("/api/engineers/{engineer_id}/documents")
async def get_engineer_documents(engineer_id: str, db: AsyncSession = Depends(get_db)):
    """Get documents for an engineer"""
    try:
        engineer_uuid = uuid_lib.UUID(engineer_id)
        
        # Get certifications
        certs_result = await db.execute(
            select(Certification).where(Certification.engineer_id == engineer_uuid)
        )
        certifications = certs_result.scalars().all()
        
        documents = []
        for cert in certifications:
            documents.append({
                "id": str(cert.id),
                "name": f"{cert.certification_type} №{cert.number}",
                "type": "certification",
                "issued_by": cert.issued_by,
                "issue_date": cert.issue_date.isoformat() if cert.issue_date else None,
                "expiry_date": cert.expiry_date.isoformat() if cert.expiry_date else None,
                "file_path": cert.file_path,
            })
        
        return {"items": documents}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid engineer_id format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Document download endpoint
@app.get("/api/documents/{document_id}/download")
async def download_document(document_id: str, db: AsyncSession = Depends(get_db)):
    """Download a document"""
    try:
        doc_uuid = uuid_lib.UUID(document_id)
        
        result = await db.execute(
            select(Certification).where(Certification.id == doc_uuid)
        )
        cert = result.scalar_one_or_none()
        
        if not cert or not cert.file_path:
            raise HTTPException(status_code=404, detail="Document not found")
        
        from fastapi.responses import FileResponse
        import os
        
        file_path = Path(cert.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="File not found")
        
        return FileResponse(
            path=str(file_path),
            filename=file_path.name,
            media_type='application/pdf'
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid document_id format")
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

# User management endpoints
@app.get("/api/users")
async def get_users(
    skip: int = 0,
    limit: int = 100,
    role: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(require_permission("manage_users"))
):
    """Get list of users (admin and chief_operator only)"""
    try:
        query = select(UserModel)
        if role:
            query = query.where(UserModel.role == role)
        query = query.offset(skip).limit(limit)
        
        result = await db.execute(query)
        users = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(u.id),
                    "username": u.username,
                    "email": u.email,
                    "full_name": u.full_name,
                    "role": u.role,
                    "is_active": u.is_active,
                    "engineer_id": str(u.engineer_id) if u.engineer_id else None,
                    "created_at": u.created_at.isoformat() if u.created_at else None,
                    "last_login": u.last_login.isoformat() if u.last_login else None,
                }
                for u in users
            ],
            "total": len(users)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/users")
async def create_user(
    user_data: dict,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(require_permission("manage_users"))
):
    """Create new user (admin and chief_operator only)"""
    try:
        # Проверяем, что username и email уникальны
        existing_user = await get_user_by_username(db, user_data.get("username"))
        if existing_user:
            raise HTTPException(status_code=400, detail="Username already exists")
        
        existing_email = await get_user_by_email(db, user_data.get("email"))
        if existing_email:
            raise HTTPException(status_code=400, detail="Email already exists")
        
        new_user = UserModel(
            username=user_data.get("username"),
            email=user_data.get("email"),
            password_hash=hash_password(user_data.get("password", "changeme123")),
            full_name=user_data.get("full_name"),
            role=user_data.get("role", "engineer"),
            engineer_id=uuid_lib.UUID(user_data.get("engineer_id")) if user_data.get("engineer_id") else None,
            is_active=user_data.get("is_active", True)
        )
        db.add(new_user)
        await db.commit()
        await db.refresh(new_user)
        return {"id": str(new_user.id), "status": "created"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Equipment access management
@app.post("/api/users/{user_id}/equipment-access")
async def grant_equipment_access(
    user_id: str,
    access_data: dict,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(require_role(["admin", "chief_operator", "operator"]))
):
    """Предоставить доступ пользователю к оборудованию"""
    try:
        target_user = await get_user_by_id(db, user_id)
        if not target_user:
            raise HTTPException(status_code=404, detail="User not found")
        
        # Только оператор и выше могут предоставлять доступ
        if user.role == "operator" and target_user.role not in ["engineer"]:
            raise HTTPException(status_code=403, detail="Can only grant access to engineers")
        
        equipment_id = uuid_lib.UUID(access_data.get("equipment_id"))
        access_type = access_data.get("access_type", "read_write")
        
        # Проверяем, не существует ли уже доступ
        result = await db.execute(
            select(UserEquipmentAccess).where(
                UserEquipmentAccess.user_id == target_user.id,
                UserEquipmentAccess.equipment_id == equipment_id,
                UserEquipmentAccess.is_active == True
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            # Обновляем существующий доступ
            existing.access_type = access_type
            existing.granted_by = user.id
            existing.granted_at = datetime.utcnow()
        else:
            # Создаем новый доступ
            new_access = UserEquipmentAccess(
                user_id=target_user.id,
                equipment_id=equipment_id,
                access_type=access_type,
                granted_by=user.id
            )
            db.add(new_access)
        
        await db.commit()
        return {"status": "access_granted"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/users/{user_id}/equipment-access/{equipment_id}")
async def revoke_equipment_access(
    user_id: str,
    equipment_id: str,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(require_role(["admin", "chief_operator", "operator"]))
):
    """Отозвать доступ пользователя к оборудованию"""
    try:
        target_user = await get_user_by_id(db, user_id)
        if not target_user:
            raise HTTPException(status_code=404, detail="User not found")
        
        eq_uuid = uuid_lib.UUID(equipment_id)
        result = await db.execute(
            select(UserEquipmentAccess).where(
                UserEquipmentAccess.user_id == target_user.id,
                UserEquipmentAccess.equipment_id == eq_uuid
            )
        )
        access = result.scalar_one_or_none()
        if access:
            access.is_active = False
            await db.commit()
            return {"status": "access_revoked"}
        else:
            raise HTTPException(status_code=404, detail="Access not found")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# Questionnaire endpoints
@app.post("/api/questionnaires")
async def create_questionnaire(
    equipment_id: str = Form(...),
    equipment_inventory_number: str = Form(...),
    equipment_name: str = Form(...),
    inspection_date: str = Form(...),
    inspector_name: str = Form(...),
    inspector_position: str = Form(...),
    questionnaire_data: str = Form(...),  # JSON string
    files: List[UploadFile] = File([]),  # Множественные файлы
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """Создать опросный лист с прикрепленными фотографиями"""
    try:
        import json
        from pathlib import Path
        
        equipment_uuid = uuid_lib.UUID(equipment_id)
        
        # Проверка существования оборудования
        result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_uuid)
        )
        equipment = result.scalar_one_or_none()
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        # Парсинг JSON данных опросного листа
        try:
            questionnaire_json = json.loads(questionnaire_data)
        except json.JSONDecodeError:
            raise HTTPException(status_code=400, detail="Invalid questionnaire_data JSON")
        
        # Создаем директорию для фотографий опросных листов
        photos_dir = Path("/app/questionnaires")
        photos_dir.mkdir(exist_ok=True)
        
        # Создаем подпапку по инвентарному номеру
        inventory_dir = photos_dir / equipment_inventory_number.replace('/', '_')
        inventory_dir.mkdir(exist_ok=True)
        
        # Сохраняем файлы и обновляем пути в questionnaire_data
        saved_files = {}
        for file in files:
            if file.filename:
                # Имя файла уже содержит всю необходимую информацию в формате:
                # {инв_номер}_{название}_{код}_{timestamp}.jpg
                # Если имя файла уже в правильном формате, используем его
                # Иначе генерируем новое имя
                file_ext = Path(file.filename).suffix or '.jpg'
                
                # Проверяем, соответствует ли имя файла формату
                # Если да - используем его, если нет - генерируем новое
                if '_' in file.filename and file.filename.count('_') >= 3:
                    # Имя файла уже в правильном формате
                    file_name = file.filename
                else:
                    # Генерируем новое имя файла
                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    normalized_inv = equipment_inventory_number.replace('/', '_').replace(' ', '_').upper()
                    # Извлекаем item_id и item_name из оригинального имени или используем дефолтные
                    item_id = Path(file.filename).stem.split('_')[0] if '_' in file.filename else 'photo'
                    item_name = 'photo'
                    normalized_name = item_name.replace('/', '_').replace(' ', '_')[:30]
                    normalized_id = item_id.replace('/', '_').upper()
                    file_name = f"{normalized_inv}_{normalized_name}_{normalized_id}_{timestamp}{file_ext}"
                
                file_path_full = inventory_dir / file_name
                
                # Сохраняем файл
                with open(file_path_full, "wb") as f:
                    content = await file.read()
                    f.write(content)
                
                # Сохраняем путь к файлу
                relative_path = f"/questionnaires/{equipment_inventory_number.replace('/', '_')}/{file_name}"
                saved_files[file.filename] = relative_path
        
        # Обновляем пути к файлам в questionnaire_data
        def update_photo_paths(data, files_map):
            """Рекурсивно обновляет пути к фото в данных"""
            if isinstance(data, dict):
                for key, value in data.items():
                    if key == 'photos' and isinstance(value, list):
                        # Обновляем пути к фото
                        updated_photos = []
                        for photo in value:
                            if isinstance(photo, str) and photo in files_map:
                                updated_photos.append(files_map[photo])
                            else:
                                updated_photos.append(photo)
                        data[key] = updated_photos
                    else:
                        update_photo_paths(value, files_map)
            elif isinstance(data, list):
                for item in data:
                    update_photo_paths(item, files_map)
        
        update_photo_paths(questionnaire_json, saved_files)
        
        # Парсинг даты
        inspection_date_obj = None
        if inspection_date:
            try:
                inspection_date_obj = datetime.fromisoformat(inspection_date.replace('Z', '+00:00')).date()
            except:
                pass
        
        # Создание опросного листа
        new_questionnaire = Questionnaire(
            equipment_id=equipment_uuid,
            equipment_inventory_number=equipment_inventory_number,
            equipment_name=equipment_name,
            inspection_date=inspection_date_obj,
            inspector_name=inspector_name,
            inspector_position=inspector_position,
            questionnaire_data=questionnaire_json,
            created_by=user.id
        )
        
        db.add(new_questionnaire)
        await db.commit()
        await db.refresh(new_questionnaire)
        
        return {
            "id": str(new_questionnaire.id),
            "equipment_id": str(new_questionnaire.equipment_id),
            "equipment_inventory_number": new_questionnaire.equipment_inventory_number,
            "equipment_name": new_questionnaire.equipment_name,
            "inspection_date": new_questionnaire.inspection_date.isoformat() if new_questionnaire.inspection_date else None,
            "inspector_name": new_questionnaire.inspector_name,
            "inspector_position": new_questionnaire.inspector_position,
            "files_saved": len(saved_files),
            "status": "created"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid equipment_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to create questionnaire: {str(e)}")

@app.get("/api/questionnaires")
async def get_questionnaires(
    equipment_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """Получить список опросных листов"""
    try:
        query = select(Questionnaire)
        
        if equipment_id:
            equipment_uuid = uuid_lib.UUID(equipment_id)
            query = query.where(Questionnaire.equipment_id == equipment_uuid)
        
        query = query.offset(skip).limit(limit).order_by(Questionnaire.created_at.desc())
        
        result = await db.execute(query)
        questionnaires = result.scalars().all()
        
        return {
            "items": [
                {
                    "id": str(q.id),
                    "equipment_id": str(q.equipment_id),
                    "equipment_inventory_number": q.equipment_inventory_number,
                    "equipment_name": q.equipment_name,
                    "inspection_date": q.inspection_date.isoformat() if q.inspection_date else None,
                    "inspector_name": q.inspector_name,
                    "inspector_position": q.inspector_position,
                    "created_at": q.created_at.isoformat() if q.created_at else None,
                }
                for q in questionnaires
            ],
            "total": len(questionnaires)
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid equipment_id format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/questionnaires/{questionnaire_id}")
async def get_questionnaire(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """Получить опросный лист по ID"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        return {
            "id": str(questionnaire.id),
            "equipment_id": str(questionnaire.equipment_id),
            "equipment_inventory_number": questionnaire.equipment_inventory_number,
            "equipment_name": questionnaire.equipment_name,
            "inspection_date": questionnaire.inspection_date.isoformat() if questionnaire.inspection_date else None,
            "inspector_name": questionnaire.inspector_name,
            "inspector_position": questionnaire.inspector_position,
            "questionnaire_data": questionnaire.questionnaire_data,
            "created_at": questionnaire.created_at.isoformat() if questionnaire.created_at else None,
            "updated_at": questionnaire.updated_at.isoformat() if questionnaire.updated_at else None,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Workshops endpoints
@app.get("/api/workshops")
async def get_workshops(
    client_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """Get list of workshops"""
    try:
        query = select(Workshop).where(Workshop.is_active == 1)
        if client_id:
            try:
                client_uuid = uuid_lib.UUID(client_id)
                query = query.where(Workshop.client_id == client_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid client_id format")
        query = query.offset(skip).limit(limit)
        
        result = await db.execute(query)
        workshops = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(w.id),
                    "name": w.name,
                    "code": w.code,
                    "client_id": str(w.client_id) if w.client_id else None,
                    "location": w.location,
                    "description": w.description,
                }
                for w in workshops
            ],
            "total": len(workshops)
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/workshops")
async def create_workshop(
    workshop_data: dict,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(require_role(["admin", "chief_operator", "operator"]))
):
    """Create new workshop (only for admin, chief_operator, operator)"""
    try:
        client_id = None
        if workshop_data.get("client_id"):
            try:
                client_id = uuid_lib.UUID(workshop_data.get("client_id"))
            except:
                pass
        
        new_workshop = Workshop(
            name=workshop_data.get("name"),
            code=workshop_data.get("code"),
            client_id=client_id,
            location=workshop_data.get("location"),
            description=workshop_data.get("description"),
            is_active=1
        )
        db.add(new_workshop)
        await db.commit()
        await db.refresh(new_workshop)
        return {
            "id": str(new_workshop.id),
            "name": new_workshop.name,
            "code": new_workshop.code,
            "status": "created"
        }
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to create workshop: {str(e)}")

@app.post("/api/workshops/{workshop_id}/engineer-access")
async def grant_workshop_access(
    workshop_id: str,
    access_data: dict,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(require_role(["admin", "chief_operator", "operator"]))
):
    """Предоставить доступ инженеру к цеху"""
    try:
        workshop_uuid = uuid_lib.UUID(workshop_id)
        engineer_uuid = uuid_lib.UUID(access_data.get("engineer_id"))
        access_type = access_data.get("access_type", "read_write")
        
        # Проверяем, не существует ли уже доступ
        result = await db.execute(
            select(WorkshopEngineerAccess).where(
                WorkshopEngineerAccess.workshop_id == workshop_uuid,
                WorkshopEngineerAccess.engineer_id == engineer_uuid,
                WorkshopEngineerAccess.is_active == True
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            # Обновляем существующий доступ
            existing.access_type = access_type
            existing.granted_by = user.id
            existing.granted_at = datetime.utcnow()
        else:
            # Создаем новый доступ
            new_access = WorkshopEngineerAccess(
                workshop_id=workshop_uuid,
                engineer_id=engineer_uuid,
                access_type=access_type,
                granted_by=user.id
            )
            db.add(new_access)
        
        await db.commit()
        return {"status": "access_granted"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/workshops/{workshop_id}/engineer-access")
async def get_workshop_access(
    workshop_id: str,
    db: AsyncSession = Depends(get_db),
    user: UserModel = Depends(verify_token)
):
    """Получить список инженеров с доступом к цеху"""
    try:
        workshop_uuid = uuid_lib.UUID(workshop_id)
        result = await db.execute(
            select(WorkshopEngineerAccess).where(
                WorkshopEngineerAccess.workshop_id == workshop_uuid,
                WorkshopEngineerAccess.is_active == True
            )
        )
        accesses = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(a.id),
                    "engineer_id": str(a.engineer_id),
                    "access_type": a.access_type,
                    "granted_at": a.granted_at.isoformat() if a.granted_at else None,
                }
                for a in accesses
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
