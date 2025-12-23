from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text, or_, and_, func, Integer, cast, delete
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime, date, timedelta
import os
import uuid as uuid_lib
from database import get_db, engine, Base
from models import (
    UserEquipmentAccess,
    Equipment, EquipmentType, PipelineSegment, Inspection,
    Client, Project, EquipmentResource, RegulatoryDocument,
    Engineer, Certification, Report, Questionnaire, NDTMethod, User,
    Enterprise, Branch, Workshop, HierarchyEngineerAssignment,
    QuestionnaireDocumentFile, InspectionHistory, Assignment, RepairJournal,
    VerificationEquipment, VerificationHistory, InspectionEquipment
)
from report_generator import ReportGenerator
from auth import USERS_DB, create_access_token, verify_token, verify_token_optional, verify_password, hash_password
from pathlib import Path
from access_management import router as access_router
from hierarchy_management import router as hierarchy_router
from assignments_api import router as assignments_router
from equipment_history_api import router as equipment_history_router

app = FastAPI(
    title="ES TD NGO Platform API",
    description="API для системы учета оборудования и диагностирования",
    version="3.6.2"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # В продакшене указать конкретные домены
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(access_router)
app.include_router(hierarchy_router)
app.include_router(assignments_router)  # Новый роутер для заданий (версия 3.3.0)
app.include_router(equipment_history_router)  # Новый роутер для истории (версия 3.3.0)

# Версия мобильного приложения
MOBILE_APP_VERSION = "3.6.2"
MOBILE_APP_BUILD = "1"
MOBILE_APP_DOWNLOAD_URL = "http://5.129.203.182/mobile/es-td-ngo-mobile-3.6.2-1.apk"

# Endpoint для проверки версии мобильного приложения
@app.get("/api/mobile/version")
async def get_mobile_version():
    """Получить информацию о версии мобильного приложения"""
    return {
        "version": MOBILE_APP_VERSION,
        "build": MOBILE_APP_BUILD,
        "download_url": MOBILE_APP_DOWNLOAD_URL,
        "release_date": datetime.now().isoformat()
    }

@app.get("/api/mobile/check-update")
async def check_mobile_update(current_version: str, current_build: str):
    """Проверить наличие обновления для мобильного приложения"""
    try:
        # Парсим версию (формат: "3.6.1+1" или "3.6.1")
        current_v_parts = current_version.split('.')
        server_v_parts = MOBILE_APP_VERSION.split('.')
        
        # Сравниваем версии
        has_update = False
        for i in range(min(len(current_v_parts), len(server_v_parts))):
            current_v = int(current_v_parts[i])
            server_v = int(server_v_parts[i])
            if server_v > current_v:
                has_update = True
                break
            elif server_v < current_v:
                break
        
        # Если версии одинаковые, сравниваем build
        if not has_update and current_version == MOBILE_APP_VERSION:
            try:
                current_b = int(current_build)
                server_b = int(MOBILE_APP_BUILD)
                has_update = server_b > current_b
            except:
                pass
        
        return {
            "has_update": has_update,
            "current_version": current_version,
            "current_build": current_build,
            "latest_version": MOBILE_APP_VERSION,
            "latest_build": MOBILE_APP_BUILD,
            "download_url": MOBILE_APP_DOWNLOAD_URL if has_update else None
        }
    except Exception as e:
        return {
            "has_update": False,
            "error": str(e)
        }

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

        # Лёгкие авто-миграции (исправление расхождений схемы БД и моделей)
        # Важно: Base.metadata.create_all НЕ добавляет колонки в уже существующие таблицы.
        try:
            async with engine.begin() as conn:
                # equipment_resources.resource_type отсутствует в старых БД, но используется в предпросмотре/отчетах
                await conn.execute(
                    text(
                        "ALTER TABLE equipment_resources "
                        "ADD COLUMN IF NOT EXISTS resource_type VARCHAR(50)"
                    )
                )
            print("✅ DB migration: ensured equipment_resources.resource_type")
        except Exception as e:
            print(f"⚠️  Warning: DB migration equipment_resources.resource_type failed: {e}")
            
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
async def login(form_data: OAuth2PasswordRequestForm = Depends(), db: AsyncSession = Depends(get_db)):
    """Вход в систему"""
    # Сначала проверяем в базе данных
    result = await db.execute(select(User).where(User.username == form_data.username))
    db_user = result.scalar_one_or_none()
    
    if db_user:
        # Пользователь найден в БД
        if not db_user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="User account is disabled",
            )
        if not verify_password(form_data.password, db_user.password_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect username or password",
                headers={"WWW-Authenticate": "Bearer"},
            )
        user_role = db_user.role
    else:
        # Fallback на старый словарь USERS_DB для обратной совместимости
        user = USERS_DB.get(form_data.username)
        if not user or user["password"] != form_data.password:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect username or password",
                headers={"WWW-Authenticate": "Bearer"},
            )
        user_role = user["role"]
    
    access_token_expires = timedelta(minutes=60 * 24)
    access_token = create_access_token(
        data={"sub": form_data.username, "role": user_role},
        expires_delta=access_token_expires
    )
    
    # Для мобильного приложения возвращаем хеш пароля для офлайн-авторизации
    password_hash = None
    if db_user:
        password_hash = db_user.password_hash
    else:
        # Для fallback пользователей создаем хеш пароля
        password_hash = hash_password(form_data.password)
    
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "role": user_role,
        "password_hash": password_hash  # Для офлайн-авторизации в мобильном приложении
    }

@app.get("/api/auth/me")
async def get_current_user(username: str = Depends(verify_token), db: AsyncSession = Depends(get_db)):
    """Получить информацию о текущем пользователе"""
    # Сначала проверяем в базе данных
    result = await db.execute(select(User).where(User.username == username))
    db_user = result.scalar_one_or_none()
    
    if db_user:
        # Получаем права доступа на основе роли
        from auth import ROLE_PERMISSIONS
        permissions = ROLE_PERMISSIONS.get(db_user.role, [])
        return {
            "id": str(db_user.id),
            "username": db_user.username,
            "email": db_user.email,
            "full_name": db_user.full_name,
            "role": db_user.role,
            "permissions": permissions,
            "engineer_id": str(db_user.engineer_id) if db_user.engineer_id else None
        }
    
    # Fallback на старый словарь USERS_DB
    user = USERS_DB.get(username)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "id": None,  # Для fallback пользователей нет ID
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

# Pydantic models for request/response
class EquipmentCreate(BaseModel):
    name: str
    type_id: Optional[str] = None
    serial_number: Optional[str] = None
    location: Optional[str] = None
    workshop_id: Optional[str] = None
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
    workshop_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get list of equipment (filtered by access for engineers)"""
    try:
        # Получаем информацию о пользователе
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        # Для инженеров фильтруем по доступу (иерархия + прямое назначение)
        if user.role == "engineer":
            # Получаем назначения по иерархии
            hierarchy_result = await db.execute(
                text("""
                    SELECT 
                        enterprise_id, branch_id, workshop_id, 
                        equipment_type_id, equipment_id
                    FROM hierarchy_engineer_assignments 
                    WHERE user_id = CAST(:user_id AS uuid)
                    AND is_active = 1
                    AND (expires_at IS NULL OR expires_at > NOW())
                """),
                {"user_id": str(user.id)}
            )
            hierarchy_assignments = hierarchy_result.all()
            
            # Получаем прямое назначение оборудования
            direct_access_result = await db.execute(
                text("""
                    SELECT equipment_id 
                    FROM user_equipment_access 
                    WHERE user_id = CAST(:user_id AS uuid)
                    AND is_active = 1
                    AND (expires_at IS NULL OR expires_at > NOW())
                """),
                {"user_id": str(user.id)}
            )
            direct_equipment_ids = [row[0] for row in direct_access_result.all()]
            
            # Собираем все ID оборудования из иерархии
            accessible_equipment_ids = set(direct_equipment_ids)
            
            # Обрабатываем назначения по иерархии
            enterprise_ids = []
            branch_ids = []
            workshop_ids = []
            equipment_type_ids = []
            direct_equipment_from_hierarchy = []
            
            for assignment in hierarchy_assignments:
                if assignment[0]:  # enterprise_id
                    enterprise_ids.append(assignment[0])
                if assignment[1]:  # branch_id
                    branch_ids.append(assignment[1])
                if assignment[2]:  # workshop_id
                    workshop_ids.append(assignment[2])
                if assignment[3]:  # equipment_type_id
                    equipment_type_ids.append(assignment[3])
                if assignment[4]:  # equipment_id
                    direct_equipment_from_hierarchy.append(assignment[4])
            
            # Получаем оборудование по иерархии
            query = select(Equipment)
            conditions = []
            
            if direct_equipment_from_hierarchy:
                accessible_equipment_ids.update(direct_equipment_from_hierarchy)
            
            if workshop_ids:
                conditions.append(Equipment.workshop_id.in_(workshop_ids))
            
            if branch_ids:
                # Получаем цеха для этих филиалов
                workshop_result = await db.execute(
                    select(Workshop.id).where(Workshop.branch_id.in_(branch_ids))
                )
                workshop_ids_from_branches = [w[0] for w in workshop_result.all()]
                if workshop_ids_from_branches:
                    conditions.append(Equipment.workshop_id.in_(workshop_ids_from_branches))
            
            if enterprise_ids:
                # Получаем филиалы для этих предприятий
                branch_result = await db.execute(
                    select(Branch.id).where(Branch.enterprise_id.in_(enterprise_ids))
                )
                branch_ids_from_enterprises = [b[0] for b in branch_result.all()]
                if branch_ids_from_enterprises:
                    # Получаем цеха для этих филиалов
                    workshop_result = await db.execute(
                        select(Workshop.id).where(Workshop.branch_id.in_(branch_ids_from_enterprises))
                    )
                    workshop_ids_from_enterprises = [w[0] for w in workshop_result.all()]
                    if workshop_ids_from_enterprises:
                        conditions.append(Equipment.workshop_id.in_(workshop_ids_from_enterprises))
            
            if equipment_type_ids:
                conditions.append(Equipment.type_id.in_(equipment_type_ids))
            
            if accessible_equipment_ids:
                conditions.append(Equipment.id.in_(list(accessible_equipment_ids)))
            
            if conditions:
                query = query.where(or_(*conditions))
                result = await db.execute(query.offset(skip).limit(limit))
                equipment = result.scalars().all()
            else:
                # Если нет назначений, возвращаем пустой список
                equipment = []
        else:
            # Для admin, chief_operator, operator - полный доступ
            query = select(Equipment)
            
            # Фильтр по workshop_id, если указан
            if workshop_id:
                try:
                    workshop_uuid = uuid_lib.UUID(workshop_id)
                    query = query.where(Equipment.workshop_id == workshop_uuid)
                except ValueError:
                    raise HTTPException(status_code=400, detail="Invalid workshop_id format")
            
            # Для админов и операторов увеличиваем лимит, если не указан явно
            effective_limit = limit if limit > 100 else 10000  # Большой лимит для админов
            result = await db.execute(query.offset(skip).limit(effective_limit))
            equipment = result.scalars().all()
        
        # Обогащаем данные об оборудовании информацией об иерархии
        equipment_items = []
        for eq in equipment:
            item = {
                "id": str(eq.id),
                "equipment_code": eq.equipment_code if hasattr(eq, 'equipment_code') and eq.equipment_code else None,  # Уникальный код оборудования (версия 3.3.0)
                "name": eq.name,
                "type_id": str(eq.type_id) if eq.type_id else None,
                "serial_number": eq.serial_number,
                "location": eq.location,
                "attributes": eq.attributes or {},
                "commissioning_date": str(eq.commissioning_date) if eq.commissioning_date else None,
                "created_at": str(eq.created_at) if eq.created_at else None,
                "workshop_id": str(eq.workshop_id) if eq.workshop_id else None,
            }
            
            # Получаем информацию о цехе, филиале и предприятии
            if eq.workshop_id:
                workshop_result = await db.execute(
                    select(Workshop).where(Workshop.id == eq.workshop_id)
                )
                workshop = workshop_result.scalar_one_or_none()
                if workshop:
                    item["workshop_name"] = workshop.name
                    item["workshop_code"] = workshop.code
                    
                    # Получаем филиал
                    branch_result = await db.execute(
                        select(Branch).where(Branch.id == workshop.branch_id)
                    )
                    branch = branch_result.scalar_one_or_none()
                    if branch:
                        item["branch_id"] = str(branch.id)
                        item["branch_name"] = branch.name
                        item["branch_code"] = branch.code
                        
                        # Получаем предприятие
                        enterprise_result = await db.execute(
                            select(Enterprise).where(Enterprise.id == branch.enterprise_id)
                        )
                        enterprise = enterprise_result.scalar_one_or_none()
                        if enterprise:
                            item["enterprise_id"] = str(enterprise.id)
                            item["enterprise_name"] = enterprise.name
                            item["enterprise_code"] = enterprise.code
            
            # Получаем информацию о типе оборудования
            if eq.type_id:
                type_result = await db.execute(
                    select(EquipmentType).where(EquipmentType.id == eq.type_id)
                )
                equipment_type = type_result.scalar_one_or_none()
                if equipment_type:
                    item["type_name"] = equipment_type.name
                    item["type_code"] = equipment_type.code
            
            equipment_items.append(item)
        
        return {
            "items": equipment_items,
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
        
        # Parse workshop_id if provided
        workshop_id_uuid = None
        if equipment_data.workshop_id:
            try:
                workshop_id_uuid = uuid_lib.UUID(equipment_data.workshop_id)
            except:
                pass
        
        new_equipment = Equipment(
            name=equipment_data.name,
            type_id=type_id,
            serial_number=equipment_data.serial_number,
            location=equipment_data.location,
            workshop_id=workshop_id_uuid,
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

@app.post("/api/equipment-types")
async def create_equipment_type(
    type_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать тип оборудования"""
    try:
        # Проверяем права (только admin и chief_operator)
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        if not user or user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        new_type = EquipmentType(
            name=type_data.get("name"),
            code=type_data.get("code"),
            description=type_data.get("description")
        )
        db.add(new_type)
        await db.commit()
        await db.refresh(new_type)
        
        return {
            "id": str(new_type.id),
            "name": new_type.name,
            "code": new_type.code,
            "description": new_type.description,
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create equipment type: {str(e)}")

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
        # Фильтрация по архиву будет добавлена после миграции БД
        # Пока не фильтруем, так как поле is_archived еще не существует в БД
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

@app.patch("/api/inspections/{inspection_id}/status")
async def update_inspection_status(
    inspection_id: str,
    payload: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Изменить статус чек-листа/обследования (Inspection).
    Статусы: DRAFT, SIGNED, APPROVED
    - admin/chief_operator/operator: могут устанавливать любой из поддерживаемых статусов
    - engineer: может менять статус только своих инспекций и только на DRAFT/SIGNED
    """
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)

        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")

        new_status = (payload.get("status") or "").strip().upper()
        allowed_statuses = {"DRAFT", "SIGNED", "APPROVED"}
        if new_status not in allowed_statuses:
            raise HTTPException(status_code=400, detail="Invalid status. Allowed: DRAFT, SIGNED, APPROVED")

        # RBAC
        if current_user.role in ["admin", "chief_operator", "operator"]:
            pass
        elif current_user.role == "engineer":
            if not (inspection.inspector_id and inspection.inspector_id == current_user.id):
                raise HTTPException(status_code=403, detail="Доступ запрещен")
            if new_status not in {"DRAFT", "SIGNED"}:
                raise HTTPException(status_code=403, detail="Инженер не может утверждать (APPROVED)")
        else:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        inspection.status = new_status
        await db.commit()
        await db.refresh(inspection)

        return {"status": "ok", "id": inspection_id, "new_status": inspection.status}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to update inspection status: {str(e)}")

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
        
        # Parse project_id if provided
        project_id = None
        if inspection_data.get("project_id"):
            try:
                project_id = uuid_lib.UUID(inspection_data.get("project_id"))
            except:
                pass
        
        new_inspection = Inspection(
            equipment_id=equipment_id,
            project_id=project_id,
            data=inspection_data.get("data", {}),
            conclusion=inspection_data.get("conclusion"),
            status=inspection_data.get("status", "DRAFT"),
            date_performed=date_performed
        )
        db.add(new_inspection)
        await db.commit()
        await db.refresh(new_inspection)
        
        # Если это чек-лист сосуда (vessel checklist), создаем questionnaire
        questionnaire_id = None
        inspection_data_dict = inspection_data.get("data", {})
        if inspection_data_dict and isinstance(inspection_data_dict, dict):
            # Проверяем, есть ли данные чек-листа (documents, vessel_name и т.д.)
            if inspection_data_dict.get("documents") or inspection_data_dict.get("vessel_name"):
                # Получаем информацию об оборудовании
                eq_result = await db.execute(
                    select(Equipment).where(Equipment.id == equipment_id)
                )
                equipment = eq_result.scalar_one_or_none()
                
                # Извлекаем данные из inspection_data
                inspection_date_str = inspection_data_dict.get("inspection_date")
                inspection_date_obj = None
                if inspection_date_str:
                    try:
                        if isinstance(inspection_date_str, str):
                            inspection_date_obj = datetime.fromisoformat(inspection_date_str.replace('Z', '+00:00')).date()
                    except:
                        pass
                
                # Создаем questionnaire
                new_questionnaire = Questionnaire(
                    equipment_id=equipment_id,
                    equipment_name=equipment.name if equipment else None,
                    equipment_inventory_number=inspection_data_dict.get("equipment_inventory_number"),
                    inspection_date=inspection_date_obj or (date_performed.date() if date_performed else None),
                    inspector_name=inspection_data_dict.get("inspector_name") or inspection_data_dict.get("executors"),
                    inspector_position=inspection_data_dict.get("inspector_position"),
                    questionnaire_data=inspection_data_dict
                )
                db.add(new_questionnaire)
                await db.commit()
                await db.refresh(new_questionnaire)
                questionnaire_id = str(new_questionnaire.id)
        
        # Создаем запись в истории обследований (версия 3.3.0)
        assignment_id = None
        if inspection_data.get("assignment_id"):
            try:
                assignment_id = uuid_lib.UUID(inspection_data.get("assignment_id"))
            except:
                pass
        
        # Определяем тип обследования
        inspection_type = "VISUAL"
        if inspection_data_dict:
            if inspection_data_dict.get("documents") or inspection_data_dict.get("vessel_name"):
                inspection_type = "QUESTIONNAIRE"
            elif inspection_data_dict.get("ndt_methods") or inspection_data_dict.get("method_code"):
                inspection_type = "NDT"
        
        # Получаем ID инженера из данных или из токена
        inspector_id = None
        if inspection_data_dict.get("inspector_id"):
            try:
                inspector_id = uuid_lib.UUID(inspection_data_dict.get("inspector_id"))
            except:
                pass
        
        # Создаем запись в истории
        history_entry = InspectionHistory(
            equipment_id=equipment_id,
            assignment_id=assignment_id,
            inspection_type=inspection_type,
            inspector_id=inspector_id,
            inspection_date=date_performed or datetime.now(),
            data=inspection_data.get("data", {}),
            conclusion=inspection_data.get("conclusion"),
            status=inspection_data.get("status", "DRAFT")
        )
        db.add(history_entry)
        await db.commit()
        await db.refresh(history_entry)

        # Обновляем статус задания (чтобы у инженера отмечалось выполнено/не выполнено)
        if assignment_id:
            try:
                assignment_result = await db.execute(
                    select(Assignment).where(Assignment.id == assignment_id)
                )
                assignment = assignment_result.scalar_one_or_none()
                if assignment:
                    insp_status = (inspection_data.get("status") or "DRAFT").upper()
                    if insp_status == "SIGNED":
                        assignment.status = "COMPLETED"
                        assignment.completed_at = datetime.now()
                    elif insp_status == "DRAFT":
                        # Черновик — это "в работе"
                        if assignment.status not in ["COMPLETED", "CANCELLED"]:
                            assignment.status = "IN_PROGRESS"
                    else:
                        # Прочие статусы не меняем, чтобы не ломать логику
                        pass
                    await db.commit()
            except Exception:
                # Не блокируем создание инспекции из-за статуса задания
                await db.rollback()
        
        return {
            "id": str(new_inspection.id),
            "equipment_id": str(new_inspection.equipment_id),
            "questionnaire_id": questionnaire_id,
            "history_id": str(history_entry.id),  # ID записи в истории (версия 3.3.0)
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


@app.delete("/api/inspections/{inspection_id}")
async def delete_inspection(
    inspection_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Удаление чек-листа (inspection).
    - admin/chief_operator/operator: удаляют любые
    - engineer: удаляет только свои (по inspector_id)
    При удалении также удаляются связанные отчеты (reports) и методы НК (ndt_methods) по inspection_id.
    """
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)

        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")

        # Права
        allowed = False
        if current_user.role in ["admin", "chief_operator", "operator"]:
            allowed = True
        elif current_user.role == "engineer":
            if inspection.inspector_id and inspection.inspector_id == current_user.id:
                allowed = True
        if not allowed:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        # Удаляем связанные отчеты и их файлы
        rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
        related_reports = rep_result.scalars().all()
        for report in related_reports:
            for p in [report.file_path, getattr(report, "word_file_path", None)]:
                if p:
                    try:
                        fp = Path(p)
                        if fp.exists():
                            fp.unlink()
                    except Exception:
                        pass
            await db.delete(report)

        # Удаляем связанные методы НК (новая схема привязки к inspection_id)
        try:
            ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
            for m in ndt_result.scalars().all():
                await db.delete(m)
        except Exception:
            pass

        await db.delete(inspection)
        await db.commit()
        return {"status": "deleted", "id": inspection_id, "reports_deleted": len(related_reports)}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete inspection: {str(e)}")


@app.delete("/api/inspections/cleanup")
async def cleanup_inspections(
    older_than_days: int = 180,
    before: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Массовое удаление старых чек-листов (inspections) и связанных отчетов/методов НК.
    - admin/chief_operator/operator: удаляют любые
    - engineer: удаляет только свои
    """
    try:
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        cutoff = None
        if before:
            try:
                cutoff = datetime.fromisoformat(before.replace("Z", "+00:00"))
            except Exception:
                try:
                    cutoff = datetime.strptime(before, "%Y-%m-%d")
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid 'before' format")
        else:
            if older_than_days < 1:
                raise HTTPException(status_code=400, detail="older_than_days must be >= 1")
            cutoff = datetime.now() - timedelta(days=int(older_than_days))

        insp_query = select(Inspection).where(Inspection.created_at < cutoff)
        if current_user.role == "engineer":
            insp_query = insp_query.where(Inspection.inspector_id == current_user.id)
        elif current_user.role not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        insp_result = await db.execute(insp_query)
        inspections = insp_result.scalars().all()

        deleted = 0
        reports_deleted = 0
        for inspection in inspections:
            # связанные отчеты
            rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
            related_reports = rep_result.scalars().all()
            for report in related_reports:
                for p in [report.file_path, getattr(report, "word_file_path", None)]:
                    if p:
                        try:
                            fp = Path(p)
                            if fp.exists():
                                fp.unlink()
                        except Exception:
                            pass
                await db.delete(report)
                reports_deleted += 1

            # методы НК
            try:
                ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
                for m in ndt_result.scalars().all():
                    await db.delete(m)
            except Exception:
                pass

            await db.delete(inspection)
            deleted += 1

        await db.commit()
        return {"status": "ok", "deleted": deleted, "reports_deleted": reports_deleted, "cutoff": cutoff.isoformat()}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to cleanup inspections: {str(e)}")

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
async def get_engineers(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get list of engineers"""
    try:
        result = await db.execute(
            select(Engineer).where(Engineer.is_active == 1)
        )
        engineers = result.scalars().all()
        items = []
        for e in engineers:
            try:
                items.append({
                    "id": str(e.id),
                    "full_name": e.full_name or "",
                    "position": e.position or "",
                    "email": e.email or "",
                    "phone": e.phone or "",
                    "qualifications": e.qualifications if e.qualifications is not None else [],
                    "equipment_types": e.equipment_types if e.equipment_types is not None else [],
                })
            except Exception as item_error:
                import traceback
                print(f"Error processing engineer {e.id}: {item_error}")
                traceback.print_exc()
                continue
        
        return {"items": items}
    except Exception as e:
        import traceback
        print(f"Error in get_engineers: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/users")
async def get_users(
    role: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список пользователей"""
    try:
        # Проверяем права доступа (только admin и chief_operator)
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        # Теперь is_active имеет тип INTEGER, можно использовать прямое сравнение
        query = select(User).where(User.is_active == 1)
        if role:
            query = query.where(User.role == role)
        
        result = await db.execute(query.order_by(User.username))
        users = result.scalars().all()
        
        return {
            "items": [
                {
                    "id": str(u.id),
                    "username": u.username,
                    "email": u.email,
                    "full_name": u.full_name,
                    "role": u.role,
                    "engineer_id": str(u.engineer_id) if u.engineer_id else None,
                }
                for u in users
            ]
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get users: {str(e)}")

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
    username: str = Depends(verify_token),
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
        items = []
        for c in certs:
            try:
                items.append({
                    "id": str(c.id),
                    "engineer_id": str(c.engineer_id) if c.engineer_id else None,
                    "certification_type": c.certification_type or "",
                    "certificate_number": c.certificate_number or "",
                    "number": c.certificate_number or "",  # Для обратной совместимости
                    "issued_by": c.issuing_organization or "",
                    "issuing_organization": c.issuing_organization or "",
                    "issue_date": str(c.issue_date) if c.issue_date else None,
                    "expiry_date": str(c.expiry_date) if c.expiry_date else None,
                    "document_number": c.document_number or None,
                    "document_date": str(c.document_date) if c.document_date else None,
                    "scan_file_name": getattr(c, "scan_file_name", None),
                    "scan_file_size": getattr(c, "scan_file_size", None),
                    "scan_mime_type": getattr(c, "scan_mime_type", None),
                })
            except Exception as item_error:
                import traceback
                print(f"Error processing certification {c.id if c else 'unknown'}: {item_error}")
                traceback.print_exc()
                continue
        
        return {"items": items}
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/certifications")
async def create_certification(
    certification_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать сертификат"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        engineer_id = uuid_lib.UUID(certification_data.get("engineer_id"))
        
        certification = Certification(
            engineer_id=engineer_id,
            certification_type=certification_data.get("certification_type"),
            certificate_number=certification_data.get("certificate_number"),
            issue_date=datetime.strptime(certification_data.get("issue_date"), "%Y-%m-%d").date() if certification_data.get("issue_date") else None,
            expiry_date=datetime.strptime(certification_data.get("expiry_date"), "%Y-%m-%d").date() if certification_data.get("expiry_date") else None,
            issuing_organization=certification_data.get("issuing_organization"),
            document_number=certification_data.get("document_number"),
            document_date=datetime.strptime(certification_data.get("document_date"), "%Y-%m-%d").date() if certification_data.get("document_date") else None,
            is_active=1
        )
        
        db.add(certification)
        await db.commit()
        await db.refresh(certification)
        
        return {
            "id": str(certification.id),
            "engineer_id": str(certification.engineer_id),
            "certification_type": certification.certification_type,
            "certificate_number": certification.certificate_number,
            "issue_date": str(certification.issue_date) if certification.issue_date else None,
            "expiry_date": str(certification.expiry_date) if certification.expiry_date else None,
            "issuing_organization": certification.issuing_organization,
            "document_number": certification.document_number,
            "document_date": str(certification.document_date) if certification.document_date else None,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid date format: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create certification: {str(e)}")

@app.put("/api/certifications/{certification_id}")
async def update_certification(
    certification_id: str,
    certification_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Обновить сертификат"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(
            select(Certification).where(Certification.id == cert_uuid)
        )
        certification = result.scalar_one_or_none()
        
        if not certification:
            raise HTTPException(status_code=404, detail="Сертификат не найден")
        
        if "certification_type" in certification_data:
            certification.certification_type = certification_data["certification_type"]
        if "certificate_number" in certification_data:
            certification.certificate_number = certification_data["certificate_number"]
        if "issue_date" in certification_data:
            certification.issue_date = datetime.strptime(certification_data["issue_date"], "%Y-%m-%d").date() if certification_data["issue_date"] else None
        if "expiry_date" in certification_data:
            certification.expiry_date = datetime.strptime(certification_data["expiry_date"], "%Y-%m-%d").date() if certification_data["expiry_date"] else None
        if "issuing_organization" in certification_data:
            certification.issuing_organization = certification_data["issuing_organization"]
        if "document_number" in certification_data:
            certification.document_number = certification_data["document_number"]
        if "document_date" in certification_data:
            certification.document_date = datetime.strptime(certification_data["document_date"], "%Y-%m-%d").date() if certification_data["document_date"] else None
        
        await db.commit()
        await db.refresh(certification)
        
        return {
            "id": str(certification.id),
            "engineer_id": str(certification.engineer_id),
            "certification_type": certification.certification_type,
            "certificate_number": certification.certificate_number,
            "issue_date": str(certification.issue_date) if certification.issue_date else None,
            "expiry_date": str(certification.expiry_date) if certification.expiry_date else None,
            "issuing_organization": certification.issuing_organization,
            "document_number": certification.document_number,
            "document_date": str(certification.document_date) if certification.document_date else None,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid date format: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to update certification: {str(e)}")

@app.delete("/api/certifications/{certification_id}")
async def delete_certification(
    certification_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить сертификат (мягкое удаление)"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(
            select(Certification).where(Certification.id == cert_uuid)
        )
        certification = result.scalar_one_or_none()
        
        if not certification:
            raise HTTPException(status_code=404, detail="Сертификат не найден")
        
        certification.is_active = 0
        await db.commit()
        
        return {"message": "Сертификат успешно удален"}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete certification: {str(e)}")


@app.post("/api/certifications/{certification_id}/scan")
async def upload_certification_scan(
    certification_id: str,
    file: UploadFile = File(...),
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Загрузить скан сертификата (фото/PDF)"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(select(Certification).where(Certification.id == cert_uuid))
        cert = result.scalar_one_or_none()
        if not cert:
            raise HTTPException(status_code=404, detail="Сертификат не найден")

        allowed = {
            "application/pdf",
            "image/jpeg",
            "image/png",
            "image/webp",
        }
        if file.content_type and file.content_type not in allowed:
            raise HTTPException(status_code=400, detail="Разрешены только фото (JPEG/PNG/WEBP) или PDF")

        uploads_dir = Path("/app/uploads/certification_scans") / str(cert.id)
        uploads_dir.mkdir(parents=True, exist_ok=True)

        safe_name = (file.filename or "scan").replace("\\", "_").replace("/", "_")
        stored_name = f"{uuid_lib.uuid4()}_{safe_name}"
        stored_path = uploads_dir / stored_name

        # Удаляем старый файл, если был
        old_path = getattr(cert, "scan_file_path", None)
        if old_path:
            try:
                old_p = Path(old_path)
                if old_p.exists():
                    old_p.unlink()
            except Exception:
                pass

        size = 0
        with stored_path.open("wb") as f:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                f.write(chunk)

        cert.scan_file_path = str(stored_path)
        cert.scan_file_name = file.filename
        cert.scan_file_size = size
        cert.scan_mime_type = file.content_type

        await db.commit()
        await db.refresh(cert)

        return {
            "id": str(cert.id),
            "scan_file_name": cert.scan_file_name,
            "scan_file_size": cert.scan_file_size,
            "scan_mime_type": cert.scan_mime_type,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid certification_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to upload scan: {str(e)}")


@app.get("/api/certifications/{certification_id}/scan")
async def download_certification_scan(
    certification_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Скачать скан сертификата"""
    try:
        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(select(Certification).where(Certification.id == cert_uuid))
        cert = result.scalar_one_or_none()
        if not cert:
            raise HTTPException(status_code=404, detail="Сертификат не найден")

        scan_path = getattr(cert, "scan_file_path", None)
        if not scan_path or not Path(scan_path).exists():
            raise HTTPException(status_code=404, detail="Скан не найден")

        return FileResponse(
            path=scan_path,
            filename=(getattr(cert, "scan_file_name", None) or "certificate-scan"),
            media_type=(getattr(cert, "scan_mime_type", None) or "application/octet-stream"),
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid certification_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to download scan: {str(e)}")


@app.delete("/api/certifications/{certification_id}/scan")
async def delete_certification_scan(
    certification_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить скан сертификата"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        cert_uuid = uuid_lib.UUID(certification_id)
        result = await db.execute(select(Certification).where(Certification.id == cert_uuid))
        cert = result.scalar_one_or_none()
        if not cert:
            raise HTTPException(status_code=404, detail="Сертификат не найден")

        scan_path = getattr(cert, "scan_file_path", None)
        if scan_path:
            try:
                p = Path(scan_path)
                if p.exists():
                    p.unlink()
            except Exception:
                pass

        cert.scan_file_path = None
        cert.scan_file_name = None
        cert.scan_file_size = None
        cert.scan_mime_type = None
        await db.commit()

        return {"message": "Скан удален"}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid certification_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete scan: {str(e)}")

# Reports endpoints
@app.get("/api/reports")
async def get_reports(
    inspection_id: Optional[str] = None,
    equipment_id: Optional[str] = None,
    project_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Get reports (с учетом прав: инженер видит только свои отчеты)"""
    try:
        # Текущий пользователь и роль
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        query = select(Report)
        # Фильтрация по архиву будет добавлена после миграции БД
        # Пока не фильтруем, так как поле is_archived еще не существует в БД
        if inspection_id:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                query = query.where(Report.inspection_id == insp_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid inspection_id format")
        # Фильтрация по equipment_id и project_id через связанные инспекции
        if equipment_id:
            try:
                eq_uuid = uuid_lib.UUID(equipment_id)
                # Фильтруем через связанные инспекции
                insp_subquery = select(Inspection.id).where(Inspection.equipment_id == eq_uuid)
                query = query.where(Report.inspection_id.in_(insp_subquery))
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        if project_id:
            try:
                proj_uuid = uuid_lib.UUID(project_id)
                # Фильтруем через связанные инспекции
                insp_subquery = select(Inspection.id).where(Inspection.project_id == proj_uuid)
                query = query.where(Report.inspection_id.in_(insp_subquery))
            except:
                raise HTTPException(status_code=400, detail="Invalid project_id format")

        # Ограничиваем инженера только своими отчетами.
        # created_by хранится как UUID (users.id). Фолбэк для старых записей: если created_by пустой,
        # пытаемся определить по inspection.inspector_id.
        if current_user.role == "engineer":
            query = (
                query.join(Inspection, Report.inspection_id == Inspection.id, isouter=True)
                .where(
                    or_(
                        Report.created_by == current_user.id,
                        and_(Report.created_by.is_(None), Inspection.inspector_id == current_user.id),
                    )
                )
            )
        
        result = await db.execute(query.order_by(Report.created_at.desc()))
        reports = result.scalars().all()
        
        # Получаем информацию об инженерах из связанных инспекций
        report_items = []
        for r in reports:
            inspector_name = None
            inspector_position = None
            equipment_id = None
            project_id = None
            inspection = None
            
            # Пытаемся получить ФИО инженера из связанной инспекции
            if r.inspection_id:
                insp_result = await db.execute(
                    select(Inspection).where(Inspection.id == r.inspection_id)
                )
                inspection = insp_result.scalar_one_or_none()
                if inspection:
                    # Получаем equipment_id и project_id из инспекции
                    equipment_id = str(inspection.equipment_id) if inspection.equipment_id else None
                    project_id = str(inspection.project_id) if inspection.project_id else None
                    
                    if inspection.inspector_id:
                        # Получаем информацию об инженере из users
                        user_result = await db.execute(
                            select(User).where(User.id == inspection.inspector_id)
                        )
                        user = user_result.scalar_one_or_none()
                        if user:
                            inspector_name = user.full_name or user.username
                            # Пытаемся получить должность из связанного engineer
                            if user.engineer_id:
                                eng_result = await db.execute(
                                    select(Engineer).where(Engineer.id == user.engineer_id)
                                )
                                engineer = eng_result.scalar_one_or_none()
                                if engineer:
                                    inspector_position = engineer.position
            
            report_items.append({
                "id": str(r.id),
                "inspection_id": str(r.inspection_id) if r.inspection_id else None,
                "equipment_id": equipment_id,
                "project_id": project_id,
                "report_type": r.report_type,
                "title": f"{r.report_type} Report" if r.report_type else "Report",
                "file_path": r.file_path,
                "file_size": r.file_size,
                # Статус отчета берём из статуса инспекции, если она есть (DRAFT/SIGNED/APPROVED).
                # Фолбэк: если инспекции нет, считаем что файл -> GENERATED иначе DRAFT.
                "status": (inspection.status if inspection and getattr(inspection, "status", None) else ("GENERATED" if r.file_path else "DRAFT")),
                "inspector_name": inspector_name,
                "inspector_position": inspector_position,
                "created_by": str(r.created_by) if r.created_by else None,
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "word_file_path": getattr(r, "word_file_path", None),
                "word_file_size": getattr(r, "word_file_size", None),
            })
        
        return {
            "items": report_items
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/inspections/{inspection_id}/preview")
async def get_inspection_preview(inspection_id: str, db: AsyncSession = Depends(get_db)):
    """Получить данные инспекции для предпросмотра перед генерацией отчета"""
    try:
        inspection_uuid = uuid_lib.UUID(inspection_id)
        
        # Получаем данные инспекции
        result = await db.execute(
            select(Inspection).where(Inspection.id == inspection_uuid)
        )
        inspection = result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")
        
        # Получаем данные оборудования
        eq_result = await db.execute(
            select(Equipment).where(Equipment.id == inspection.equipment_id)
        )
        equipment = eq_result.scalar_one_or_none()
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        # Получаем методы НК через questionnaire_id
        # Сначала находим questionnaire для этого inspection
        questionnaire_result = await db.execute(
            select(Questionnaire).where(Questionnaire.equipment_id == equipment.id)
            .order_by(Questionnaire.created_at.desc())
        )
        questionnaire = questionnaire_result.scalar_one_or_none()
        
        ndt_methods = []
        if questionnaire:
            ndt_result = await db.execute(
                select(NDTMethod).where(NDTMethod.questionnaire_id == questionnaire.id)
            )
            ndt_methods = ndt_result.scalars().all()
        
        # Получаем данные ресурса, если есть
        resource_data = None
        res_result = await db.execute(
            select(EquipmentResource).where(EquipmentResource.equipment_id == equipment.id)
            .order_by(EquipmentResource.created_at.desc())
        )
        resource = res_result.scalar_one_or_none()
        if resource:
            # Используем поля, которые есть в модели EquipmentResource
            resource_data = {
                "resource_type": resource.resource_type,
                "current_value": float(resource.current_value) if resource.current_value else None,
                "limit_value": float(resource.limit_value) if resource.limit_value else None,
                "unit": resource.unit,
                "last_updated": resource.last_updated.isoformat() if resource.last_updated else None,
            }
        
        return {
            "inspection": {
                "id": str(inspection.id),
                "date_performed": inspection.date_performed.isoformat() if inspection.date_performed else None,
                "status": inspection.status,
                "conclusion": inspection.conclusion,
                "data": inspection.data,
            },
            "equipment": {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
                "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
                "attributes": equipment.attributes or {},
            },
            "questionnaire": {
                "id": str(questionnaire.id) if questionnaire else None,
            },
            "ndt_methods": [
                {
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                }
                for m in ndt_methods
            ],
            "resource": resource_data,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to get preview: {str(e)}")


@app.get("/api/inspections/{inspection_id}/questionnaire")
async def get_inspection_questionnaire_info(
    inspection_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """
    Получить привязанный к инспекции опросный лист (questionnaire_id) и файлы документов.
    Нужен для корректного отображения названий и вложений документов в веб-интерфейсе.
    """
    try:
        inspection_uuid = uuid_lib.UUID(inspection_id)

        ins_result = await db.execute(select(Inspection).where(Inspection.id == inspection_uuid))
        inspection = ins_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")

        # Ищем наиболее подходящий questionnaire для этой инспекции:
        # 1) по equipment_id
        # 2) по ближайшему created_at (если есть) иначе последний
        q_query = select(Questionnaire).where(Questionnaire.equipment_id == inspection.equipment_id)
        if getattr(inspection, "created_at", None):
            q_query = q_query.order_by(
                func.abs(func.extract("epoch", Questionnaire.created_at - inspection.created_at))
            )
        else:
            q_query = q_query.order_by(Questionnaire.created_at.desc())

        q_result = await db.execute(q_query)
        questionnaire = q_result.scalar_one_or_none()

        if not questionnaire:
            return {"questionnaire_id": None, "document_files": []}

        files_result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == questionnaire.id
            )
        )
        files = files_result.scalars().all()

        return {
            "questionnaire_id": str(questionnaire.id),
            "document_files": [
                {
                    "id": str(f.id),
                    "document_number": f.document_number,
                    "file_name": f.file_name,
                    "file_size": int(f.file_size or 0),
                    "file_type": f.file_type,
                    "mime_type": f.mime_type,
                    "created_at": f.created_at.isoformat() if f.created_at else None,
                }
                for f in files
            ],
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Failed to get inspection questionnaire info: {str(e)}")

@app.post("/api/reports/generate")
async def generate_report(
    report_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Generate technical report or expertise"""
    try:
        # Текущий пользователь
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

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
                    # Используем поля, которые есть в модели EquipmentResource
                    resource_data = {
                        "resource_type": resource.resource_type,
                        "current_value": float(resource.current_value) if resource.current_value else None,
                        "limit_value": float(resource.limit_value) if resource.limit_value else None,
                        "unit": resource.unit,
                        "last_updated": resource.last_updated.isoformat() if resource.last_updated else None,
                    }
            
            # Методы НК:
            # 1) Сначала пытаемся взять методы, привязанные напрямую к inspection_id (3.3.0+)
            # 2) Фолбэк: методы, привязанные к последнему questionnaire по этому оборудованию (историческая логика)
            ndt_methods = []
            try:
                ndt_result = await db.execute(
                    select(NDTMethod).where(NDTMethod.inspection_id == inspection.id)
                )
                ndt_methods = ndt_result.scalars().all()
            except Exception:
                ndt_methods = []

            if not ndt_methods:
                questionnaire_result = await db.execute(
                    select(Questionnaire).where(Questionnaire.equipment_id == equipment.id)
                    .order_by(Questionnaire.created_at.desc())
                )
                questionnaire = questionnaire_result.scalar_one_or_none()

                if questionnaire:
                    ndt_result = await db.execute(
                        select(NDTMethod).where(NDTMethod.questionnaire_id == questionnaire.id)
                    )
                    ndt_methods = ndt_result.scalars().all()

            # Вложения чек-листа (фото таблички/схема контроля/сканы документов) — привязаны к Questionnaire
            document_files = []
            try:
                q_query = select(Questionnaire).where(Questionnaire.equipment_id == equipment.id)
                if getattr(inspection, "created_at", None):
                    q_query = q_query.order_by(
                        func.abs(func.extract("epoch", Questionnaire.created_at - inspection.created_at))
                    )
                else:
                    q_query = q_query.order_by(Questionnaire.created_at.desc())

                q_result = await db.execute(q_query)
                q_for_files = q_result.scalar_one_or_none()
                if q_for_files:
                    files_result = await db.execute(
                        select(QuestionnaireDocumentFile).where(
                            QuestionnaireDocumentFile.questionnaire_id == q_for_files.id
                        )
                    )
                    files = files_result.scalars().all()
                    document_files = [
                        {
                            "document_number": f.document_number,
                            "file_name": f.file_name,
                            "file_path": f.file_path,
                            "file_size": int(f.file_size or 0),
                            "file_type": f.file_type,
                            "mime_type": f.mime_type,
                        }
                        for f in files
                    ]
            except Exception:
                document_files = []
            
            # Получаем используемое оборудование для поверок
            verification_equipment_list = []
            try:
                # Ищем по inspection_id
                inspection_eq_result = await db.execute(
                    select(InspectionEquipment).where(InspectionEquipment.inspection_id == inspection.id)
                )
                inspection_equipment = inspection_eq_result.scalars().all()
                
                for ie in inspection_equipment:
                    ver_eq_result = await db.execute(
                        select(VerificationEquipment).where(VerificationEquipment.id == ie.verification_equipment_id)
                    )
                    ver_eq = ver_eq_result.scalar_one_or_none()
                    if ver_eq:
                        verification_equipment_list.append({
                            "id": str(ver_eq.id),
                            "name": ver_eq.name,
                            "equipment_type": ver_eq.equipment_type,
                            "serial_number": ver_eq.serial_number,
                            "manufacturer": ver_eq.manufacturer,
                            "model": ver_eq.model,
                            "verification_date": ver_eq.verification_date.isoformat() if ver_eq.verification_date else None,
                            "next_verification_date": ver_eq.next_verification_date.isoformat() if ver_eq.next_verification_date else None,
                            "verification_certificate_number": ver_eq.verification_certificate_number,
                            "verification_organization": ver_eq.verification_organization,
                            "scan_file_path": ver_eq.scan_file_path,
                            "scan_file_name": ver_eq.scan_file_name,
                        })
            except Exception as e:
                print(f"Warning: Could not load verification equipment: {e}")
                verification_equipment_list = []
            
            # Generate report
            reports_dir = Path("/app/reports")
            reports_dir.mkdir(exist_ok=True)
            
            report_type = report_data.get("report_type", "TECHNICAL_REPORT")
            # pdf или docx (поддерживаем также WORD/DOC)
            output_format = (report_data.get("format") or "pdf").strip().lower()
            is_docx = output_format in ["docx", "doc", "word"]
            
            if is_docx:
                # Генерация Word документа
                from word_generator import WordGenerator
                word_generator = WordGenerator()
                filename = f"{report_type}_{inspection.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.docx"
                file_path = reports_dir / filename
            else:
                # Генерация PDF
                generator = ReportGenerator()
                filename = f"{report_type}_{inspection.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
                file_path = reports_dir / filename
            
            # Проверяем, что ndt_methods не None и является списком
            if ndt_methods is None:
                ndt_methods = []
            
            ndt_methods_data = [
                {
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                    "photos": m.photos or [],
                    "additional_data": m.additional_data or {},
                    "performed_date": m.performed_date.isoformat() if m.performed_date else None,
                }
                for m in ndt_methods
            ]

            # Приложения: документы специалистов (удостоверения/сертификаты НК) по ФИО из методов НК
            specialist_docs = []
            try:
                inspector_names = sorted(
                    {str(m.get("inspector_name")).strip() for m in ndt_methods_data if m.get("inspector_name")},
                    key=lambda s: s.lower(),
                )
                for name in inspector_names:
                    # ищем пользователя по full_name или username
                    ures = await db.execute(
                        select(User).where(or_(User.full_name == name, User.username == name))
                    )
                    u = ures.scalar_one_or_none()
                    if not u or not getattr(u, "engineer_id", None):
                        continue
                    certs_res = await db.execute(
                        select(Certification).where(
                            Certification.engineer_id == u.engineer_id,
                            Certification.scan_file_path.is_not(None),
                        )
                    )
                    certs = certs_res.scalars().all()
                    items = []
                    for c in certs:
                        sp = getattr(c, "scan_file_path", None)
                        if not sp:
                            continue
                        items.append(
                            {
                                "certification_type": getattr(c, "certification_type", None),
                                "certificate_number": getattr(c, "certificate_number", None),
                                "issuing_organization": getattr(c, "issuing_organization", None),
                                "issue_date": str(getattr(c, "issue_date", None)) if getattr(c, "issue_date", None) else None,
                                "expiry_date": str(getattr(c, "expiry_date", None)) if getattr(c, "expiry_date", None) else None,
                                "scan_file_path": sp,
                                "scan_file_name": getattr(c, "scan_file_name", None),
                                "scan_mime_type": getattr(c, "scan_mime_type", None),
                            }
                        )
                    if items:
                        specialist_docs.append({"inspector_name": name, "certifications": items})
            except Exception:
                specialist_docs = []
            
            if is_docx:
                # Генерация Word документа
                word_generator.generate_report_word(
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
                    ndt_methods_data,
                    str(file_path),
                    report_type,
                    document_files=document_files,
                    specialist_docs=specialist_docs,
                    verification_equipment=verification_equipment_list,
                )
            else:
                # Генерация PDF
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
                        str(file_path),
                        ndt_methods_data,
                        document_files=document_files,
                        specialist_docs=specialist_docs,
                        verification_equipment=verification_equipment_list,
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
                        str(file_path),
                        ndt_methods_data,
                        document_files=document_files,
                        specialist_docs=specialist_docs,
                        verification_equipment=verification_equipment_list,
                    )
            
            # Save report record
            new_report = Report(
                inspection_id=inspection_id,
                report_type=report_type,
                file_path=str(file_path),
                file_size=file_path.stat().st_size if file_path.exists() else 0,
                created_by=current_user.id,
            )
            # Для DOCX также заполняем word_* поля (для единообразия и будущего расширения)
            if is_docx:
                new_report.word_file_path = str(file_path)
                new_report.word_file_size = new_report.file_size
            db.add(new_report)
            await db.commit()
            await db.refresh(new_report)
            
            return {
                "id": str(new_report.id),
                "file_path": str(file_path),
                "file_size": new_report.file_size,
                "format": "docx" if is_docx else "pdf",
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


@app.delete("/api/reports/{report_id}")
async def delete_report(
    report_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удаление отчета (admin/operator — любой, engineer — только свой)"""
    try:
        report_uuid = uuid_lib.UUID(report_id)

        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        rep_result = await db.execute(select(Report).where(Report.id == report_uuid))
        report = rep_result.scalar_one_or_none()
        if not report:
            raise HTTPException(status_code=404, detail="Report not found")

        # Проверка прав
        if current_user.role in ["admin", "chief_operator", "operator"]:
            allowed = True
        elif current_user.role == "engineer":
            allowed = False
            if report.created_by and report.created_by == current_user.id:
                allowed = True
            elif report.created_by is None and report.inspection_id:
                insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                insp = insp_result.scalar_one_or_none()
                if insp and insp.inspector_id == current_user.id:
                    allowed = True
        else:
            allowed = False

        if not allowed:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        # Удаляем файлы
        for p in [report.file_path, getattr(report, "word_file_path", None)]:
            if p:
                try:
                    fp = Path(p)
                    if fp.exists():
                        fp.unlink()
                except Exception:
                    pass

        await db.delete(report)
        await db.commit()
        return {"status": "deleted", "id": report_id}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid report_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete report: {str(e)}")

class BulkDeleteInspectionsRequest(BaseModel):
    inspection_ids: List[str]

@app.post("/api/inspections/bulk-delete")
async def bulk_delete_inspections(
    request: BulkDeleteInspectionsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое удаление чек-листов"""
    try:
        inspection_ids = request.inspection_ids
        if not inspection_ids:
            raise HTTPException(status_code=400, detail="No inspection IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        deleted_count = 0
        for inspection_id in inspection_ids:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
                inspection = insp_result.scalar_one_or_none()
                
                if not inspection:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if inspection.inspector_id and inspection.inspector_id == user.id:
                        allowed = True
                
                if not allowed:
                    continue
                
                # Удаляем связанные отчеты и их файлы
                rep_result = await db.execute(select(Report).where(Report.inspection_id == inspection.id))
                related_reports = rep_result.scalars().all()
                for report in related_reports:
                    for p in [report.file_path, getattr(report, "word_file_path", None)]:
                        if p:
                            try:
                                fp = Path(p)
                                if fp.exists():
                                    fp.unlink()
                            except Exception:
                                pass
                    await db.delete(report)
                
                # Удаляем связанные методы НК
                try:
                    ndt_result = await db.execute(select(NDTMethod).where(NDTMethod.inspection_id == inspection.id))
                    for m in ndt_result.scalars().all():
                        await db.delete(m)
                except Exception:
                    pass
                
                # Удаляем связанное оборудование для поверок
                try:
                    eq_result = await db.execute(select(InspectionEquipment).where(InspectionEquipment.inspection_id == inspection.id))
                    for eq in eq_result.scalars().all():
                        await db.delete(eq)
                except Exception:
                    pass
                
                # Теперь можно безопасно удалить сам чек-лист
                await db.delete(inspection)
                deleted_count += 1
            except Exception as e:
                # Логируем ошибку для отладки, но продолжаем обработку других записей
                print(f"⚠️ Error deleting inspection {inspection_id}: {str(e)}")
                continue
        
        await db.commit()
        return {"deleted": deleted_count, "total": len(inspection_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete inspections: {str(e)}")

class BulkArchiveRequest(BaseModel):
    inspection_ids: List[str]
    archive: bool = True

@app.post("/api/inspections/bulk-archive")
async def bulk_archive_inspections(
    request: BulkArchiveRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое архивирование/разархивирование чек-листов"""
    try:
        inspection_ids = request.inspection_ids
        archive = request.archive
        if not inspection_ids:
            raise HTTPException(status_code=400, detail="No inspection IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        archived_count = 0
        for inspection_id in inspection_ids:
            try:
                insp_uuid = uuid_lib.UUID(inspection_id)
                insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
                inspection = insp_result.scalar_one_or_none()
                
                if not inspection:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if inspection.inspector_id and inspection.inspector_id == user.id:
                        allowed = True
                
                if not allowed:
                    continue
                
                inspection.is_archived = archive
                archived_count += 1
            except Exception as e:
                continue
        
        await db.commit()
        return {"archived": archived_count, "total": len(inspection_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to archive inspections: {str(e)}")

class BulkDeleteReportsRequest(BaseModel):
    report_ids: List[str]

@app.post("/api/reports/bulk-delete")
async def bulk_delete_reports(
    request: BulkDeleteReportsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое удаление отчетов"""
    try:
        report_ids = request.report_ids
        if not report_ids:
            raise HTTPException(status_code=400, detail="No report IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        deleted_count = 0
        for report_id in report_ids:
            try:
                report_uuid = uuid_lib.UUID(report_id)
                rep_result = await db.execute(select(Report).where(Report.id == report_uuid))
                report = rep_result.scalar_one_or_none()
                
                if not report:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if report.created_by and report.created_by == user.id:
                        allowed = True
                    elif report.created_by is None and report.inspection_id:
                        insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                        insp = insp_result.scalar_one_or_none()
                        if insp and insp.inspector_id == user.id:
                            allowed = True
                
                if not allowed:
                    continue
                
                # Удаляем файлы
                for p in [report.file_path, getattr(report, "word_file_path", None)]:
                    if p:
                        try:
                            fp = Path(p)
                            if fp.exists():
                                fp.unlink()
                        except Exception:
                            pass
                
                await db.delete(report)
                deleted_count += 1
            except Exception as e:
                continue
        
        await db.commit()
        return {"deleted": deleted_count, "total": len(report_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete reports: {str(e)}")

class BulkArchiveReportsRequest(BaseModel):
    report_ids: List[str]
    archive: bool = True

@app.post("/api/reports/bulk-archive")
async def bulk_archive_reports(
    request: BulkArchiveReportsRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Массовое архивирование/разархивирование отчетов"""
    try:
        report_ids = request.report_ids
        archive = request.archive
        if not report_ids:
            raise HTTPException(status_code=400, detail="No report IDs provided")
        
        user_id = current_user.get("id")
        if not user_id:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_result = await db.execute(select(User).where(User.id == uuid_lib.UUID(user_id)))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        archived_count = 0
        for report_id in report_ids:
            try:
                report_uuid = uuid_lib.UUID(report_id)
                rep_result = await db.execute(select(Report).where(Report.id == report_uuid))
                report = rep_result.scalar_one_or_none()
                
                if not report:
                    continue
                
                # Проверка прав
                allowed = False
                if user.role in ["admin", "chief_operator", "operator"]:
                    allowed = True
                elif user.role == "engineer":
                    if report.created_by and report.created_by == user.id:
                        allowed = True
                    elif report.created_by is None and report.inspection_id:
                        insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                        insp = insp_result.scalar_one_or_none()
                        if insp and insp.inspector_id == user.id:
                            allowed = True
                
                if not allowed:
                    continue
                
                report.is_archived = archive
                archived_count += 1
            except Exception as e:
                continue
        
        await db.commit()
        return {"archived": archived_count, "total": len(report_ids)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to archive reports: {str(e)}")

@app.delete("/api/reports/cleanup")
async def cleanup_reports(
    older_than_days: int = 90,
    before: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Массовое удаление старых отчетов.
    - admin/chief_operator/operator: удаляют любые
    - engineer: удаляет только свои
    Параметры:
      - older_than_days: удалить старше N дней (по created_at)
      - before: ISO дата/время (например 2025-12-01 или 2025-12-01T00:00:00)
    """
    try:
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        cutoff = None
        if before:
            try:
                cutoff = datetime.fromisoformat(before.replace("Z", "+00:00"))
            except Exception:
                # fallback для формата YYYY-MM-DD
                try:
                    cutoff = datetime.strptime(before, "%Y-%m-%d")
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid 'before' format")
        else:
            if older_than_days < 1:
                raise HTTPException(status_code=400, detail="older_than_days must be >= 1")
            cutoff = datetime.now() - timedelta(days=int(older_than_days))

        query = select(Report).where(Report.created_at < cutoff)

        # Ограничение инженера только своими отчетами (как в get_reports)
        if current_user.role == "engineer":
            query = (
                query.join(Inspection, Report.inspection_id == Inspection.id, isouter=True)
                .where(
                    or_(
                        Report.created_by == current_user.id,
                        and_(Report.created_by.is_(None), Inspection.inspector_id == current_user.id),
                    )
                )
            )
        elif current_user.role not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        result = await db.execute(query)
        reports = result.scalars().all()

        deleted = 0
        for report in reports:
            # удаляем файлы
            for p in [report.file_path, getattr(report, "word_file_path", None)]:
                if p:
                    try:
                        fp = Path(p)
                        if fp.exists():
                            fp.unlink()
                    except Exception:
                        pass
            await db.delete(report)
            deleted += 1

        await db.commit()
        return {"status": "ok", "deleted": deleted, "cutoff": cutoff.isoformat()}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to cleanup reports: {str(e)}")

@app.get("/api/reports/{report_id}/download")
async def download_report(
    report_id: str,
    format: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Download report file (PDF/DOCX)"""
    try:
        # Текущий пользователь и права
        user_result = await db.execute(select(User).where(User.username == username))
        current_user = user_result.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=404, detail="User not found")

        result = await db.execute(
            select(Report).where(Report.id == uuid_lib.UUID(report_id))
        )
        report = result.scalar_one_or_none()
        if not report:
            raise HTTPException(status_code=404, detail="Report not found")

        # Инженер может скачивать только свои отчеты
        if current_user.role == "engineer":
            allowed = False
            if report.created_by and report.created_by == current_user.id:
                allowed = True
            elif report.created_by is None and report.inspection_id:
                insp_result = await db.execute(select(Inspection).where(Inspection.id == report.inspection_id))
                insp = insp_result.scalar_one_or_none()
                if insp and insp.inspector_id == current_user.id:
                    allowed = True
            if not allowed:
                raise HTTPException(status_code=403, detail="Доступ запрещен")

        # Выбор файла по формату (если указан), иначе по расширению/наличию
        fmt = (format or "").strip().lower()
        selected_path = None
        if fmt in ["docx", "doc", "word"]:
            if report.word_file_path and os.path.exists(report.word_file_path):
                selected_path = report.word_file_path
            elif report.file_path and str(report.file_path).lower().endswith(".docx") and os.path.exists(report.file_path):
                selected_path = report.file_path
        elif fmt in ["pdf"]:
            if report.file_path and str(report.file_path).lower().endswith(".pdf") and os.path.exists(report.file_path):
                selected_path = report.file_path

        if not selected_path:
            # auto
            if report.file_path and os.path.exists(report.file_path):
                selected_path = report.file_path
            elif report.word_file_path and os.path.exists(report.word_file_path):
                selected_path = report.word_file_path

        if not selected_path or not os.path.exists(selected_path):
            raise HTTPException(status_code=404, detail="Report file not found")

        filename = os.path.basename(selected_path)
        lower = filename.lower()
        if lower.endswith(".docx"):
            media_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        else:
            media_type = "application/pdf"

        return FileResponse(
            selected_path,
            media_type=media_type,
            filename=filename
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid report_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Questionnaire endpoints
@app.get("/api/questionnaires")
async def get_questionnaires(
    equipment_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    """Получить список опросных листов"""
    try:
        query = select(Questionnaire)
        
        if equipment_id:
            try:
                equipment_uuid = uuid_lib.UUID(equipment_id)
                query = query.where(Questionnaire.equipment_id == equipment_uuid)
            except:
                raise HTTPException(status_code=400, detail="Invalid equipment_id format")
        
        query = query.order_by(Questionnaire.created_at.desc()).offset(skip).limit(limit)
        
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
                    "file_path": q.file_path,
                    "file_size": q.file_size or 0,
                    "word_file_path": q.word_file_path,
                    "word_file_size": q.word_file_size or 0,
                    "created_by": str(q.created_by) if q.created_by else None,
                    "created_at": q.created_at.isoformat() if q.created_at else None,
                }
                for q in questionnaires
            ],
            "total": len(questionnaires)
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/questionnaires/{questionnaire_id}")
async def get_questionnaire(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
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
        
        # Получаем методы НК для этого опросного листа
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.questionnaire_id == q_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        
        return {
            "id": str(questionnaire.id),
            "equipment_id": str(questionnaire.equipment_id),
            "equipment_inventory_number": questionnaire.equipment_inventory_number,
            "equipment_name": questionnaire.equipment_name,
            "inspection_date": questionnaire.inspection_date.isoformat() if questionnaire.inspection_date else None,
            "inspector_name": questionnaire.inspector_name,
            "inspector_position": questionnaire.inspector_position,
            "questionnaire_data": questionnaire.questionnaire_data,
            "file_path": questionnaire.file_path,
            "file_size": questionnaire.file_size or 0,
            "word_file_path": questionnaire.word_file_path,
            "word_file_size": questionnaire.word_file_size or 0,
            "created_by": str(questionnaire.created_by) if questionnaire.created_by else None,
            "created_at": questionnaire.created_at.isoformat() if questionnaire.created_at else None,
            "updated_at": questionnaire.updated_at.isoformat() if questionnaire.updated_at else None,
            "ndt_methods": [
                {
                    "id": str(m.id),
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                    "photos": m.photos or [],
                    "additional_data": m.additional_data or {},
                    "performed_date": m.performed_date.isoformat() if m.performed_date else None,
                }
                for m in ndt_methods
            ]
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/questionnaires/{questionnaire_id}/ndt-methods")
async def add_ndt_method(
    questionnaire_id: str,
    method_data: dict,
    db: AsyncSession = Depends(get_db)
):
    """Добавить метод НК к опросному листу"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        # Проверяем существование опросного листа
        q_result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = q_result.scalar_one_or_none()
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Создаем метод НК
        performed_date = None
        if method_data.get("performed_date"):
            try:
                performed_date = datetime.fromisoformat(method_data.get("performed_date").replace('Z', '+00:00'))
            except:
                pass
        
        # Обработка аннотированных изображений
        photos_list = method_data.get("photos", [])
        additional_data = method_data.get("additional_data", {})
        
        new_method = NDTMethod(
            questionnaire_id=q_uuid,
            equipment_id=questionnaire.equipment_id,
            method_code=method_data.get("method_code"),
            method_name=method_data.get("method_name"),
            is_performed=1 if method_data.get("is_performed", False) else 0,
            standard=method_data.get("standard"),
            equipment=method_data.get("equipment"),
            inspector_name=method_data.get("inspector_name"),
            inspector_level=method_data.get("inspector_level"),
            results=method_data.get("results"),
            defects=method_data.get("defects"),
            conclusion=method_data.get("conclusion"),
            photos=photos_list,
            additional_data=additional_data,
            performed_date=performed_date,
        )
        
        db.add(new_method)
        await db.commit()
        await db.refresh(new_method)
        
        return {
            "id": str(new_method.id),
            "status": "created"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to add NDT method: {str(e)}")

@app.post("/api/inspections/{inspection_id}/ndt-methods")
async def add_ndt_method_to_inspection(
    inspection_id: str,
    method_data: dict,
    db: AsyncSession = Depends(get_db)
):
    """Добавить метод НК к обследованию"""
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)
        
        # Проверяем существование обследования
        insp_result = await db.execute(
            select(Inspection).where(Inspection.id == insp_uuid)
        )
        inspection = insp_result.scalar_one_or_none()
        if not inspection:
            raise HTTPException(status_code=404, detail="Inspection not found")
        
        # Создаем метод НК
        performed_date = None
        if method_data.get("performed_date"):
            try:
                performed_date = datetime.fromisoformat(method_data.get("performed_date").replace('Z', '+00:00'))
            except:
                pass
        
        new_method = NDTMethod(
            inspection_id=insp_uuid,
            equipment_id=inspection.equipment_id,
            method_code=method_data.get("method_code"),
            method_name=method_data.get("method_name"),
            is_performed=1 if method_data.get("is_performed", False) else 0,
            standard=method_data.get("standard"),
            equipment=method_data.get("equipment"),
            inspector_name=method_data.get("inspector_name"),
            inspector_level=method_data.get("inspector_level"),
            results=method_data.get("results"),
            defects=method_data.get("defects"),
            conclusion=method_data.get("conclusion"),
            photos=method_data.get("photos", []),
            additional_data=method_data.get("additional_data", {}),
            performed_date=performed_date,
        )
        
        db.add(new_method)
        await db.commit()
        await db.refresh(new_method)
        
        return {
            "id": str(new_method.id),
            "status": "created"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid inspection_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to add NDT method: {str(e)}")

@app.post("/api/questionnaires/{questionnaire_id}/generate-pdf")
async def generate_questionnaire_pdf(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Сгенерировать PDF для опросного листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Получаем данные об оборудовании
        eq_result = await db.execute(
            select(Equipment).where(Equipment.id == questionnaire.equipment_id)
        )
        equipment = eq_result.scalar_one_or_none()
        
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        # Получаем методы НК
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.questionnaire_id == q_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        
        # Генерируем PDF
        generator = ReportGenerator()
        # Храним генерируемые файлы в /app/reports (примонтирован в docker-compose),
        # чтобы они не пропадали при пересборке контейнера.
        questionnaires_dir = Path("/app/reports/questionnaires")
        questionnaires_dir.mkdir(parents=True, exist_ok=True)
        
        filename = f"questionnaire_{questionnaire.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
        file_path = questionnaires_dir / filename
        
        generator.generate_questionnaire_report(
            questionnaire.questionnaire_data or {},
            {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
            },
            {
                "inventory_number": questionnaire.equipment_inventory_number,
                "equipment_name": questionnaire.equipment_name,
                "inspection_date": questionnaire.inspection_date.isoformat() if questionnaire.inspection_date else None,
                "inspector_name": questionnaire.inspector_name,
                "inspector_position": questionnaire.inspector_position,
            },
            str(file_path),
            [
                {
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                }
                for m in ndt_methods
            ]
        )
        
        # Обновляем запись опросного листа
        questionnaire.file_path = str(file_path)
        questionnaire.file_size = file_path.stat().st_size if file_path.exists() else 0
        await db.commit()
        
        return {
            "id": str(questionnaire.id),
            "file_path": str(file_path),
            "file_size": questionnaire.file_size,
            "status": "generated"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to generate PDF: {str(e)}")

@app.get("/api/questionnaires/{questionnaire_id}/download")
async def download_questionnaire(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Скачать опросный лист (PDF)"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Если PDF еще не сгенерирован, генерируем его
        if not questionnaire.file_path or not Path(questionnaire.file_path).exists():
            await generate_questionnaire_pdf(questionnaire_id, db)
            result = await db.execute(
                select(Questionnaire).where(Questionnaire.id == q_uuid)
            )
            questionnaire = result.scalar_one_or_none()
        
        if not questionnaire.file_path:
            raise HTTPException(status_code=404, detail="PDF file not found")
        
        file_path = Path(questionnaire.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="PDF file not found on disk")
        
        return FileResponse(
            path=str(file_path),
            filename=file_path.name,
            media_type='application/pdf'
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/questionnaires/{questionnaire_id}/generate-word")
async def generate_questionnaire_word(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Сгенерировать Word документ для опросного листа"""
    try:
        from word_generator import WordGenerator
        
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Получаем данные об оборудовании
        eq_result = await db.execute(
            select(Equipment).where(Equipment.id == questionnaire.equipment_id)
        )
        equipment = eq_result.scalar_one_or_none()
        
        if not equipment:
            raise HTTPException(status_code=404, detail="Equipment not found")
        
        # Получаем методы НК
        ndt_result = await db.execute(
            select(NDTMethod).where(NDTMethod.questionnaire_id == q_uuid)
        )
        ndt_methods = ndt_result.scalars().all()
        
        # Генерируем Word
        generator = WordGenerator()
        # Храним генерируемые файлы в /app/reports (примонтирован в docker-compose),
        # чтобы они не пропадали при пересборке контейнера.
        questionnaires_dir = Path("/app/reports/questionnaires")
        questionnaires_dir.mkdir(parents=True, exist_ok=True)
        
        filename = f"questionnaire_{questionnaire.id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.docx"
        file_path = questionnaires_dir / filename
        
        generator.generate_questionnaire_word(
            questionnaire.questionnaire_data or {},
            {
                "id": str(equipment.id),
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
            },
            {
                "inventory_number": questionnaire.equipment_inventory_number,
                "equipment_name": questionnaire.equipment_name,
                "inspection_date": questionnaire.inspection_date.isoformat() if questionnaire.inspection_date else None,
                "inspector_name": questionnaire.inspector_name,
                "inspector_position": questionnaire.inspector_position,
            },
            [
                {
                    "method_code": m.method_code,
                    "method_name": m.method_name,
                    "is_performed": bool(m.is_performed),
                    "standard": m.standard,
                    "equipment": m.equipment,
                    "inspector_name": m.inspector_name,
                    "inspector_level": m.inspector_level,
                    "results": m.results,
                    "defects": m.defects,
                    "conclusion": m.conclusion,
                }
                for m in ndt_methods
            ],
            str(file_path)
        )
        
        # Обновляем запись опросного листа
        questionnaire.word_file_path = str(file_path)
        questionnaire.word_file_size = file_path.stat().st_size if file_path.exists() else 0
        await db.commit()
        
        return {
            "id": str(questionnaire.id),
            "word_file_path": str(file_path),
            "word_file_size": questionnaire.word_file_size,
            "status": "generated"
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to generate Word: {str(e)}")

@app.get("/api/questionnaires/{questionnaire_id}/download-word")
async def download_questionnaire_word(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Скачать Word документ опросного листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = result.scalar_one_or_none()
        
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Если Word еще не сгенерирован, генерируем его
        if not questionnaire.word_file_path or not Path(questionnaire.word_file_path).exists():
            await generate_questionnaire_word(questionnaire_id, db)
            result = await db.execute(
                select(Questionnaire).where(Questionnaire.id == q_uuid)
            )
            questionnaire = result.scalar_one_or_none()
        
        if not questionnaire.word_file_path:
            raise HTTPException(status_code=404, detail="Word file not found")
        
        file_path = Path(questionnaire.word_file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="Word file not found on disk")
        
        return FileResponse(
            path=str(file_path),
            filename=file_path.name,
            media_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Document files endpoints
@app.post("/api/questionnaires/{questionnaire_id}/documents/{document_number}/upload")
async def upload_document_file(
    questionnaire_id: str,
    document_number: str,
    file: UploadFile = File(...),
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Загрузить файл документа для чек-листа"""
    try:
        # Проверяем формат questionnaire_id
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        # Проверяем существование опросного листа
        q_result = await db.execute(
            select(Questionnaire).where(Questionnaire.id == q_uuid)
        )
        questionnaire = q_result.scalar_one_or_none()
        if not questionnaire:
            raise HTTPException(status_code=404, detail="Questionnaire not found")
        
        # Проверяем номер/ключ документа.
        # - Основной список (1..17) — "Перечень рассмотренных документов".
        # - Дополнительно разрешаем любые "безопасные" ключи для прочих вложений чек-листа:
        #   factory_plate_photo, control_scheme_image, photo_1, scheme_2025_12 и т.п.
        allowed_numbers = {str(i) for i in range(1, 18)}
        if document_number not in allowed_numbers:
            import re
            # безопасный ключ: латиница/цифры/подчерк/дефис, 1..64 символа
            if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", document_number):
                raise HTTPException(
                    status_code=400,
                    detail="Invalid document key. Use 1..17 or a safe key like factory_plate_photo/control_scheme_image/photo_1",
                )
        
        # Проверяем тип файла (только изображения и PDF)
        allowed_types = ['image/jpeg', 'image/jpg', 'image/png', 'application/pdf']
        if file.content_type not in allowed_types:
            raise HTTPException(
                status_code=400, 
                detail=f"Invalid file type. Allowed types: {', '.join(allowed_types)}"
            )
        
        # Получаем пользователя для uploaded_by
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        user_id = user.id if user else None
        
        # Создаем директорию для файлов документов в /app/uploads (примонтирован),
        # чтобы вложения чек-листа не пропадали при пересборке контейнера.
        documents_dir = Path("/app/uploads/questionnaire_documents") / str(q_uuid)
        documents_dir.mkdir(parents=True, exist_ok=True)
        
        # Генерируем уникальное имя файла
        file_extension = Path(file.filename).suffix if file.filename else '.bin'
        if file.content_type == 'application/pdf':
            file_extension = '.pdf'
        elif 'image' in file.content_type:
            file_extension = '.jpg' if 'jpeg' in file.content_type else '.png'
        
        file_id = uuid_lib.uuid4()
        file_name = f"doc_{document_number}_{file_id}{file_extension}"
        file_path = documents_dir / file_name
        
        # Сохраняем файл
        file_content = await file.read()
        with open(file_path, 'wb') as f:
            f.write(file_content)
        
        file_size = len(file_content)
        
        # Удаляем старый файл для этого документа, если есть
        old_file_result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        old_file = old_file_result.scalar_one_or_none()
        if old_file:
            # Удаляем файл с диска
            old_path = Path(old_file.file_path)
            if old_path.exists():
                old_path.unlink()
            # Удаляем запись из БД
            await db.execute(delete(QuestionnaireDocumentFile).where(QuestionnaireDocumentFile.id == old_file.id))
        
        # Создаем новую запись в БД
        new_file = QuestionnaireDocumentFile(
            questionnaire_id=q_uuid,
            document_number=document_number,
            file_name=file.filename or file_name,
            file_path=str(file_path),
            file_size=file_size,
            file_type=file.content_type.split('/')[0] if file.content_type else None,  # image или application
            mime_type=file.content_type,
            uploaded_by=user_id
        )
        
        db.add(new_file)
        await db.commit()
        await db.refresh(new_file)
        
        return {
            "id": str(new_file.id),
            "questionnaire_id": questionnaire_id,
            "document_number": document_number,
            "file_name": new_file.file_name,
            "file_size": new_file.file_size,
            "file_type": new_file.file_type,
            "mime_type": new_file.mime_type,
            "created_at": new_file.created_at.isoformat() if new_file.created_at else None
        }
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to upload file: {str(e)}")

@app.get("/api/questionnaires/{questionnaire_id}/documents/{document_number}/download")
async def download_document_file(
    questionnaire_id: str,
    document_number: str,
    db: AsyncSession = Depends(get_db)
):
    """Скачать файл документа чек-листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        # Ищем файл
        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        doc_file = result.scalar_one_or_none()
        
        if not doc_file:
            raise HTTPException(status_code=404, detail="Document file not found")
        
        file_path = Path(doc_file.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="File not found on disk")
        
        # Определяем media_type
        media_type = doc_file.mime_type or 'application/octet-stream'
        if doc_file.file_type == 'image':
            if 'jpeg' in doc_file.mime_type or 'jpg' in doc_file.mime_type:
                media_type = 'image/jpeg'
            elif 'png' in doc_file.mime_type:
                media_type = 'image/png'
        elif doc_file.file_type == 'application' or 'pdf' in doc_file.mime_type:
            media_type = 'application/pdf'
        
        return FileResponse(
            path=str(file_path),
            filename=doc_file.file_name,
            media_type=media_type
        )
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/questionnaires/{questionnaire_id}/documents")
async def get_questionnaire_documents(
    questionnaire_id: str,
    db: AsyncSession = Depends(get_db)
):
    """Получить список всех файлов документов для опросного листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid
            ).order_by(QuestionnaireDocumentFile.document_number)
        )
        files = result.scalars().all()
        
        return {
            "items": [
                {
                    "id": str(f.id),
                    "document_number": f.document_number,
                    "file_name": f.file_name,
                    "file_size": f.file_size,
                    "file_type": f.file_type,
                    "mime_type": f.mime_type,
                    "created_at": f.created_at.isoformat() if f.created_at else None
                }
                for f in files
            ],
            "total": len(files)
        }
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/questionnaires/{questionnaire_id}/documents/{document_number}/view")
async def view_document_file(
    questionnaire_id: str,
    document_number: str,
    db: AsyncSession = Depends(get_db)
):
    """
    Просмотр файла документа чек-листа в браузере (Content-Disposition: inline).
    Поддерживает изображения и PDF.
    """
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)

        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        doc_file = result.scalar_one_or_none()

        if not doc_file:
            raise HTTPException(status_code=404, detail="Document file not found")

        file_path = Path(doc_file.file_path)
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="File not found on disk")

        media_type = doc_file.mime_type or 'application/octet-stream'
        if doc_file.file_type == 'image':
            if doc_file.mime_type and ('jpeg' in doc_file.mime_type or 'jpg' in doc_file.mime_type):
                media_type = 'image/jpeg'
            elif doc_file.mime_type and 'png' in doc_file.mime_type:
                media_type = 'image/png'
        elif (doc_file.file_type == 'application') or (doc_file.mime_type and 'pdf' in doc_file.mime_type):
            media_type = 'application/pdf'

        return FileResponse(
            path=str(file_path),
            media_type=media_type,
            headers={
                "Content-Disposition": f'inline; filename="{doc_file.file_name}"'
            }
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/questionnaires/{questionnaire_id}/documents/{document_number}")
async def delete_document_file(
    questionnaire_id: str,
    document_number: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить файл документа чек-листа"""
    try:
        q_uuid = uuid_lib.UUID(questionnaire_id)
        
        # Ищем файл
        result = await db.execute(
            select(QuestionnaireDocumentFile).where(
                QuestionnaireDocumentFile.questionnaire_id == q_uuid,
                QuestionnaireDocumentFile.document_number == document_number
            )
        )
        doc_file = result.scalar_one_or_none()
        
        if not doc_file:
            raise HTTPException(status_code=404, detail="Document file not found")
        
        # Удаляем файл с диска
        file_path = Path(doc_file.file_path)
        if file_path.exists():
            file_path.unlink()
        
        # Удаляем запись из БД
        await db.execute(delete(QuestionnaireDocumentFile).where(QuestionnaireDocumentFile.id == doc_file.id))
        await db.commit()
        
        return {"status": "deleted", "document_number": document_number}
        
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid questionnaire_id format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# ========== API для управления поверками оборудования ==========

@app.get("/api/verification-equipment")
async def get_verification_equipment(
    days_before_expiry: Optional[int] = None,  # Предупреждение за N дней до истечения
    equipment_type: Optional[str] = None,  # Фильтр по типу
    is_active: Optional[bool] = True,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить список оборудования для поверок"""
    try:
        query = select(VerificationEquipment)
        
        if is_active is not None:
            query = query.where(VerificationEquipment.is_active == (1 if is_active else 0))
        
        if equipment_type:
            query = query.where(VerificationEquipment.equipment_type == equipment_type)
        
        if days_before_expiry is not None:
            today = date.today()
            warning_date = today + timedelta(days=days_before_expiry)
            query = query.where(
                VerificationEquipment.next_verification_date <= warning_date,
                VerificationEquipment.next_verification_date >= today
            )
        
        result = await db.execute(query.order_by(VerificationEquipment.next_verification_date))
        items = result.scalars().all()
        
        return [{
            "id": str(item.id),
            "name": item.name,
            "equipment_type": item.equipment_type,
            "category": item.category,
            "serial_number": item.serial_number,
            "manufacturer": item.manufacturer,
            "model": item.model,
            "inventory_number": item.inventory_number,
            "verification_date": item.verification_date.isoformat() if item.verification_date else None,
            "next_verification_date": item.next_verification_date.isoformat() if item.next_verification_date else None,
            "verification_certificate_number": item.verification_certificate_number,
            "verification_organization": item.verification_organization,
            "scan_file_path": item.scan_file_path,
            "scan_file_name": item.scan_file_name,
            "is_active": bool(item.is_active),
            "notes": item.notes,
            "days_until_expiry": (item.next_verification_date - date.today()).days if item.next_verification_date else None,
            "is_expired": item.next_verification_date < date.today() if item.next_verification_date else False,
            "created_at": item.created_at.isoformat() if item.created_at else None,
        } for item in items]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/verification-equipment")
async def create_verification_equipment(
    name: str = Form(...),
    equipment_type: str = Form(...),
    serial_number: str = Form(...),
    verification_date: str = Form(...),
    next_verification_date: str = Form(...),
    category: Optional[str] = Form(None),
    manufacturer: Optional[str] = Form(None),
    model: Optional[str] = Form(None),
    inventory_number: Optional[str] = Form(None),
    verification_certificate_number: Optional[str] = Form(None),
    verification_organization: Optional[str] = Form(None),
    notes: Optional[str] = Form(None),
    scan_file: Optional[UploadFile] = File(None),
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Создать новое оборудование для поверки"""
    try:
        # Проверка прав (только admin, chief_operator, operator)
        if current_user.get("role") not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        scan_file_path = None
        scan_file_name = None
        scan_file_size = None
        scan_mime_type = None
        
        if scan_file:
            upload_dir = Path("uploads/verification-scans")
            upload_dir.mkdir(parents=True, exist_ok=True)
            
            file_ext = Path(scan_file.filename).suffix
            file_name = f"{uuid_lib.uuid4()}{file_ext}"
            file_path = upload_dir / file_name
            
            content = await scan_file.read()
            with open(file_path, "wb") as f:
                f.write(content)
            
            scan_file_path = str(file_path)
            scan_file_name = scan_file.filename
            scan_file_size = len(content)
            scan_mime_type = scan_file.content_type
        
        verification_date_obj = datetime.strptime(verification_date, "%Y-%m-%d").date()
        next_verification_date_obj = datetime.strptime(next_verification_date, "%Y-%m-%d").date()
        
        new_equipment = VerificationEquipment(
            name=name,
            equipment_type=equipment_type,
            category=category,
            serial_number=serial_number,
            manufacturer=manufacturer,
            model=model,
            inventory_number=inventory_number,
            verification_date=verification_date_obj,
            next_verification_date=next_verification_date_obj,
            verification_certificate_number=verification_certificate_number,
            verification_organization=verification_organization,
            scan_file_path=scan_file_path,
            scan_file_name=scan_file_name,
            scan_file_size=scan_file_size,
            scan_mime_type=scan_mime_type,
            notes=notes
        )
        
        db.add(new_equipment)
        await db.commit()
        await db.refresh(new_equipment)
        
        return {
            "id": str(new_equipment.id),
            "name": new_equipment.name,
            "equipment_type": new_equipment.equipment_type,
            "serial_number": new_equipment.serial_number,
            "next_verification_date": new_equipment.next_verification_date.isoformat(),
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Неверный формат даты: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/verification-equipment/{equipment_id}")
async def get_verification_equipment_by_id(
    equipment_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить оборудование для поверки по ID"""
    try:
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Получить историю поверок
        history_result = await db.execute(
            select(VerificationHistory)
            .where(VerificationHistory.verification_equipment_id == item.id)
            .order_by(VerificationHistory.verification_date.desc())
        )
        history = history_result.scalars().all()
        
        return {
            "id": str(item.id),
            "name": item.name,
            "equipment_type": item.equipment_type,
            "category": item.category,
            "serial_number": item.serial_number,
            "manufacturer": item.manufacturer,
            "model": item.model,
            "inventory_number": item.inventory_number,
            "verification_date": item.verification_date.isoformat() if item.verification_date else None,
            "next_verification_date": item.next_verification_date.isoformat() if item.next_verification_date else None,
            "verification_certificate_number": item.verification_certificate_number,
            "verification_organization": item.verification_organization,
            "scan_file_path": item.scan_file_path,
            "scan_file_name": item.scan_file_name,
            "scan_file_size": item.scan_file_size,
            "scan_mime_type": item.scan_mime_type,
            "is_active": bool(item.is_active),
            "notes": item.notes,
            "days_until_expiry": (item.next_verification_date - date.today()).days if item.next_verification_date else None,
            "is_expired": item.next_verification_date < date.today() if item.next_verification_date else False,
            "history": [{
                "id": str(h.id),
                "verification_date": h.verification_date.isoformat(),
                "next_verification_date": h.next_verification_date.isoformat(),
                "certificate_number": h.certificate_number,
                "verification_organization": h.verification_organization,
                "scan_file_path": h.scan_file_path,
                "scan_file_name": h.scan_file_name,
                "notes": h.notes,
                "created_at": h.created_at.isoformat() if h.created_at else None,
            } for h in history],
            "created_at": item.created_at.isoformat() if item.created_at else None,
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/api/verification-equipment/{equipment_id}")
async def update_verification_equipment(
    equipment_id: str,
    name: Optional[str] = Form(None),
    equipment_type: Optional[str] = Form(None),
    serial_number: Optional[str] = Form(None),
    verification_date: Optional[str] = Form(None),
    next_verification_date: Optional[str] = Form(None),
    category: Optional[str] = Form(None),
    manufacturer: Optional[str] = Form(None),
    model: Optional[str] = Form(None),
    inventory_number: Optional[str] = Form(None),
    verification_certificate_number: Optional[str] = Form(None),
    verification_organization: Optional[str] = Form(None),
    notes: Optional[str] = Form(None),
    is_active: Optional[bool] = Form(None),
    scan_file: Optional[UploadFile] = File(None),
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Обновить оборудование для поверки"""
    try:
        if current_user.get("role") not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Сохранить старую запись в историю, если изменилась дата поверки
        if verification_date and item.verification_date:
            old_date = item.verification_date
            new_date = datetime.strptime(verification_date, "%Y-%m-%d").date()
            if old_date != new_date:
                history_entry = VerificationHistory(
                    verification_equipment_id=item.id,
                    verification_date=old_date,
                    next_verification_date=item.next_verification_date,
                    certificate_number=item.verification_certificate_number,
                    verification_organization=item.verification_organization,
                    scan_file_path=item.scan_file_path,
                    scan_file_name=item.scan_file_name,
                    notes=item.notes
                )
                if "id" in current_user:
                    history_entry.created_by = uuid_lib.UUID(current_user["id"])
                db.add(history_entry)
        
        if name is not None:
            item.name = name
        if equipment_type is not None:
            item.equipment_type = equipment_type
        if category is not None:
            item.category = category
        if serial_number is not None:
            item.serial_number = serial_number
        if manufacturer is not None:
            item.manufacturer = manufacturer
        if model is not None:
            item.model = model
        if inventory_number is not None:
            item.inventory_number = inventory_number
        if verification_date is not None:
            item.verification_date = datetime.strptime(verification_date, "%Y-%m-%d").date()
        if next_verification_date is not None:
            item.next_verification_date = datetime.strptime(next_verification_date, "%Y-%m-%d").date()
        if verification_certificate_number is not None:
            item.verification_certificate_number = verification_certificate_number
        if verification_organization is not None:
            item.verification_organization = verification_organization
        if notes is not None:
            item.notes = notes
        if is_active is not None:
            item.is_active = 1 if is_active else 0
        
        if scan_file:
            # Удалить старый файл, если есть
            if item.scan_file_path and os.path.exists(item.scan_file_path):
                try:
                    os.remove(item.scan_file_path)
                except:
                    pass
            
            upload_dir = Path("uploads/verification-scans")
            upload_dir.mkdir(parents=True, exist_ok=True)
            
            file_ext = Path(scan_file.filename).suffix
            file_name = f"{uuid_lib.uuid4()}{file_ext}"
            file_path = upload_dir / file_name
            
            content = await scan_file.read()
            with open(file_path, "wb") as f:
                f.write(content)
            
            item.scan_file_path = str(file_path)
            item.scan_file_name = scan_file.filename
            item.scan_file_size = len(content)
            item.scan_mime_type = scan_file.content_type
        
        await db.commit()
        await db.refresh(item)
        
        return {
            "id": str(item.id),
            "name": item.name,
            "equipment_type": item.equipment_type,
            "next_verification_date": item.next_verification_date.isoformat(),
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Неверный формат: {str(e)}")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/verification-equipment/{equipment_id}")
async def delete_verification_equipment(
    equipment_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Удалить оборудование для поверки"""
    try:
        if current_user.get("role") not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Удалить файл скана, если есть
        if item.scan_file_path and os.path.exists(item.scan_file_path):
            try:
                os.remove(item.scan_file_path)
            except:
                pass
        
        await db.delete(item)
        await db.commit()
        
        return {"status": "deleted", "id": equipment_id}
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/verification-equipment/{equipment_id}/scan")
async def get_verification_scan(
    equipment_id: str,
    inline: bool = False,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить скан свидетельства о поверке"""
    try:
        result = await db.execute(
            select(VerificationEquipment).where(VerificationEquipment.id == uuid_lib.UUID(equipment_id))
        )
        item = result.scalar_one_or_none()
        
        if not item or not item.scan_file_path:
            raise HTTPException(status_code=404, detail="Скан не найден")
        
        if not os.path.exists(item.scan_file_path):
            raise HTTPException(status_code=404, detail="Файл не найден на сервере")
        
        from fastapi.responses import StreamingResponse
        
        def iterfile():
            with open(item.scan_file_path, mode="rb") as file_like:
                yield from file_like
        
        headers = {}
        if inline:
            headers["Content-Disposition"] = f'inline; filename="{item.scan_file_name or "scan.pdf"}"'
        else:
            headers["Content-Disposition"] = f'attachment; filename="{item.scan_file_name or "scan.pdf"}"'
        
        return StreamingResponse(
            iterfile(),
            media_type=item.scan_mime_type or "application/pdf",
            headers=headers
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/inspections/{inspection_id}/equipment")
async def add_equipment_to_inspection(
    inspection_id: str,
    equipment_data: dict,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    """Добавить используемое оборудование для поверок к обследованию"""
    try:
        # Проверка существования обследования
        insp_uuid = uuid_lib.UUID(inspection_id)
        insp_result = await db.execute(select(Inspection).where(Inspection.id == insp_uuid))
        inspection = insp_result.scalar_one_or_none()
        
        if not inspection:
            raise HTTPException(status_code=404, detail="Обследование не найдено")
        
        # Проверка прав
        user_result = await db.execute(select(User).where(User.username == current_user["username"]))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="Пользователь не найден")
        
        if user.role not in ["admin", "chief_operator", "operator", "engineer"]:
            raise HTTPException(status_code=403, detail="Недостаточно прав")
        
        # Если engineer, проверяем, что это его обследование
        if user.role == "engineer" and inspection.inspector_id != user.id:
            raise HTTPException(status_code=403, detail="Можно добавлять оборудование только к своим обследованиям")
        
        # Получаем список ID оборудования для поверок
        equipment_ids = equipment_data.get("verification_equipment_ids", [])
        if not isinstance(equipment_ids, list):
            raise HTTPException(status_code=400, detail="verification_equipment_ids должен быть списком")
        
        added = []
        for eq_id in equipment_ids:
            try:
                eq_uuid = uuid_lib.UUID(eq_id)
                # Проверяем существование оборудования
                eq_result = await db.execute(
                    select(VerificationEquipment).where(VerificationEquipment.id == eq_uuid)
                )
                ver_eq = eq_result.scalar_one_or_none()
                
                if not ver_eq:
                    continue
                
                # Проверяем, не добавлено ли уже
                existing = await db.execute(
                    select(InspectionEquipment).where(
                        InspectionEquipment.inspection_id == insp_uuid,
                        InspectionEquipment.verification_equipment_id == eq_uuid
                    )
                )
                if existing.scalar_one_or_none():
                    continue
                
                # Создаем связь
                inspection_equipment = InspectionEquipment(
                    inspection_id=insp_uuid,
                    verification_equipment_id=eq_uuid
                )
                db.add(inspection_equipment)
                added.append(str(eq_id))
            except ValueError:
                continue
        
        await db.commit()
        
        return {
            "status": "success",
            "inspection_id": inspection_id,
            "equipment_added": len(added),
            "equipment_ids": added
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/inspections/{inspection_id}/equipment")
async def get_inspection_equipment(
    inspection_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Получить список используемого оборудования для обследования"""
    try:
        insp_uuid = uuid_lib.UUID(inspection_id)
        
        result = await db.execute(
            select(InspectionEquipment, VerificationEquipment)
            .join(VerificationEquipment, InspectionEquipment.verification_equipment_id == VerificationEquipment.id)
            .where(InspectionEquipment.inspection_id == insp_uuid)
        )
        items = result.all()
        
        equipment_list = []
        for ie, ve in items:
            equipment_list.append({
                "id": str(ve.id),
                "name": ve.name,
                "equipment_type": ve.equipment_type,
                "serial_number": ve.serial_number,
                "manufacturer": ve.manufacturer,
                "model": ve.model,
                "verification_date": ve.verification_date.isoformat() if ve.verification_date else None,
                "next_verification_date": ve.next_verification_date.isoformat() if ve.next_verification_date else None,
                "verification_certificate_number": ve.verification_certificate_number,
                "verification_organization": ve.verification_organization,
                "scan_file_path": ve.scan_file_path,
                "scan_file_name": ve.scan_file_name,
                "is_expired": ve.next_verification_date < date.today() if ve.next_verification_date else False,
            })
        
        return equipment_list
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/verification-equipment/export")
async def export_verification_equipment(
    format: str = "csv",  # csv или excel
    days_before_expiry: Optional[int] = None,
    equipment_type: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(verify_token_optional)
):
    """Экспорт списка оборудования для поверок"""
    try:
        query = select(VerificationEquipment).where(VerificationEquipment.is_active == 1)
        
        if equipment_type:
            query = query.where(VerificationEquipment.equipment_type == equipment_type)
        
        if days_before_expiry is not None:
            today = date.today()
            warning_date = today + timedelta(days=days_before_expiry)
            query = query.where(
                VerificationEquipment.next_verification_date <= warning_date,
                VerificationEquipment.next_verification_date >= today
            )
        
        result = await db.execute(query.order_by(VerificationEquipment.next_verification_date))
        items = result.scalars().all()
        
        if format.lower() == "csv":
            import csv
            import io
            
            output = io.StringIO()
            writer = csv.writer(output)
            
            # Заголовки
            writer.writerow([
                'Название', 'Тип', 'Категория', 'Серийный номер', 'Производитель', 'Модель',
                'Инвентарный номер', 'Дата поверки', 'Следующая поверка', 'Номер свидетельства',
                'Организация поверки', 'Статус', 'Дней до истечения'
            ])
            
            # Данные
            for item in items:
                days = (item.next_verification_date - date.today()).days if item.next_verification_date else None
                status = "Просрочено" if (item.next_verification_date and item.next_verification_date < date.today()) else (
                    f"Предупреждение ({days} дн.)" if days and days <= 30 else "Активно"
                )
                writer.writerow([
                    item.name or '',
                    item.equipment_type or '',
                    item.category or '',
                    item.serial_number or '',
                    item.manufacturer or '',
                    item.model or '',
                    item.inventory_number or '',
                    item.verification_date.strftime('%d.%m.%Y') if item.verification_date else '',
                    item.next_verification_date.strftime('%d.%m.%Y') if item.next_verification_date else '',
                    item.verification_certificate_number or '',
                    item.verification_organization or '',
                    status,
                    str(days) if days is not None else '',
                ])
            
            csv_content = output.getvalue()
            output.close()
            
            from fastapi.responses import Response
            return Response(
                content='\ufeff' + csv_content,
                media_type='text/csv; charset=utf-8',
                headers={'Content-Disposition': f'attachment; filename="verification_equipment_{date.today().isoformat()}.csv"'}
            )
        else:
            raise HTTPException(status_code=400, detail="Неподдерживаемый формат экспорта")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
