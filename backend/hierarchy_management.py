"""
API endpoints для управления иерархией оборудования и назначения инженеров
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, text
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime, date, timedelta
import uuid as uuid_lib

from database import get_db
from models import (
    User, Equipment, Enterprise, Branch, Workshop, EquipmentType,
    HierarchyEngineerAssignment
)
from auth import verify_token, verify_token_optional

router = APIRouter(prefix="/api/hierarchy", tags=["Hierarchy Management"])

# Pydantic models
class EnterpriseCreate(BaseModel):
    name: str
    code: Optional[str] = None
    description: Optional[str] = None

class BranchCreate(BaseModel):
    enterprise_id: str
    name: str
    code: Optional[str] = None
    description: Optional[str] = None

class WorkshopCreate(BaseModel):
    branch_id: str
    name: str
    code: Optional[str] = None
    description: Optional[str] = None

class EngineerAssignmentRequest(BaseModel):
    user_ids: List[str]  # Список ID инженеров
    expires_at: Optional[datetime] = None

# Enterprise endpoints
@router.get("/enterprises")
async def get_enterprises(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список предприятий"""
    try:
        import logging
        logger = logging.getLogger(__name__)
        logger.info(f"Запрос списка предприятий от пользователя: {username}")
        
        # Сначала проверяем все предприятия (включая неактивные) для диагностики
        all_result = await db.execute(select(Enterprise).order_by(Enterprise.name))
        all_enterprises = all_result.scalars().all()
        logger.info(f"Всего предприятий в базе (включая неактивные): {len(all_enterprises)}")
        
        # Затем фильтруем только активные
        result = await db.execute(
            select(Enterprise).where(Enterprise.is_active == 1).order_by(Enterprise.name)
        )
        enterprises = result.scalars().all()
        logger.info(f"Найдено активных предприятий: {len(enterprises)}")
        
        # Если активных нет, но есть неактивные - показываем все для диагностики
        if len(enterprises) == 0 and len(all_enterprises) > 0:
            logger.warning(f"ВНИМАНИЕ: Найдено {len(all_enterprises)} предприятий, но все они неактивны (is_active != 1)")
            logger.warning("Временно показываем все предприятия для диагностики")
            for e in all_enterprises[:5]:
                logger.warning(f"  Предприятие: {e.name}, is_active: {e.is_active}")
            # Временно используем все предприятия
            enterprises = all_enterprises
        
        items = [
            {
                "id": str(e.id),
                "name": e.name or "",
                "code": e.code or "",
                "description": e.description or "",
            }
            for e in enterprises
        ]
        
        logger.info(f"Возвращаем {len(items)} предприятий")
        return {"items": items}
    except Exception as e:
        import logging
        logger = logging.getLogger(__name__)
        logger.error(f"Ошибка получения предприятий: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to get enterprises: {str(e)}")

@router.post("/enterprises")
async def create_enterprise(
    enterprise_data: EnterpriseCreate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать предприятие"""
    try:
        # Проверяем права (только admin и chief_operator)
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        if not user or user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        new_enterprise = Enterprise(
            name=enterprise_data.name,
            code=enterprise_data.code,
            description=enterprise_data.description
        )
        db.add(new_enterprise)
        await db.commit()
        await db.refresh(new_enterprise)
        
        return {
            "id": str(new_enterprise.id),
            "name": new_enterprise.name,
            "code": new_enterprise.code,
            "description": new_enterprise.description,
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create enterprise: {str(e)}")

# Branch endpoints
@router.get("/branches")
async def get_branches(
    enterprise_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список филиалов"""
    try:
        query = select(Branch).where(Branch.is_active == 1)
        if enterprise_id:
            query = query.where(Branch.enterprise_id == uuid_lib.UUID(enterprise_id))
        
        result = await db.execute(query.order_by(Branch.name))
        branches = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(b.id),
                    "enterprise_id": str(b.enterprise_id),
                    "name": b.name,
                    "code": b.code,
                    "description": b.description,
                }
                for b in branches
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get branches: {str(e)}")

@router.post("/branches")
async def create_branch(
    branch_data: BranchCreate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать филиал"""
    try:
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        if not user or user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        new_branch = Branch(
            enterprise_id=uuid_lib.UUID(branch_data.enterprise_id),
            name=branch_data.name,
            code=branch_data.code,
            description=branch_data.description
        )
        db.add(new_branch)
        await db.commit()
        await db.refresh(new_branch)
        
        return {
            "id": str(new_branch.id),
            "enterprise_id": str(new_branch.enterprise_id),
            "name": new_branch.name,
            "code": new_branch.code,
            "description": new_branch.description,
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create branch: {str(e)}")

# Workshop endpoints
@router.get("/workshops")
async def get_workshops(
    branch_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список цехов"""
    try:
        query = select(Workshop).where(Workshop.is_active == 1)
        if branch_id:
            query = query.where(Workshop.branch_id == uuid_lib.UUID(branch_id))
        
        result = await db.execute(query.order_by(Workshop.name))
        workshops = result.scalars().all()
        return {
            "items": [
                {
                    "id": str(w.id),
                    "branch_id": str(w.branch_id),
                    "name": w.name,
                    "code": w.code,
                    "description": w.description,
                }
                for w in workshops
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get workshops: {str(e)}")

@router.post("/workshops")
async def create_workshop(
    workshop_data: WorkshopCreate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать цех"""
    try:
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        if not user or user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        new_workshop = Workshop(
            branch_id=uuid_lib.UUID(workshop_data.branch_id),
            name=workshop_data.name,
            code=workshop_data.code,
            description=workshop_data.description
        )
        db.add(new_workshop)
        await db.commit()
        await db.refresh(new_workshop)
        
        return {
            "id": str(new_workshop.id),
            "branch_id": str(new_workshop.branch_id),
            "name": new_workshop.name,
            "code": new_workshop.code,
            "description": new_workshop.description,
        }
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create workshop: {str(e)}")

# Engineer assignment endpoints
@router.post("/enterprises/{enterprise_id}/assign-engineers")
async def assign_engineers_to_enterprise(
    enterprise_id: str,
    assignment_data: EngineerAssignmentRequest,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Назначить инженеров на предприятие"""
    try:
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        enterprise_uuid = uuid_lib.UUID(enterprise_id)
        
        for user_id_str in assignment_data.user_ids:
            user_uuid = uuid_lib.UUID(user_id_str)
            
            # Проверяем, не назначен ли уже
            existing_result = await db.execute(
                select(HierarchyEngineerAssignment).where(
                    and_(
                        HierarchyEngineerAssignment.user_id == user_uuid,
                        HierarchyEngineerAssignment.enterprise_id == enterprise_uuid,
                        text("hierarchy_engineer_assignments.is_active = 1")
                    )
                )
            )
            existing = existing_result.scalar_one_or_none()
            
            if existing:
                # Обновляем существующее назначение
                existing.expires_at = assignment_data.expires_at
                existing.granted_by = current_user.id
                existing.granted_at = datetime.now()
            else:
                # Создаем новое назначение
                new_assignment = HierarchyEngineerAssignment(
                    user_id=user_uuid,
                    enterprise_id=enterprise_uuid,
                    granted_by=current_user.id,
                    expires_at=assignment_data.expires_at
                )
                db.add(new_assignment)
        
        await db.commit()
        return {"message": "Инженеры успешно назначены на предприятие"}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid UUID format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to assign engineers: {str(e)}")

@router.post("/branches/{branch_id}/assign-engineers")
async def assign_engineers_to_branch(
    branch_id: str,
    assignment_data: EngineerAssignmentRequest,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Назначить инженеров на филиал"""
    try:
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        branch_uuid = uuid_lib.UUID(branch_id)
        
        for user_id_str in assignment_data.user_ids:
            user_uuid = uuid_lib.UUID(user_id_str)
            
            existing_result = await db.execute(
                select(HierarchyEngineerAssignment).where(
                    and_(
                        HierarchyEngineerAssignment.user_id == user_uuid,
                        HierarchyEngineerAssignment.branch_id == branch_uuid,
                        text("hierarchy_engineer_assignments.is_active = 1")
                    )
                )
            )
            existing = existing_result.scalar_one_or_none()
            
            if existing:
                existing.expires_at = assignment_data.expires_at
                existing.granted_by = current_user.id
                existing.granted_at = datetime.now()
            else:
                new_assignment = HierarchyEngineerAssignment(
                    user_id=user_uuid,
                    branch_id=branch_uuid,
                    granted_by=current_user.id,
                    expires_at=assignment_data.expires_at
                )
                db.add(new_assignment)
        
        await db.commit()
        return {"message": "Инженеры успешно назначены на филиал"}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid UUID format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to assign engineers: {str(e)}")

@router.post("/workshops/{workshop_id}/assign-engineers")
async def assign_engineers_to_workshop(
    workshop_id: str,
    assignment_data: EngineerAssignmentRequest,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Назначить инженеров на цех"""
    try:
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        workshop_uuid = uuid_lib.UUID(workshop_id)
        
        for user_id_str in assignment_data.user_ids:
            user_uuid = uuid_lib.UUID(user_id_str)
            
            existing_result = await db.execute(
                select(HierarchyEngineerAssignment).where(
                    and_(
                        HierarchyEngineerAssignment.user_id == user_uuid,
                        HierarchyEngineerAssignment.workshop_id == workshop_uuid,
                        text("hierarchy_engineer_assignments.is_active = 1")
                    )
                )
            )
            existing = existing_result.scalar_one_or_none()
            
            if existing:
                existing.expires_at = assignment_data.expires_at
                existing.granted_by = current_user.id
                existing.granted_at = datetime.now()
            else:
                new_assignment = HierarchyEngineerAssignment(
                    user_id=user_uuid,
                    workshop_id=workshop_uuid,
                    granted_by=current_user.id,
                    expires_at=assignment_data.expires_at
                )
                db.add(new_assignment)
        
        await db.commit()
        return {"message": "Инженеры успешно назначены на цех"}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid UUID format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to assign engineers: {str(e)}")

@router.post("/equipment-types/{equipment_type_id}/assign-engineers")
async def assign_engineers_to_equipment_type(
    equipment_type_id: str,
    assignment_data: EngineerAssignmentRequest,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Назначить инженеров на тип оборудования"""
    try:
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        equipment_type_uuid = uuid_lib.UUID(equipment_type_id)
        
        for user_id_str in assignment_data.user_ids:
            user_uuid = uuid_lib.UUID(user_id_str)
            
            existing_result = await db.execute(
                select(HierarchyEngineerAssignment).where(
                    and_(
                        HierarchyEngineerAssignment.user_id == user_uuid,
                        HierarchyEngineerAssignment.equipment_type_id == equipment_type_uuid,
                        text("hierarchy_engineer_assignments.is_active = 1")
                    )
                )
            )
            existing = existing_result.scalar_one_or_none()
            
            if existing:
                existing.expires_at = assignment_data.expires_at
                existing.granted_by = current_user.id
                existing.granted_at = datetime.now()
            else:
                new_assignment = HierarchyEngineerAssignment(
                    user_id=user_uuid,
                    equipment_type_id=equipment_type_uuid,
                    granted_by=current_user.id,
                    expires_at=assignment_data.expires_at
                )
                db.add(new_assignment)
        
        await db.commit()
        return {"message": "Инженеры успешно назначены на тип оборудования"}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid UUID format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to assign engineers: {str(e)}")

@router.post("/equipment/{equipment_id}/assign-engineers")
async def assign_engineers_to_equipment(
    equipment_id: str,
    assignment_data: EngineerAssignmentRequest,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Назначить инженеров на конкретное оборудование"""
    try:
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        current_user = user_result.scalar_one_or_none()
        if not current_user or current_user.role not in ["admin", "chief_operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        equipment_uuid = uuid_lib.UUID(equipment_id)
        
        for user_id_str in assignment_data.user_ids:
            user_uuid = uuid_lib.UUID(user_id_str)
            
            existing_result = await db.execute(
                select(HierarchyEngineerAssignment).where(
                    and_(
                        HierarchyEngineerAssignment.user_id == user_uuid,
                        HierarchyEngineerAssignment.equipment_id == equipment_uuid,
                        text("hierarchy_engineer_assignments.is_active = 1")
                    )
                )
            )
            existing = existing_result.scalar_one_or_none()
            
            if existing:
                existing.expires_at = assignment_data.expires_at
                existing.granted_by = current_user.id
                existing.granted_at = datetime.now()
            else:
                new_assignment = HierarchyEngineerAssignment(
                    user_id=user_uuid,
                    equipment_id=equipment_uuid,
                    granted_by=current_user.id,
                    expires_at=assignment_data.expires_at
                )
                db.add(new_assignment)
        
        await db.commit()
        return {"message": "Инженеры успешно назначены на оборудование"}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid UUID format")
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to assign engineers: {str(e)}")

@router.get("/assignments/{user_id}")
async def get_user_assignments(
    user_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить назначения для инженера"""
    try:
        user_uuid = uuid_lib.UUID(user_id)
        
        result = await db.execute(
            select(HierarchyEngineerAssignment).where(
                and_(
                    HierarchyEngineerAssignment.user_id == user_uuid,
                    text("hierarchy_engineer_assignments.is_active = 1"),
                    or_(
                        HierarchyEngineerAssignment.expires_at.is_(None),
                        HierarchyEngineerAssignment.expires_at > datetime.now()
                    )
                )
            )
        )
        assignments = result.scalars().all()
        
        return {
            "items": [
                {
                    "id": str(a.id),
                    "enterprise_id": str(a.enterprise_id) if a.enterprise_id else None,
                    "branch_id": str(a.branch_id) if a.branch_id else None,
                    "workshop_id": str(a.workshop_id) if a.workshop_id else None,
                    "equipment_type_id": str(a.equipment_type_id) if a.equipment_type_id else None,
                    "equipment_id": str(a.equipment_id) if a.equipment_id else None,
                    "expires_at": str(a.expires_at) if a.expires_at else None,
                }
                for a in assignments
            ]
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid UUID format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get assignments: {str(e)}")

@router.get("/enterprises/{enterprise_id}/assigned-engineers")
async def get_enterprise_assigned_engineers(
    enterprise_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список назначенных инженеров на предприятие"""
    try:
        enterprise_uuid = uuid_lib.UUID(enterprise_id)
        result = await db.execute(
            select(HierarchyEngineerAssignment, User).join(
                User, HierarchyEngineerAssignment.user_id == User.id
            ).where(
                and_(
                    HierarchyEngineerAssignment.enterprise_id == enterprise_uuid,
                    text("hierarchy_engineer_assignments.is_active = 1"),
                    or_(
                        HierarchyEngineerAssignment.expires_at.is_(None),
                        HierarchyEngineerAssignment.expires_at > datetime.now()
                    )
                )
            )
        )
        assignments = result.all()
        
        return {
            "items": [
                {
                    "user_id": str(a[0].user_id),
                    "username": a[1].username,
                    "full_name": a[1].full_name,
                    "email": a[1].email,
                    "granted_at": a[0].granted_at.isoformat() if a[0].granted_at else None,
                    "expires_at": a[0].expires_at.isoformat() if a[0].expires_at else None,
                }
                for a in assignments
            ]
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid UUID format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get assigned engineers: {str(e)}")

@router.get("/branches/{branch_id}/assigned-engineers")
async def get_branch_assigned_engineers(
    branch_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список назначенных инженеров на филиал"""
    try:
        branch_uuid = uuid_lib.UUID(branch_id)
        result = await db.execute(
            select(HierarchyEngineerAssignment, User).join(
                User, HierarchyEngineerAssignment.user_id == User.id
            ).where(
                and_(
                    HierarchyEngineerAssignment.branch_id == branch_uuid,
                    text("hierarchy_engineer_assignments.is_active = 1"),
                    or_(
                        HierarchyEngineerAssignment.expires_at.is_(None),
                        HierarchyEngineerAssignment.expires_at > datetime.now()
                    )
                )
            )
        )
        assignments = result.all()
        
        return {
            "items": [
                {
                    "user_id": str(a[0].user_id),
                    "username": a[1].username,
                    "full_name": a[1].full_name,
                    "email": a[1].email,
                    "granted_at": a[0].granted_at.isoformat() if a[0].granted_at else None,
                    "expires_at": a[0].expires_at.isoformat() if a[0].expires_at else None,
                }
                for a in assignments
            ]
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid UUID format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get assigned engineers: {str(e)}")

@router.get("/workshops/{workshop_id}/assigned-engineers")
async def get_workshop_assigned_engineers(
    workshop_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список назначенных инженеров на цех"""
    try:
        workshop_uuid = uuid_lib.UUID(workshop_id)
        result = await db.execute(
            select(HierarchyEngineerAssignment, User).join(
                User, HierarchyEngineerAssignment.user_id == User.id
            ).where(
                and_(
                    HierarchyEngineerAssignment.workshop_id == workshop_uuid,
                    text("hierarchy_engineer_assignments.is_active = 1"),
                    or_(
                        HierarchyEngineerAssignment.expires_at.is_(None),
                        HierarchyEngineerAssignment.expires_at > datetime.now()
                    )
                )
            )
        )
        assignments = result.all()
        
        return {
            "items": [
                {
                    "user_id": str(a[0].user_id),
                    "username": a[1].username,
                    "full_name": a[1].full_name,
                    "email": a[1].email,
                    "granted_at": a[0].granted_at.isoformat() if a[0].granted_at else None,
                    "expires_at": a[0].expires_at.isoformat() if a[0].expires_at else None,
                }
                for a in assignments
            ]
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid UUID format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get assigned engineers: {str(e)}")

@router.get("/equipment/{equipment_id}/assigned-engineers")
async def get_equipment_assigned_engineers(
    equipment_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список назначенных инженеров на оборудование"""
    try:
        equipment_uuid = uuid_lib.UUID(equipment_id)
        result = await db.execute(
            select(HierarchyEngineerAssignment, User).join(
                User, HierarchyEngineerAssignment.user_id == User.id
            ).where(
                and_(
                    HierarchyEngineerAssignment.equipment_id == equipment_uuid,
                    text("hierarchy_engineer_assignments.is_active = 1"),
                    or_(
                        HierarchyEngineerAssignment.expires_at.is_(None),
                        HierarchyEngineerAssignment.expires_at > datetime.now()
                    )
                )
            )
        )
        assignments = result.all()
        
        return {
            "items": [
                {
                    "user_id": str(a[0].user_id),
                    "username": a[1].username,
                    "full_name": a[1].full_name,
                    "email": a[1].email,
                    "granted_at": a[0].granted_at.isoformat() if a[0].granted_at else None,
                    "expires_at": a[0].expires_at.isoformat() if a[0].expires_at else None,
                }
                for a in assignments
            ]
        }
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid UUID format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get assigned engineers: {str(e)}")


