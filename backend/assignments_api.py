"""
API для работы с заданиями на диагностику/экспертизу оборудования (версия 3.4.0)
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, func, update
from sqlalchemy.orm import selectinload
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime, timezone
import uuid as uuid_lib
import logging

from database import get_db
from models import (
    Assignment,
    Equipment,
    User,
    InspectionHistory,
    Inspection,
    Report,
    Questionnaire,
    HierarchyEngineerAssignment,
    Enterprise,
    Branch,
    Workshop,
    EquipmentType,
    Opo,
)
from auth import verify_token

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/assignments", tags=["assignments"])

# --- Константы валидации ---
VALID_ASSIGNMENT_TYPES = {'DIAGNOSTICS', 'EXPERTISE', 'INSPECTION'}
VALID_STATUSES = {'PENDING', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'}
VALID_PRIORITIES = {'LOW', 'NORMAL', 'HIGH', 'URGENT'}
OPERATOR_ROLES = {'admin', 'chief_operator', 'operator'}


# --- Вспомогательные функции ---
async def _get_current_user(username: str, db: AsyncSession) -> User:
    """Get current user by username/email, raise 404 if not found."""
    result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    return user


async def _check_assignment_access(user: User, assignment: Assignment):
    """Check user has access to assignment. Raises 403 if not."""
    if user.role in OPERATOR_ROLES:
        return
    if user.role == 'engineer' and assignment.assigned_to == user.id:
        return
    raise HTTPException(status_code=403, detail="Нет доступа к этому заданию")


# Pydantic модели
class AssignmentCreate(BaseModel):
    equipment_id: str
    assignment_type: str  # 'DIAGNOSTICS', 'EXPERTISE', 'INSPECTION'
    assigned_to: str
    priority: Optional[str] = 'NORMAL'
    due_date: Optional[str] = None
    description: Optional[str] = None

class AssignmentUpdate(BaseModel):
    status: Optional[str] = None
    priority: Optional[str] = None
    due_date: Optional[str] = None
    description: Optional[str] = None

class AssignmentsStatusSummaryRequest(BaseModel):
    assignment_ids: List[str]

class AssignmentResponse(BaseModel):
    id: str
    equipment_id: str
    equipment_code: str
    equipment_name: str
    assignment_type: str
    assigned_by: Optional[str]
    assigned_to: str
    assigned_to_name: Optional[str]
    status: str
    priority: str
    due_date: Optional[str]
    description: Optional[str]
    created_at: str
    updated_at: Optional[str]
    completed_at: Optional[str]
    enterprise_id: Optional[str] = None
    enterprise_name: Optional[str] = None
    branch_id: Optional[str] = None
    branch_name: Optional[str] = None
    workshop_id: Optional[str] = None
    workshop_name: Optional[str] = None
    opo_id: Optional[str] = None
    opo_name: Optional[str] = None
    opo_code: Optional[str] = None

class ObjectEngineerProgress(BaseModel):
    user_id: str
    username: str
    full_name: Optional[str]
    total: int
    completed: int
    remaining: int
    progress_pct: int

class ObjectAssignmentsProgress(BaseModel):
    object_type: str  # enterprise/branch/workshop/equipment/equipment_type
    object_id: str
    object_name: str
    engineers: List[ObjectEngineerProgress]

@router.post("", response_model=dict)
async def create_assignment(
    assignment_data: AssignmentCreate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать новое задание на диагностику/экспертизу"""
    try:
        user = await _get_current_user(username, db)

        if user.role not in OPERATOR_ROLES:
            raise HTTPException(status_code=403, detail="Недостаточно прав для создания задания")

        # Валидация типа задания
        if assignment_data.assignment_type not in VALID_ASSIGNMENT_TYPES:
            raise HTTPException(
                status_code=400,
                detail=f"Недопустимый тип задания. Допустимые: {', '.join(sorted(VALID_ASSIGNMENT_TYPES))}"
            )

        # Валидация приоритета
        if assignment_data.priority and assignment_data.priority not in VALID_PRIORITIES:
            raise HTTPException(
                status_code=400,
                detail=f"Недопустимый приоритет. Допустимые: {', '.join(sorted(VALID_PRIORITIES))}"
            )

        # Проверяем существование оборудования
        equipment_result = await db.execute(
            select(Equipment).where(Equipment.id == assignment_data.equipment_id)
        )
        equipment = equipment_result.scalar_one_or_none()

        if not equipment:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")

        # Проверяем существование назначенного пользователя
        assigned_user_result = await db.execute(
            select(User).where(User.id == assignment_data.assigned_to)
        )
        assigned_user = assigned_user_result.scalar_one_or_none()

        if not assigned_user:
            raise HTTPException(status_code=404, detail="Пользователь не найден")

        # Задание можно назначить только инженеру
        if assigned_user.role != 'engineer':
            raise HTTPException(status_code=400, detail="Задание можно назначить только инженеру")

        # Проверяем, что инженер имеет доступ к оборудованию через иерархию (предупреждение)
        hierarchy_check = await db.execute(
            select(HierarchyEngineerAssignment).where(
                and_(
                    HierarchyEngineerAssignment.user_id == assigned_user.id,
                    HierarchyEngineerAssignment.is_active == True,
                    or_(
                        HierarchyEngineerAssignment.equipment_id == equipment.id,
                        HierarchyEngineerAssignment.workshop_id == equipment.workshop_id,
                    )
                )
            )
        )
        if not hierarchy_check.scalar_one_or_none():
            logger.warning(
                f"Инженер {assigned_user.id} не имеет назначения в иерархии для оборудования {equipment.id}"
            )

        # Парсим дату
        due_date = None
        if assignment_data.due_date:
            try:
                due_date = datetime.fromisoformat(assignment_data.due_date.replace('Z', '+00:00'))
            except ValueError:
                raise HTTPException(status_code=400, detail="Неверный формат даты. Используйте ISO 8601")

        # Создаем задание
        new_assignment = Assignment(
            equipment_id=uuid_lib.UUID(assignment_data.equipment_id),
            assignment_type=assignment_data.assignment_type,
            assigned_by=user.id,
            assigned_to=uuid_lib.UUID(assignment_data.assigned_to),
            priority=assignment_data.priority,
            due_date=due_date,
            description=assignment_data.description,
            status='PENDING'
        )

        db.add(new_assignment)
        await db.commit()
        await db.refresh(new_assignment)

        try:
            from notifications_api import send_push_notification
            await send_push_notification(
                db=db,
                user_id=assigned_user.id,
                title="Новое задание",
                body=f"Вам назначено задание: {assignment_data.assignment_type}",
                data={"assignment_id": str(new_assignment.id)},
            )
        except Exception as e:
            logger.warning(f"Failed to send push notification: {e}")

        return {
            "id": str(new_assignment.id),
            "status": "created",
            "message": "Задание успешно создано"
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Ошибка при создании задания: {str(e)}")

@router.get("", response_model=List[AssignmentResponse])
async def get_assignments(
    status: Optional[str] = None,
    assigned_to: Optional[str] = None,
    equipment_id: Optional[str] = None,
    enterprise_id: Optional[str] = None,
    branch_id: Optional[str] = None,
    workshop_id: Optional[str] = None,
    include_cancelled: Optional[bool] = True,
    limit: int = 100,
    offset: int = 0,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список заданий с пагинацией и фильтрацией по иерархии.

    - enterprise_id / branch_id / workshop_id — фильтрация по иерархии предприятия
    - limit / offset — пагинация (макс. 1000 записей за запрос)
    - include_cancelled=false скрывает задания со статусом CANCELLED (архив)
    """
    try:
        user = await _get_current_user(username, db)

        query = select(Assignment)

        if user.role == 'engineer':
            query = query.where(Assignment.assigned_to == user.id)
        elif user.role not in OPERATOR_ROLES:
            raise HTTPException(status_code=403, detail="Нет доступа к списку заданий")

        if include_cancelled is False:
            query = query.where(Assignment.status != "CANCELLED")

        filters = []
        if status:
            filters.append(Assignment.status == status)
        if assigned_to:
            filters.append(Assignment.assigned_to == uuid_lib.UUID(assigned_to))
        if equipment_id:
            filters.append(Assignment.equipment_id == uuid_lib.UUID(equipment_id))

        if filters:
            query = query.where(and_(*filters))

        # Фильтрация по иерархии (предприятие → филиал → цех → оборудование)
        if workshop_id:
            equipment_in_workshop = select(Equipment.id).where(
                Equipment.workshop_id == uuid_lib.UUID(workshop_id)
            )
            query = query.where(Assignment.equipment_id.in_(equipment_in_workshop))
        elif branch_id:
            workshops_in_branch = select(Workshop.id).where(
                Workshop.branch_id == uuid_lib.UUID(branch_id)
            )
            equipment_in_branch = select(Equipment.id).where(
                Equipment.workshop_id.in_(workshops_in_branch)
            )
            query = query.where(Assignment.equipment_id.in_(equipment_in_branch))
        elif enterprise_id:
            branches_in_enterprise = select(Branch.id).where(
                Branch.enterprise_id == uuid_lib.UUID(enterprise_id)
            )
            workshops_in_enterprise = select(Workshop.id).where(
                Workshop.branch_id.in_(branches_in_enterprise)
            )
            equipment_in_enterprise = select(Equipment.id).where(
                Equipment.workshop_id.in_(workshops_in_enterprise)
            )
            query = query.where(Assignment.equipment_id.in_(equipment_in_enterprise))

        query = query.order_by(Assignment.created_at.desc())

        # Пагинация (макс. 1000 записей за запрос)
        effective_limit = min(limit, 1000)
        query = query.limit(effective_limit).offset(offset)

        result = await db.execute(query)
        assignments = result.scalars().all()

        # --- Batch-загрузка связанных данных (устранение N+1) ---
        equipment_ids = {a.equipment_id for a in assignments}
        user_ids = {a.assigned_to for a in assignments}

        equip_result = await db.execute(
            select(Equipment).where(Equipment.id.in_(equipment_ids))
        ) if equipment_ids else None
        equipment_map = {eq.id: eq for eq in equip_result.scalars().all()} if equip_result else {}

        user_result = await db.execute(
            select(User).where(User.id.in_(user_ids))
        ) if user_ids else None
        user_map = {u.id: u for u in user_result.scalars().all()} if user_result else {}

        workshop_ids = {eq.workshop_id for eq in equipment_map.values() if eq.workshop_id}
        ws_result = await db.execute(
            select(Workshop).where(Workshop.id.in_(workshop_ids))
        ) if workshop_ids else None
        workshop_map = {w.id: w for w in ws_result.scalars().all()} if ws_result else {}

        branch_ids = {w.branch_id for w in workshop_map.values() if w.branch_id}
        br_result = await db.execute(
            select(Branch).where(Branch.id.in_(branch_ids))
        ) if branch_ids else None
        branch_map = {b.id: b for b in br_result.scalars().all()} if br_result else {}

        enterprise_ids = {b.enterprise_id for b in branch_map.values() if b.enterprise_id}
        ent_result = await db.execute(
            select(Enterprise).where(Enterprise.id.in_(enterprise_ids))
        ) if enterprise_ids else None
        enterprise_map = {e.id: e for e in ent_result.scalars().all()} if ent_result else {}

        opo_ids = {eq.opo_id for eq in equipment_map.values() if getattr(eq, 'opo_id', None)}
        opo_result = await db.execute(
            select(Opo).where(Opo.id.in_(opo_ids))
        ) if opo_ids else None
        opo_map = {o.id: o for o in opo_result.scalars().all()} if opo_result else {}

        # Формируем ответ
        assignments_list = []
        for assignment in assignments:
            equipment = equipment_map.get(assignment.equipment_id)
            assigned_user = user_map.get(assignment.assigned_to)

            workshop = workshop_map.get(equipment.workshop_id) if equipment and equipment.workshop_id else None
            branch = branch_map.get(workshop.branch_id) if workshop and workshop.branch_id else None
            enterprise = enterprise_map.get(branch.enterprise_id) if branch and branch.enterprise_id else None
            opo = opo_map.get(equipment.opo_id) if equipment and getattr(equipment, 'opo_id', None) else None

            assignments_list.append({
                "id": str(assignment.id),
                "equipment_id": str(assignment.equipment_id),
                "equipment_code": getattr(equipment, "equipment_code", None) if equipment else "N/A",
                "equipment_name": equipment.name if equipment else "N/A",
                "assignment_type": getattr(assignment, "assignment_type", None) or "DIAGNOSTICS",
                "assigned_by": str(assignment.assigned_by) if assignment.assigned_by else None,
                "assigned_to": str(assignment.assigned_to),
                "assigned_to_name": assigned_user.full_name if assigned_user else None,
                "status": assignment.status,
                "priority": assignment.priority,
                "due_date": assignment.due_date.isoformat() if assignment.due_date else None,
                "description": assignment.description,
                "created_at": assignment.created_at.isoformat() if assignment.created_at else None,
                "updated_at": assignment.updated_at.isoformat() if assignment.updated_at else None,
                "completed_at": (lambda t: t.isoformat() if t else None)(getattr(assignment, "completed_at", None)),
                "enterprise_id": str(enterprise.id) if enterprise else None,
                "enterprise_name": enterprise.name if enterprise else None,
                "branch_id": str(branch.id) if branch else None,
                "branch_name": branch.name if branch else None,
                "workshop_id": str(workshop.id) if workshop else None,
                "workshop_name": workshop.name if workshop else None,
                "opo_id": str(opo.id) if opo else None,
                "opo_name": opo.name if opo else None,
                "opo_code": opo.code if opo else None,
            })

        return assignments_list

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        logger.error(f"Error in get_assignments: {error_detail}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка при получении заданий: {error_detail}")


@router.get("/sync", response_model=List[AssignmentResponse])
async def get_assignments_sync(
    since: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Дельта-синхронизация заданий для мобильного приложения.

    Возвращает задания, изменённые после указанного timestamp (ISO 8601).
    Если since не указан — возвращает все задания пользователя.
    """
    try:
        user = await _get_current_user(username, db)

        query = select(Assignment)

        if user.role == 'engineer':
            query = query.where(Assignment.assigned_to == user.id)
        elif user.role not in OPERATOR_ROLES:
            raise HTTPException(status_code=403, detail="Нет доступа к списку заданий")

        if since:
            try:
                since_dt = datetime.fromisoformat(since.replace('Z', '+00:00'))
            except ValueError:
                raise HTTPException(
                    status_code=400,
                    detail="Неверный формат параметра 'since'. Используйте ISO 8601 (напр. 2025-01-01T00:00:00Z)"
                )
            query = query.where(
                or_(
                    Assignment.updated_at > since_dt,
                    Assignment.created_at > since_dt,
                )
            )

        query = query.order_by(Assignment.created_at.desc()).limit(1000)

        result = await db.execute(query)
        assignments = result.scalars().all()

        if not assignments:
            return []

        # Batch-загрузка связанных данных
        equipment_ids = {a.equipment_id for a in assignments}
        user_ids = {a.assigned_to for a in assignments}

        equip_result = await db.execute(
            select(Equipment).where(Equipment.id.in_(equipment_ids))
        ) if equipment_ids else None
        equipment_map = {eq.id: eq for eq in equip_result.scalars().all()} if equip_result else {}

        user_result = await db.execute(
            select(User).where(User.id.in_(user_ids))
        ) if user_ids else None
        user_map = {u.id: u for u in user_result.scalars().all()} if user_result else {}

        workshop_ids = {eq.workshop_id for eq in equipment_map.values() if eq.workshop_id}
        ws_result = await db.execute(
            select(Workshop).where(Workshop.id.in_(workshop_ids))
        ) if workshop_ids else None
        workshop_map = {w.id: w for w in ws_result.scalars().all()} if ws_result else {}

        branch_ids = {w.branch_id for w in workshop_map.values() if w.branch_id}
        br_result = await db.execute(
            select(Branch).where(Branch.id.in_(branch_ids))
        ) if branch_ids else None
        branch_map = {b.id: b for b in br_result.scalars().all()} if br_result else {}

        enterprise_ids = {b.enterprise_id for b in branch_map.values() if b.enterprise_id}
        ent_result = await db.execute(
            select(Enterprise).where(Enterprise.id.in_(enterprise_ids))
        ) if enterprise_ids else None
        enterprise_map = {e.id: e for e in ent_result.scalars().all()} if ent_result else {}

        opo_ids = {eq.opo_id for eq in equipment_map.values() if getattr(eq, 'opo_id', None)}
        opo_result = await db.execute(
            select(Opo).where(Opo.id.in_(opo_ids))
        ) if opo_ids else None
        opo_map = {o.id: o for o in opo_result.scalars().all()} if opo_result else {}

        assignments_list = []
        for assignment in assignments:
            equipment = equipment_map.get(assignment.equipment_id)
            assigned_user = user_map.get(assignment.assigned_to)

            workshop = workshop_map.get(equipment.workshop_id) if equipment and equipment.workshop_id else None
            branch = branch_map.get(workshop.branch_id) if workshop and workshop.branch_id else None
            enterprise = enterprise_map.get(branch.enterprise_id) if branch and branch.enterprise_id else None
            opo = opo_map.get(equipment.opo_id) if equipment and getattr(equipment, 'opo_id', None) else None

            assignments_list.append({
                "id": str(assignment.id),
                "equipment_id": str(assignment.equipment_id),
                "equipment_code": getattr(equipment, "equipment_code", None) if equipment else "N/A",
                "equipment_name": equipment.name if equipment else "N/A",
                "assignment_type": getattr(assignment, "assignment_type", None) or "DIAGNOSTICS",
                "assigned_by": str(assignment.assigned_by) if assignment.assigned_by else None,
                "assigned_to": str(assignment.assigned_to),
                "assigned_to_name": assigned_user.full_name if assigned_user else None,
                "status": assignment.status,
                "priority": assignment.priority,
                "due_date": assignment.due_date.isoformat() if assignment.due_date else None,
                "description": assignment.description,
                "created_at": assignment.created_at.isoformat() if assignment.created_at else None,
                "updated_at": assignment.updated_at.isoformat() if assignment.updated_at else None,
                "completed_at": (lambda t: t.isoformat() if t else None)(getattr(assignment, "completed_at", None)),
                "enterprise_id": str(enterprise.id) if enterprise else None,
                "enterprise_name": enterprise.name if enterprise else None,
                "branch_id": str(branch.id) if branch else None,
                "branch_name": branch.name if branch else None,
                "workshop_id": str(workshop.id) if workshop else None,
                "workshop_name": workshop.name if workshop else None,
                "opo_id": str(opo.id) if opo else None,
                "opo_name": opo.name if opo else None,
                "opo_code": opo.code if opo else None,
            })

        return assignments_list

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in get_assignments_sync: {e}")
        raise HTTPException(status_code=500, detail=f"Ошибка дельта-синхронизации заданий: {str(e)}")


@router.get("/{assignment_id}", response_model=AssignmentResponse)
async def get_assignment(
    assignment_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить задание по ID"""
    try:
        user = await _get_current_user(username, db)

        result = await db.execute(
            select(Assignment).where(Assignment.id == assignment_id)
        )
        assignment = result.scalar_one_or_none()

        if not assignment:
            raise HTTPException(status_code=404, detail="Задание не найдено")

        await _check_assignment_access(user, assignment)

        # Получаем информацию об оборудовании
        equipment_result = await db.execute(
            select(Equipment).where(Equipment.id == assignment.equipment_id)
        )
        equipment = equipment_result.scalar_one_or_none()

        # Получаем информацию о назначенном пользователе
        assigned_user_result = await db.execute(
            select(User).where(User.id == assignment.assigned_to)
        )
        assigned_user = assigned_user_result.scalar_one_or_none()

        return {
            "id": str(assignment.id),
            "equipment_id": str(assignment.equipment_id),
            "equipment_code": getattr(equipment, "equipment_code", None) if equipment else "N/A",
            "equipment_name": equipment.name if equipment else "N/A",
            "assignment_type": getattr(assignment, "assignment_type", None) or "DIAGNOSTICS",
            "assigned_by": str(assignment.assigned_by) if assignment.assigned_by else None,
            "assigned_to": str(assignment.assigned_to),
            "assigned_to_name": assigned_user.full_name if assigned_user else None,
            "status": assignment.status,
            "priority": assignment.priority,
            "due_date": assignment.due_date.isoformat() if assignment.due_date else None,
            "description": assignment.description,
            "created_at": assignment.created_at.isoformat() if assignment.created_at else None,
            "updated_at": assignment.updated_at.isoformat() if assignment.updated_at else None,
            "completed_at": (lambda t: t.isoformat() if t else None)(getattr(assignment, "completed_at", None)),
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Ошибка при получении задания: {str(e)}")

@router.put("/{assignment_id}", response_model=dict)
async def update_assignment(
    assignment_id: str,
    assignment_data: AssignmentUpdate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Обновить задание"""
    try:
        user = await _get_current_user(username, db)

        result = await db.execute(
            select(Assignment).where(Assignment.id == assignment_id)
        )
        assignment = result.scalar_one_or_none()

        if not assignment:
            raise HTTPException(status_code=404, detail="Задание не найдено")

        await _check_assignment_access(user, assignment)

        # Валидация статуса
        if assignment_data.status and assignment_data.status not in VALID_STATUSES:
            raise HTTPException(
                status_code=400,
                detail=f"Недопустимый статус. Допустимые: {', '.join(sorted(VALID_STATUSES))}"
            )

        # Валидация приоритета
        if assignment_data.priority and assignment_data.priority not in VALID_PRIORITIES:
            raise HTTPException(
                status_code=400,
                detail=f"Недопустимый приоритет. Допустимые: {', '.join(sorted(VALID_PRIORITIES))}"
            )

        # Обновляем поля
        if assignment_data.status:
            assignment.status = assignment_data.status
            if assignment_data.status == 'COMPLETED':
                assignment.completed_at = datetime.now(timezone.utc)

        if assignment_data.priority:
            assignment.priority = assignment_data.priority

        if assignment_data.due_date:
            try:
                assignment.due_date = datetime.fromisoformat(assignment_data.due_date.replace('Z', '+00:00'))
            except ValueError:
                raise HTTPException(status_code=400, detail="Неверный формат даты. Используйте ISO 8601")

        if assignment_data.description is not None:
            assignment.description = assignment_data.description

        assignment.updated_at = datetime.now(timezone.utc)

        await db.commit()
        await db.refresh(assignment)

        return {
            "id": str(assignment.id),
            "status": "updated",
            "message": "Задание успешно обновлено"
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Ошибка при обновлении задания: {str(e)}")


@router.patch("/{assignment_id}/archive")
async def archive_assignment(
    assignment_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Перенести задание в архив (статус CANCELLED)."""
    try:
        user = await _get_current_user(username, db)

        result = await db.execute(select(Assignment).where(Assignment.id == assignment_id))
        assignment = result.scalar_one_or_none()
        if not assignment:
            raise HTTPException(status_code=404, detail="Задание не найдено")

        await _check_assignment_access(user, assignment)

        assignment.status = "CANCELLED"
        assignment.updated_at = datetime.now(timezone.utc)
        await db.commit()
        return {"status": "ok", "message": "Задание перенесено в архив", "id": assignment_id}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Ошибка при архивации: {str(e)}")


@router.delete("/{assignment_id}")
async def delete_assignment(
    assignment_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Удалить задание. Связи обследований и опросников с заданием обнуляются."""
    try:
        user = await _get_current_user(username, db)

        # Удаление — только для операторов/админов
        if user.role not in OPERATOR_ROLES:
            raise HTTPException(status_code=403, detail="Недостаточно прав для удаления задания")

        assignment_uuid = uuid_lib.UUID(assignment_id)
        result = await db.execute(select(Assignment).where(Assignment.id == assignment_uuid))
        assignment = result.scalar_one_or_none()
        if not assignment:
            raise HTTPException(status_code=404, detail="Задание не найдено")
        await db.execute(update(Inspection).where(Inspection.assignment_id == assignment_uuid).values(assignment_id=None))
        await db.execute(update(Questionnaire).where(Questionnaire.assignment_id == assignment_uuid).values(assignment_id=None))
        await db.execute(update(InspectionHistory).where(InspectionHistory.assignment_id == assignment_uuid).values(assignment_id=None))
        await db.flush()
        await db.delete(assignment)
        await db.commit()
        return {"status": "deleted", "id": assignment_id}
    except HTTPException:
        raise
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID")
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Ошибка при удалении задания: {str(e)}")


@router.get("/{assignment_id}/inspection", response_model=dict)
async def get_assignment_inspection(
    assignment_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить чек-лист (inspection) по заданию"""
    try:
        user = await _get_current_user(username, db)

        assignment_uuid = uuid_lib.UUID(assignment_id)

        # Проверяем существование задания
        assignment_result = await db.execute(
            select(Assignment).where(Assignment.id == assignment_uuid)
        )
        assignment = assignment_result.scalar_one_or_none()

        if not assignment:
            raise HTTPException(status_code=404, detail="Задание не найдено")

        await _check_assignment_access(user, assignment)

        # Сначала ищем Inspection напрямую по assignment_id (если есть)
        inspection = None
        insp_result = await db.execute(
            select(Inspection)
            .where(Inspection.assignment_id == assignment_uuid)
            .order_by(Inspection.created_at.desc())
            .limit(1)
        )
        inspection = insp_result.scalars().first()

        # Ищем последнюю запись inspection_history по assignment_id (может быть несколько)
        history_result = await db.execute(
            select(InspectionHistory)
            .where(InspectionHistory.assignment_id == assignment_uuid)
            .order_by(InspectionHistory.inspection_date.desc())
            .limit(1)
        )
        history_entry = history_result.scalars().first()

        if not inspection and not history_entry:
            raise HTTPException(status_code=404, detail="Чек-лист для этого задания не найден")

        # Если Inspection не нашли по assignment_id, ищем по equipment_id и дате (по history_entry)
        if not inspection and history_entry:
            inspection_result = await db.execute(
                select(Inspection)
                .where(Inspection.equipment_id == assignment.equipment_id)
                .order_by(Inspection.created_at.desc())
                .limit(20)
            )
            inspections = inspection_result.scalars().all()
            history_time = history_entry.created_at or history_entry.inspection_date
            for insp in inspections:
                insp_time = insp.created_at or insp.date_performed
                if insp_time and history_time:
                    time_diff = abs((insp_time - history_time).total_seconds())
                    if time_diff < 300:  # 5 минут
                        inspection = insp
                        break
            if not inspection and inspections:
                inspection = inspections[0]

        # Если нашли Inspection, возвращаем его данные
        if inspection:
            return {
                "inspection_id": str(inspection.id),
                "inspection_history_id": str(history_entry.id) if history_entry else None,
                "equipment_id": str(inspection.equipment_id),
                "date_performed": inspection.date_performed.isoformat() if inspection.date_performed else None,
                "data": inspection.data or {},
                "conclusion": inspection.conclusion,
                "status": inspection.status,
                "created_at": inspection.created_at.isoformat() if inspection.created_at else None,
            }
        # Иначе возвращаем данные из InspectionHistory (если есть)
        if history_entry:
            return {
                "inspection_id": None,
                "inspection_history_id": str(history_entry.id),
                "equipment_id": str(history_entry.equipment_id),
                "date_performed": history_entry.inspection_date.isoformat() if history_entry.inspection_date else None,
                "data": history_entry.data or {},
                "conclusion": history_entry.conclusion,
                "status": history_entry.status,
                "created_at": history_entry.created_at.isoformat() if history_entry.created_at else None,
            }
        raise HTTPException(status_code=404, detail="Чек-лист для этого задания не найден")

    except HTTPException:
        raise
    except ValueError:
        raise HTTPException(status_code=400, detail="Неверный формат ID задания")
    except Exception as e:
        import traceback
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка при получении чек-листа: {str(e)}")


@router.post("/status-summary", response_model=dict)
async def get_assignments_status_summary(
    request: AssignmentsStatusSummaryRequest,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Сводка по заданиям для веб-интерфейса:
    - есть ли данные по заданию на сервере (InspectionHistory)
    - удалось ли сопоставить Inspection
    - есть ли сгенерированный отчет (Report)
    """
    try:
        ids: List[str] = request.assignment_ids or []
        if not ids:
            return {}

        # Валидация UUID
        uuids: List[uuid_lib.UUID] = []
        for s in ids:
            try:
                uuids.append(uuid_lib.UUID(str(s)))
            except Exception:
                continue

        if not uuids:
            return {}

        # Загружаем задания пачкой
        ass_res = await db.execute(select(Assignment).where(Assignment.id.in_(uuids)))
        assignments = ass_res.scalars().all()
        assignments_map = {str(a.id): a for a in assignments}

        # Загружаем последние записи истории по assignment_id
        hist_res = await db.execute(
            select(InspectionHistory)
            .where(InspectionHistory.assignment_id.in_(uuids))
            .order_by(InspectionHistory.assignment_id, InspectionHistory.inspection_date.desc())
        )
        histories = hist_res.scalars().all()

        latest_history: dict[str, InspectionHistory] = {}
        for h in histories:
            key = str(h.assignment_id) if h.assignment_id else None
            if not key or key in latest_history:
                continue
            latest_history[key] = h

        result: dict[str, dict] = {}

        for a_id, a in assignments_map.items():
            h = latest_history.get(a_id)
            has_history = h is not None

            inspection = None
            has_inspection = False
            report = None
            has_report = False

            # Эвристика: сопоставляем Inspection по equipment_id и времени, близкому к истории
            if has_history and a.equipment_id:
                insp_res = await db.execute(
                    select(Inspection)
                    .where(Inspection.equipment_id == a.equipment_id)
                    .order_by(Inspection.created_at.desc())
                    .limit(10)
                )
                insp_list = insp_res.scalars().all()
                if insp_list:
                    history_time = getattr(h, "created_at", None) or getattr(h, "inspection_date", None)
                    best = insp_list[0]
                    best_diff = None
                    if history_time:
                        for insp in insp_list:
                            insp_time = getattr(insp, "created_at", None) or getattr(insp, "date_performed", None)
                            if not insp_time:
                                continue
                            diff = abs((insp_time - history_time).total_seconds())
                            if best_diff is None or diff < best_diff:
                                best = insp
                                best_diff = diff
                    inspection = best

            if inspection is not None:
                has_inspection = True
                rep_res = await db.execute(
                    select(Report)
                    .where(Report.inspection_id == inspection.id)
                    .order_by(Report.created_at.desc())
                    .limit(1)
                )
                report = rep_res.scalar_one_or_none()
                has_report = report is not None

            result[a_id] = {
                "has_history": has_history,
                "has_inspection": has_inspection,
                "has_report": has_report,
                "inspection_id": str(inspection.id) if inspection is not None else None,
                "report_id": str(report.id) if report is not None else None,
                "report_file_path": report.file_path if report is not None else None,
            }

        return result

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Ошибка сводки по заданиям: {str(e)}")

@router.get("/{assignment_id}/equipment", response_model=dict)
async def get_assignment_equipment(
    assignment_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить информацию об оборудовании из задания (для мобильного приложения)"""
    try:
        user = await _get_current_user(username, db)

        result = await db.execute(
            select(Assignment).where(Assignment.id == assignment_id)
        )
        assignment = result.scalar_one_or_none()

        if not assignment:
            raise HTTPException(status_code=404, detail="Задание не найдено")

        await _check_assignment_access(user, assignment)

        # Получаем информацию об оборудовании
        equipment_result = await db.execute(
            select(Equipment).where(Equipment.id == assignment.equipment_id)
        )
        equipment = equipment_result.scalar_one_or_none()

        if not equipment:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")

        # Получаем информацию о цехе, филиале и предприятии
        workshop_name = None
        branch_name = None
        enterprise_name = None

        if equipment.workshop_id:
            workshop_result = await db.execute(
                select(Workshop).where(Workshop.id == equipment.workshop_id)
            )
            workshop = workshop_result.scalar_one_or_none()
            if workshop:
                workshop_name = workshop.name
                if workshop.branch_id:
                    branch_result = await db.execute(
                        select(Branch).where(Branch.id == workshop.branch_id)
                    )
                    branch = branch_result.scalar_one_or_none()
                    if branch:
                        branch_name = branch.name
                        if branch.enterprise_id:
                            enterprise_result = await db.execute(
                                select(Enterprise).where(Enterprise.id == branch.enterprise_id)
                            )
                            enterprise = enterprise_result.scalar_one_or_none()
                            if enterprise:
                                enterprise_name = enterprise.name

        return {
            "id": str(equipment.id),
            "equipment_code": getattr(equipment, "equipment_code", None) or "N/A",
            "name": equipment.name,
            "type_id": str(equipment.type_id) if equipment.type_id else None,
            "serial_number": equipment.serial_number,
            "location": equipment.location,
            "workshop_id": str(equipment.workshop_id) if equipment.workshop_id else None,
            "workshop_name": workshop_name,
            "branch_name": branch_name,
            "enterprise_name": enterprise_name,
            "attributes": equipment.attributes or {},
            "commissioning_date": str(equipment.commissioning_date) if equipment.commissioning_date else None,
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Ошибка при получении оборудования: {str(e)}")

@router.get("/statistics/engineers")
async def get_assignments_statistics_by_engineers(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить статистику по заданиям для каждого инженера"""
    try:
        user = await _get_current_user(username, db)

        if user.role not in OPERATOR_ROLES:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        # Получаем всех инженеров
        engineers_result = await db.execute(
            select(User).where(User.role == 'engineer', User.is_active == True)
        )
        engineers = engineers_result.scalars().all()

        statistics = []
        for engineer in engineers:
            # Получаем все задания для инженера
            assignments_result = await db.execute(
                select(Assignment).where(Assignment.assigned_to == engineer.id)
            )
            all_assignments = assignments_result.scalars().all()

            total = len(all_assignments)
            pending = len([a for a in all_assignments if a.status == 'PENDING'])
            in_progress = len([a for a in all_assignments if a.status == 'IN_PROGRESS'])
            completed = len([a for a in all_assignments if a.status == 'COMPLETED'])
            cancelled = len([a for a in all_assignments if a.status == 'CANCELLED'])

            statistics.append({
                "engineer_id": str(engineer.id),
                "engineer_name": engineer.full_name or engineer.username,
                "username": engineer.username,
                "email": engineer.email,
                "total": total,
                "pending": pending,
                "in_progress": in_progress,
                "completed": completed,
                "cancelled": cancelled,
            })

        return {
            "items": statistics,
            "total_engineers": len(statistics)
        }

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        logger.error(f"Error in get_assignments_statistics_by_engineers: {error_detail}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка при получении статистики: {error_detail}")


@router.get("/statistics/objects", response_model=dict)
async def get_assignments_progress_by_objects(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """
    Сводка для оператора: какие инженеры назначены на какой объект (предприятие/филиал/цех/тип/оборудование)
    + прогресс по заданиям (COMPLETED / TOTAL) внутри этого объекта.
    """
    try:
        user = await _get_current_user(username, db)

        if user.role not in OPERATOR_ROLES:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        now = datetime.now(timezone.utc)

        # Берем активные назначения инженеров по иерархии
        ha_result = await db.execute(
            select(HierarchyEngineerAssignment, User).join(
                User, HierarchyEngineerAssignment.user_id == User.id
            ).where(
                and_(
                    HierarchyEngineerAssignment.is_active == True,
                    or_(
                        HierarchyEngineerAssignment.expires_at.is_(None),
                        HierarchyEngineerAssignment.expires_at > now
                    )
                )
            )
        )
        rows = ha_result.all()

        # Кэш имен объектов
        enterprise_name_cache: dict[str, str] = {}
        branch_name_cache: dict[str, str] = {}
        workshop_name_cache: dict[str, str] = {}
        equipment_name_cache: dict[str, str] = {}
        equipment_type_name_cache: dict[str, str] = {}

        async def _get_enterprise_name(eid: uuid_lib.UUID) -> str:
            key = str(eid)
            if key in enterprise_name_cache:
                return enterprise_name_cache[key]
            r = await db.execute(select(Enterprise).where(Enterprise.id == eid))
            e = r.scalar_one_or_none()
            enterprise_name_cache[key] = e.name if e else key
            return enterprise_name_cache[key]

        async def _get_branch_name(bid: uuid_lib.UUID) -> str:
            key = str(bid)
            if key in branch_name_cache:
                return branch_name_cache[key]
            r = await db.execute(select(Branch).where(Branch.id == bid))
            b = r.scalar_one_or_none()
            branch_name_cache[key] = b.name if b else key
            return branch_name_cache[key]

        async def _get_workshop_name(wid: uuid_lib.UUID) -> str:
            key = str(wid)
            if key in workshop_name_cache:
                return workshop_name_cache[key]
            r = await db.execute(select(Workshop).where(Workshop.id == wid))
            w = r.scalar_one_or_none()
            workshop_name_cache[key] = w.name if w else key
            return workshop_name_cache[key]

        async def _get_equipment_name(eqid: uuid_lib.UUID) -> str:
            key = str(eqid)
            if key in equipment_name_cache:
                return equipment_name_cache[key]
            r = await db.execute(select(Equipment).where(Equipment.id == eqid))
            eq = r.scalar_one_or_none()
            equipment_name_cache[key] = eq.name if eq else key
            return equipment_name_cache[key]

        async def _get_equipment_type_name(tid: uuid_lib.UUID) -> str:
            key = str(tid)
            if key in equipment_type_name_cache:
                return equipment_type_name_cache[key]
            r = await db.execute(select(EquipmentType).where(EquipmentType.id == tid))
            t = r.scalar_one_or_none()
            equipment_type_name_cache[key] = t.name if t else key
            return equipment_type_name_cache[key]

        async def _equipment_ids_for_object(object_type: str, object_uuid: uuid_lib.UUID) -> List[uuid_lib.UUID]:
            if object_type == "equipment":
                return [object_uuid]
            if object_type == "workshop":
                r = await db.execute(select(Equipment.id).where(Equipment.workshop_id == object_uuid))
                return [x[0] for x in r.all()]
            if object_type == "branch":
                wr = await db.execute(select(Workshop.id).where(Workshop.branch_id == object_uuid))
                wids = [x[0] for x in wr.all()]
                if not wids:
                    return []
                er = await db.execute(select(Equipment.id).where(Equipment.workshop_id.in_(wids)))
                return [x[0] for x in er.all()]
            if object_type == "enterprise":
                br = await db.execute(select(Branch.id).where(Branch.enterprise_id == object_uuid))
                bids = [x[0] for x in br.all()]
                if not bids:
                    return []
                wr = await db.execute(select(Workshop.id).where(Workshop.branch_id.in_(bids)))
                wids = [x[0] for x in wr.all()]
                if not wids:
                    return []
                er = await db.execute(select(Equipment.id).where(Equipment.workshop_id.in_(wids)))
                return [x[0] for x in er.all()]
            if object_type == "equipment_type":
                r = await db.execute(select(Equipment.id).where(Equipment.type_id == object_uuid))
                return [x[0] for x in r.all()]
            return []

        objects_map: dict[tuple[str, str], dict] = {}

        for ha, engineer in rows:
            object_type = None
            object_uuid = None
            object_name = None

            if ha.equipment_id:
                object_type = "equipment"
                object_uuid = ha.equipment_id
                object_name = await _get_equipment_name(object_uuid)
            elif ha.workshop_id:
                object_type = "workshop"
                object_uuid = ha.workshop_id
                object_name = await _get_workshop_name(object_uuid)
            elif ha.branch_id:
                object_type = "branch"
                object_uuid = ha.branch_id
                object_name = await _get_branch_name(object_uuid)
            elif ha.enterprise_id:
                object_type = "enterprise"
                object_uuid = ha.enterprise_id
                object_name = await _get_enterprise_name(object_uuid)
            elif ha.equipment_type_id:
                object_type = "equipment_type"
                object_uuid = ha.equipment_type_id
                object_name = await _get_equipment_type_name(object_uuid)
            else:
                continue

            key = (object_type, str(object_uuid))
            if key not in objects_map:
                objects_map[key] = {
                    "object_type": object_type,
                    "object_id": str(object_uuid),
                    "object_name": object_name or str(object_uuid),
                    "engineers_map": {}
                }

            equipment_ids = await _equipment_ids_for_object(object_type, object_uuid)
            if not equipment_ids:
                total = 0
                completed = 0
            else:
                total_result = await db.execute(
                    select(func.count()).select_from(Assignment).where(
                        and_(
                            Assignment.assigned_to == engineer.id,
                            Assignment.equipment_id.in_(equipment_ids),
                            Assignment.status != "CANCELLED"
                        )
                    )
                )
                total = int(total_result.scalar() or 0)

                completed_result = await db.execute(
                    select(func.count()).select_from(Assignment).where(
                        and_(
                            Assignment.assigned_to == engineer.id,
                            Assignment.equipment_id.in_(equipment_ids),
                            Assignment.status == "COMPLETED"
                        )
                    )
                )
                completed = int(completed_result.scalar() or 0)

            remaining = max(total - completed, 0)
            pct = int((completed / total) * 100) if total > 0 else 0

            objects_map[key]["engineers_map"][str(engineer.id)] = {
                "user_id": str(engineer.id),
                "username": engineer.username,
                "full_name": engineer.full_name,
                "total": total,
                "completed": completed,
                "remaining": remaining,
                "progress_pct": pct,
            }

        items: List[dict] = []
        for (_, _), v in objects_map.items():
            engineers_list = list(v["engineers_map"].values())
            engineers_list.sort(key=lambda x: (x.get("full_name") or x.get("username") or ""))
            items.append(
                {
                    "object_type": v["object_type"],
                    "object_id": v["object_id"],
                    "object_name": v["object_name"],
                    "engineers": engineers_list,
                }
            )

        items.sort(key=lambda x: (x["object_type"], x["object_name"]))
        return {"items": items, "total": len(items)}

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка статистики по объектам: {str(e)}")
