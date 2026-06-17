"""
API endpoints для управления иерархией оборудования и назначения инженеров
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, text, func
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


class EnterpriseUpdate(BaseModel):
    name: Optional[str] = None
    code: Optional[str] = None
    description: Optional[str] = None


async def _require_hierarchy_admin(db: AsyncSession, username: str) -> User:
    user_result = await db.execute(select(User).where(User.username == username))
    user = user_result.scalar_one_or_none()
    if not user or user.role not in ["admin", "chief_operator"]:
        raise HTTPException(status_code=403, detail="Доступ запрещен")
    return user


def _serialize_enterprise(enterprise: Enterprise) -> dict:
    return {
        "id": str(enterprise.id),
        "name": enterprise.name or "",
        "code": enterprise.code or "",
        "description": enterprise.description or "",
    }


class BranchCreate(BaseModel):
    enterprise_id: str
    name: str
    code: Optional[str] = None
    description: Optional[str] = None


class BranchUpdate(BaseModel):
    name: Optional[str] = None
    code: Optional[str] = None
    description: Optional[str] = None


class WorkshopCreate(BaseModel):
    branch_id: str
    name: str
    code: Optional[str] = None
    description: Optional[str] = None


class WorkshopUpdate(BaseModel):
    name: Optional[str] = None
    code: Optional[str] = None
    description: Optional[str] = None


def _serialize_branch(branch: Branch) -> dict:
    return {
        "id": str(branch.id),
        "enterprise_id": str(branch.enterprise_id),
        "name": branch.name or "",
        "code": branch.code or "",
        "description": branch.description or "",
    }


def _serialize_workshop(workshop: Workshop) -> dict:
    return {
        "id": str(workshop.id),
        "branch_id": str(workshop.branch_id),
        "name": workshop.name or "",
        "code": workshop.code or "",
        "description": workshop.description or "",
    }

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
            select(Enterprise).where(Enterprise.is_active == True).order_by(Enterprise.name)
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
        
        items = [_serialize_enterprise(e) for e in enterprises]

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
        await _require_hierarchy_admin(db, username)

        code = (enterprise_data.code or "").strip() or None
        if code:
            dup = await db.execute(
                select(Enterprise).where(Enterprise.code == code, Enterprise.is_active == True)
            )
            if dup.scalar_one_or_none():
                raise HTTPException(status_code=409, detail="Предприятие с таким кодом уже существует")

        new_enterprise = Enterprise(
            name=enterprise_data.name.strip(),
            code=code,
            description=(enterprise_data.description or "").strip() or None,
        )
        db.add(new_enterprise)
        await db.commit()
        await db.refresh(new_enterprise)

        return _serialize_enterprise(new_enterprise)
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create enterprise: {str(e)}")


@router.put("/enterprises/{enterprise_id}")
async def update_enterprise(
    enterprise_id: str,
    enterprise_data: EnterpriseUpdate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Обновить предприятие"""
    await _require_hierarchy_admin(db, username)

    try:
        enterprise_uuid = uuid_lib.UUID(enterprise_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Некорректный ID предприятия") from exc

    result = await db.execute(select(Enterprise).where(Enterprise.id == enterprise_uuid))
    enterprise = result.scalar_one_or_none()
    if not enterprise or not enterprise.is_active:
        raise HTTPException(status_code=404, detail="Предприятие не найдено")

    try:
        if enterprise_data.name is not None:
            name = enterprise_data.name.strip()
            if not name:
                raise HTTPException(status_code=400, detail="Название не может быть пустым")
            enterprise.name = name

        if enterprise_data.code is not None:
            code = enterprise_data.code.strip() or None
            if code:
                dup = await db.execute(
                    select(Enterprise).where(
                        Enterprise.code == code,
                        Enterprise.id != enterprise_uuid,
                        Enterprise.is_active == True,
                    )
                )
                if dup.scalar_one_or_none():
                    raise HTTPException(status_code=409, detail="Предприятие с таким кодом уже существует")
            enterprise.code = code

        if enterprise_data.description is not None:
            enterprise.description = enterprise_data.description.strip() or None

        await db.commit()
        await db.refresh(enterprise)
        return _serialize_enterprise(enterprise)
    except HTTPException:
        await db.rollback()
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Не удалось обновить предприятие: {e}") from e


@router.delete("/enterprises/{enterprise_id}")
async def delete_enterprise(
    enterprise_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Деактивировать предприятие (мягкое удаление)"""
    await _require_hierarchy_admin(db, username)

    try:
        enterprise_uuid = uuid_lib.UUID(enterprise_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Некорректный ID предприятия") from exc

    result = await db.execute(select(Enterprise).where(Enterprise.id == enterprise_uuid))
    enterprise = result.scalar_one_or_none()
    if not enterprise or not enterprise.is_active:
        raise HTTPException(status_code=404, detail="Предприятие не найдено")

    branches_count = await db.execute(
        select(func.count())
        .select_from(Branch)
        .where(Branch.enterprise_id == enterprise_uuid, Branch.is_active == True)
    )
    if (branches_count.scalar() or 0) > 0:
        raise HTTPException(
            status_code=409,
            detail="Нельзя удалить предприятие: сначала удалите или деактивируйте все филиалы",
        )

    try:
        enterprise.is_active = False
        await db.commit()
        return {"message": "Предприятие удалено", "id": str(enterprise.id)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Не удалось удалить предприятие: {e}") from e


# Branch endpoints
@router.get("/branches")
async def get_branches(
    enterprise_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список филиалов"""
    try:
        query = select(Branch).where(Branch.is_active == True)
        if enterprise_id:
            query = query.where(Branch.enterprise_id == uuid_lib.UUID(enterprise_id))
        
        result = await db.execute(query.order_by(Branch.name))
        branches = result.scalars().all()
        return {"items": [_serialize_branch(b) for b in branches]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get branches: {str(e)}")

@router.post("/branches")
async def create_branch(
    branch_data: BranchCreate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать филиал"""
    await _require_hierarchy_admin(db, username)

    try:
        new_branch = Branch(
            enterprise_id=uuid_lib.UUID(branch_data.enterprise_id),
            name=branch_data.name.strip(),
            code=(branch_data.code or "").strip() or None,
            description=(branch_data.description or "").strip() or None,
        )
        db.add(new_branch)
        await db.commit()
        await db.refresh(new_branch)

        return _serialize_branch(new_branch)
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create branch: {str(e)}") from e


@router.put("/branches/{branch_id}")
async def update_branch(
    branch_id: str,
    branch_data: BranchUpdate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Обновить филиал"""
    await _require_hierarchy_admin(db, username)

    try:
        branch_uuid = uuid_lib.UUID(branch_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Некорректный ID филиала") from exc

    result = await db.execute(select(Branch).where(Branch.id == branch_uuid))
    branch = result.scalar_one_or_none()
    if not branch or not branch.is_active:
        raise HTTPException(status_code=404, detail="Филиал не найден")

    try:
        if branch_data.name is not None:
            name = branch_data.name.strip()
            if not name:
                raise HTTPException(status_code=400, detail="Название не может быть пустым")
            branch.name = name

        if branch_data.code is not None:
            branch.code = branch_data.code.strip() or None

        if branch_data.description is not None:
            branch.description = branch_data.description.strip() or None

        await db.commit()
        await db.refresh(branch)
        return _serialize_branch(branch)
    except HTTPException:
        await db.rollback()
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Не удалось обновить филиал: {e}") from e


@router.delete("/branches/{branch_id}")
async def delete_branch(
    branch_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Деактивировать филиал (мягкое удаление)"""
    await _require_hierarchy_admin(db, username)

    try:
        branch_uuid = uuid_lib.UUID(branch_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Некорректный ID филиала") from exc

    result = await db.execute(select(Branch).where(Branch.id == branch_uuid))
    branch = result.scalar_one_or_none()
    if not branch or not branch.is_active:
        raise HTTPException(status_code=404, detail="Филиал не найден")

    workshops_count = await db.execute(
        select(func.count())
        .select_from(Workshop)
        .where(Workshop.branch_id == branch_uuid, Workshop.is_active == True)
    )
    if (workshops_count.scalar() or 0) > 0:
        raise HTTPException(
            status_code=409,
            detail="Нельзя удалить филиал: сначала удалите или деактивируйте все цеха",
        )

    try:
        branch.is_active = False
        await db.commit()
        return {"message": "Филиал удалён", "id": str(branch.id)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Не удалось удалить филиал: {e}") from e


# Workshop endpoints
@router.get("/workshops")
async def get_workshops(
    branch_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список цехов"""
    try:
        query = select(Workshop).where(Workshop.is_active == True)
        if branch_id:
            query = query.where(Workshop.branch_id == uuid_lib.UUID(branch_id))
        
        result = await db.execute(query.order_by(Workshop.name))
        workshops = result.scalars().all()
        return {"items": [_serialize_workshop(w) for w in workshops]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get workshops: {str(e)}")

@router.post("/workshops")
async def create_workshop(
    workshop_data: WorkshopCreate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Создать цех"""
    await _require_hierarchy_admin(db, username)

    try:
        new_workshop = Workshop(
            branch_id=uuid_lib.UUID(workshop_data.branch_id),
            name=workshop_data.name.strip(),
            code=(workshop_data.code or "").strip() or None,
            description=(workshop_data.description or "").strip() or None,
        )
        db.add(new_workshop)
        await db.commit()
        await db.refresh(new_workshop)

        return _serialize_workshop(new_workshop)
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create workshop: {str(e)}") from e


@router.put("/workshops/{workshop_id}")
async def update_workshop(
    workshop_id: str,
    workshop_data: WorkshopUpdate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Обновить цех"""
    await _require_hierarchy_admin(db, username)

    try:
        workshop_uuid = uuid_lib.UUID(workshop_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Некорректный ID цеха") from exc

    result = await db.execute(select(Workshop).where(Workshop.id == workshop_uuid))
    workshop = result.scalar_one_or_none()
    if not workshop or not workshop.is_active:
        raise HTTPException(status_code=404, detail="Цех не найден")

    try:
        if workshop_data.name is not None:
            name = workshop_data.name.strip()
            if not name:
                raise HTTPException(status_code=400, detail="Название не может быть пустым")
            workshop.name = name

        if workshop_data.code is not None:
            workshop.code = workshop_data.code.strip() or None

        if workshop_data.description is not None:
            workshop.description = workshop_data.description.strip() or None

        await db.commit()
        await db.refresh(workshop)
        return _serialize_workshop(workshop)
    except HTTPException:
        await db.rollback()
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Не удалось обновить цех: {e}") from e


@router.delete("/workshops/{workshop_id}")
async def delete_workshop(
    workshop_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Деактивировать цех (мягкое удаление)"""
    await _require_hierarchy_admin(db, username)

    try:
        workshop_uuid = uuid_lib.UUID(workshop_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Некорректный ID цеха") from exc

    result = await db.execute(select(Workshop).where(Workshop.id == workshop_uuid))
    workshop = result.scalar_one_or_none()
    if not workshop or not workshop.is_active:
        raise HTTPException(status_code=404, detail="Цех не найден")

    equipment_count = await db.execute(
        select(func.count())
        .select_from(Equipment)
        .where(Equipment.workshop_id == workshop_uuid, Equipment.is_active == True)
    )
    if (equipment_count.scalar() or 0) > 0:
        raise HTTPException(
            status_code=409,
            detail="Нельзя удалить цех: сначала удалите всё оборудование в этом цехе",
        )

    try:
        workshop.is_active = False
        await db.commit()
        return {"message": "Цех удалён", "id": str(workshop.id)}
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Не удалось удалить цех: {e}") from e


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


