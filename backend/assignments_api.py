"""
API для работы с заданиями на диагностику/экспертизу оборудования (версия 3.3.0)
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, func
from sqlalchemy.orm import selectinload
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime
import uuid as uuid_lib

from database import get_db
from models import (
    Assignment,
    Equipment,
    User,
    InspectionHistory,
    HierarchyEngineerAssignment,
    Enterprise,
    Branch,
    Workshop,
    EquipmentType,
)
from auth import verify_token

router = APIRouter(prefix="/api/assignments", tags=["assignments"])

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
        # Проверяем права доступа (только операторы и выше)
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        
        if not user or user.role not in ['admin', 'chief_operator', 'operator']:
            raise HTTPException(status_code=403, detail="Недостаточно прав для создания задания")
        
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
        
        # Парсим дату
        due_date = None
        if assignment_data.due_date:
            try:
                due_date = datetime.fromisoformat(assignment_data.due_date.replace('Z', '+00:00'))
            except:
                pass
        
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
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить список заданий"""
    try:
        # Получаем информацию о пользователе
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        
        if not user:
            raise HTTPException(status_code=404, detail="Пользователь не найден")
        
        # Формируем запрос
        query = select(Assignment)
        
        # Фильтруем по назначенному пользователю (для инженеров)
        if user.role == 'engineer':
            query = query.where(Assignment.assigned_to == user.id)
        
        # Дополнительные фильтры
        filters = []
        if status:
            filters.append(Assignment.status == status)
        if assigned_to:
            filters.append(Assignment.assigned_to == uuid_lib.UUID(assigned_to))
        if equipment_id:
            filters.append(Assignment.equipment_id == uuid_lib.UUID(equipment_id))
        
        if filters:
            query = query.where(and_(*filters))
        
        # Сортируем по дате создания (новые первые)
        query = query.order_by(Assignment.created_at.desc())
        
        result = await db.execute(query)
        assignments = result.scalars().all()
        
        # Формируем ответ
        assignments_list = []
        for assignment in assignments:
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
            
            # Получаем информацию об иерархии (предприятие, филиал, цех)
            enterprise_name = None
            branch_name = None
            workshop_name = None
            enterprise_id = None
            branch_id = None
            workshop_id = None
            
            if equipment:
                # Проверяем workshop_id у оборудования
                if equipment.workshop_id:
                    try:
                        workshop_result = await db.execute(
                            select(Workshop).where(Workshop.id == equipment.workshop_id)
                        )
                        workshop = workshop_result.scalar_one_or_none()
                        if workshop:
                            workshop_name = workshop.name
                            workshop_id = str(workshop.id)
                            if workshop.branch_id:
                                try:
                                    branch_result = await db.execute(
                                        select(Branch).where(Branch.id == workshop.branch_id)
                                    )
                                    branch = branch_result.scalar_one_or_none()
                                    if branch:
                                        branch_name = branch.name
                                        branch_id = str(branch.id)
                                        if branch.enterprise_id:
                                            try:
                                                enterprise_result = await db.execute(
                                                    select(Enterprise).where(Enterprise.id == branch.enterprise_id)
                                                )
                                                enterprise = enterprise_result.scalar_one_or_none()
                                                if enterprise:
                                                    enterprise_name = enterprise.name
                                                    enterprise_id = str(enterprise.id)
                                            except Exception as e:
                                                print(f"⚠️ Error loading enterprise for assignment {assignment.id}: {e}")
                                except Exception as e:
                                    print(f"⚠️ Error loading branch for assignment {assignment.id}: {e}")
                    except Exception as e:
                        print(f"⚠️ Error loading workshop for assignment {assignment.id}: {e}")
                else:
                    # Если у оборудования нет workshop_id, логируем для отладки
                    print(f"⚠️ Equipment {equipment.id} ({equipment.equipment_code}) has no workshop_id")
            
            assignments_list.append({
                "id": str(assignment.id),
                "equipment_id": str(assignment.equipment_id),
                "equipment_code": equipment.equipment_code if equipment else "N/A",
                "equipment_name": equipment.name if equipment else "N/A",
                "assignment_type": assignment.assignment_type,
                "assigned_by": str(assignment.assigned_by) if assignment.assigned_by else None,
                "assigned_to": str(assignment.assigned_to),
                "assigned_to_name": assigned_user.full_name if assigned_user else None,
                "status": assignment.status,
                "priority": assignment.priority,
                "due_date": assignment.due_date.isoformat() if assignment.due_date else None,
                "description": assignment.description,
                "created_at": assignment.created_at.isoformat() if assignment.created_at else None,
                "updated_at": assignment.updated_at.isoformat() if assignment.updated_at else None,
                "completed_at": assignment.completed_at.isoformat() if assignment.completed_at else None,
                "enterprise_id": enterprise_id,
                "enterprise_name": enterprise_name,
                "branch_id": branch_id,
                "branch_name": branch_name,
                "workshop_id": workshop_id,
                "workshop_name": workshop_name,
            })
        
        return assignments_list
        
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_detail = str(e)
        print(f"❌ Error in get_assignments: {error_detail}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка при получении заданий: {error_detail}")

@router.get("/{assignment_id}", response_model=AssignmentResponse)
async def get_assignment(
    assignment_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить задание по ID"""
    try:
        result = await db.execute(
            select(Assignment).where(Assignment.id == assignment_id)
        )
        assignment = result.scalar_one_or_none()
        
        if not assignment:
            raise HTTPException(status_code=404, detail="Задание не найдено")
        
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
            "equipment_code": equipment.equipment_code if equipment else "N/A",
            "equipment_name": equipment.name if equipment else "N/A",
            "assignment_type": assignment.assignment_type,
            "assigned_by": str(assignment.assigned_by) if assignment.assigned_by else None,
            "assigned_to": str(assignment.assigned_to),
            "assigned_to_name": assigned_user.full_name if assigned_user else None,
            "status": assignment.status,
            "priority": assignment.priority,
            "due_date": assignment.due_date.isoformat() if assignment.due_date else None,
            "description": assignment.description,
            "created_at": assignment.created_at.isoformat() if assignment.created_at else None,
            "updated_at": assignment.updated_at.isoformat() if assignment.updated_at else None,
            "completed_at": assignment.completed_at.isoformat() if assignment.completed_at else None,
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
        result = await db.execute(
            select(Assignment).where(Assignment.id == assignment_id)
        )
        assignment = result.scalar_one_or_none()
        
        if not assignment:
            raise HTTPException(status_code=404, detail="Задание не найдено")
        
        # Обновляем поля
        if assignment_data.status:
            assignment.status = assignment_data.status
            if assignment_data.status == 'COMPLETED':
                assignment.completed_at = datetime.now()
        
        if assignment_data.priority:
            assignment.priority = assignment_data.priority
        
        if assignment_data.due_date:
            try:
                assignment.due_date = datetime.fromisoformat(assignment_data.due_date.replace('Z', '+00:00'))
            except:
                pass
        
        if assignment_data.description is not None:
            assignment.description = assignment_data.description
        
        assignment.updated_at = datetime.now()
        
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

@router.get("/{assignment_id}/equipment", response_model=dict)
async def get_assignment_equipment(
    assignment_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить информацию об оборудовании из задания (для мобильного приложения)"""
    try:
        result = await db.execute(
            select(Assignment).where(Assignment.id == assignment_id)
        )
        assignment = result.scalar_one_or_none()
        
        if not assignment:
            raise HTTPException(status_code=404, detail="Задание не найдено")
        
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
            from models import Workshop, Branch, Enterprise
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
            "equipment_code": equipment.equipment_code,
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
        # Получаем информацию о пользователе
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        
        if not user:
            raise HTTPException(status_code=404, detail="Пользователь не найден")
        
        # Проверяем права доступа (только операторы и выше)
        if user.role not in ['admin', 'chief_operator', 'operator']:
            raise HTTPException(status_code=403, detail="Доступ запрещен")
        
        # Получаем всех инженеров
        engineers_result = await db.execute(
            select(User).where(User.role == 'engineer', User.is_active == 1)
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
        print(f"❌ Error in get_assignments_statistics_by_engineers: {error_detail}")
        print(traceback.format_exc())
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
        # Текущий пользователь и права
        user_result = await db.execute(select(User).where(User.username == username))
        user = user_result.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=404, detail="Пользователь не найден")
        if user.role not in ["admin", "chief_operator", "operator"]:
            raise HTTPException(status_code=403, detail="Доступ запрещен")

        now = datetime.now()

        # Берем активные назначения инженеров по иерархии
        ha_result = await db.execute(
            select(HierarchyEngineerAssignment, User).join(
                User, HierarchyEngineerAssignment.user_id == User.id
            ).where(
                and_(
                    HierarchyEngineerAssignment.is_active == 1,
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
                # цеха филиала -> оборудование
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

            # считаем прогресс по заданиям для этого инженера в рамках объекта
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
            # сортируем инженеров по имени
            engineers_list.sort(key=lambda x: (x.get("full_name") or x.get("username") or ""))
            items.append(
                {
                    "object_type": v["object_type"],
                    "object_id": v["object_id"],
                    "object_name": v["object_name"],
                    "engineers": engineers_list,
                }
            )

        # сортировка объектов
        items.sort(key=lambda x: (x["object_type"], x["object_name"]))
        return {"items": items, "total": len(items)}

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Ошибка статистики по объектам: {str(e)}")

