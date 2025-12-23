"""
API для работы с историей обследований и журналом ремонта оборудования (версия 3.3.0)
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, desc
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime
import uuid as uuid_lib

from database import get_db
from models import InspectionHistory, RepairJournal, Equipment, User, Assignment
from auth import verify_token

router = APIRouter(prefix="/api/equipment", tags=["equipment_history"])

# Pydantic модели для истории обследований
class InspectionHistoryResponse(BaseModel):
    id: str
    equipment_id: str
    equipment_code: str
    equipment_name: str
    assignment_id: Optional[str]
    inspection_type: str
    inspector_id: Optional[str]
    inspector_name: Optional[str]
    inspection_date: str
    conclusion: Optional[str]
    next_inspection_date: Optional[str]
    status: str
    report_path: Optional[str]
    word_report_path: Optional[str]
    created_at: str

# Pydantic модели для журнала ремонта
class RepairJournalResponse(BaseModel):
    id: str
    equipment_id: str
    equipment_code: str
    equipment_name: str
    repair_date: str
    repair_type: str
    description: str
    performed_by: Optional[str]
    performed_by_name: Optional[str]
    cost: Optional[float]
    documents: List[str]
    created_at: str

@router.get("/{equipment_id}/history", response_model=List[InspectionHistoryResponse])
async def get_equipment_inspection_history(
    equipment_id: str,
    inspection_type: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить историю обследований оборудования"""
    try:
        # Проверяем существование оборудования
        equipment_result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        equipment = equipment_result.scalar_one_or_none()
        
        if not equipment:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Формируем запрос
        query = select(InspectionHistory).where(
            InspectionHistory.equipment_id == uuid_lib.UUID(equipment_id)
        )
        
        if inspection_type:
            query = query.where(InspectionHistory.inspection_type == inspection_type)
        
        # Сортируем по дате (новые первые)
        query = query.order_by(desc(InspectionHistory.inspection_date))
        
        result = await db.execute(query)
        history_items = result.scalars().all()
        
        # Формируем ответ
        history_list = []
        for item in history_items:
            # Получаем информацию об инженере
            inspector_name = None
            if item.inspector_id:
                inspector_result = await db.execute(
                    select(User).where(User.id == item.inspector_id)
                )
                inspector = inspector_result.scalar_one_or_none()
                if inspector:
                    inspector_name = inspector.full_name
            
            history_list.append({
                "id": str(item.id),
                "equipment_id": str(item.equipment_id),
                "equipment_code": equipment.equipment_code,
                "equipment_name": equipment.name,
                "assignment_id": str(item.assignment_id) if item.assignment_id else None,
                "inspection_type": item.inspection_type,
                "inspector_id": str(item.inspector_id) if item.inspector_id else None,
                "inspector_name": inspector_name,
                "inspection_date": item.inspection_date.isoformat() if item.inspection_date else None,
                "conclusion": item.conclusion,
                "next_inspection_date": str(item.next_inspection_date) if item.next_inspection_date else None,
                "status": item.status,
                "report_path": item.report_path,
                "word_report_path": item.word_report_path,
                "created_at": item.created_at.isoformat() if item.created_at else None,
            })
        
        return history_list
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Ошибка при получении истории: {str(e)}")

@router.get("/{equipment_id}/repairs", response_model=List[RepairJournalResponse])
async def get_equipment_repair_journal(
    equipment_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить журнал ремонта оборудования"""
    try:
        # Проверяем существование оборудования
        equipment_result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        equipment = equipment_result.scalar_one_or_none()
        
        if not equipment:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Получаем записи журнала ремонта
        query = select(RepairJournal).where(
            RepairJournal.equipment_id == uuid_lib.UUID(equipment_id)
        ).order_by(desc(RepairJournal.repair_date))
        
        result = await db.execute(query)
        repairs = result.scalars().all()
        
        # Формируем ответ
        repairs_list = []
        for repair in repairs:
            # Получаем информацию о том, кто выполнил ремонт
            performed_by_name = None
            if repair.performed_by:
                user_result = await db.execute(
                    select(User).where(User.id == repair.performed_by)
                )
                user = user_result.scalar_one_or_none()
                if user:
                    performed_by_name = user.full_name
            
            repairs_list.append({
                "id": str(repair.id),
                "equipment_id": str(repair.equipment_id),
                "equipment_code": equipment.equipment_code,
                "equipment_name": equipment.name,
                "repair_date": repair.repair_date.isoformat() if repair.repair_date else None,
                "repair_type": repair.repair_type,
                "description": repair.description,
                "performed_by": str(repair.performed_by) if repair.performed_by else None,
                "performed_by_name": performed_by_name,
                "cost": float(repair.cost) if repair.cost else None,
                "documents": repair.documents if repair.documents else [],
                "created_at": repair.created_at.isoformat() if repair.created_at else None,
            })
        
        return repairs_list
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Ошибка при получении журнала ремонта: {str(e)}")

@router.post("/{equipment_id}/repairs", response_model=dict)
async def create_repair_entry(
    equipment_id: str,
    repair_data: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Создать запись в журнале ремонта"""
    try:
        # Проверяем права доступа
        user_result = await db.execute(
            select(User).where(User.username == username)
        )
        user = user_result.scalar_one_or_none()
        
        if not user:
            raise HTTPException(status_code=404, detail="Пользователь не найден")
        
        # Проверяем существование оборудования
        equipment_result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        equipment = equipment_result.scalar_one_or_none()
        
        if not equipment:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Парсим дату ремонта
        repair_date = datetime.now()
        if repair_data.get('repair_date'):
            try:
                repair_date = datetime.fromisoformat(repair_data['repair_date'].replace('Z', '+00:00'))
            except:
                pass
        
        # Создаем запись
        new_repair = RepairJournal(
            equipment_id=uuid_lib.UUID(equipment_id),
            repair_date=repair_date,
            repair_type=repair_data.get('repair_type', 'REPAIR'),
            description=repair_data.get('description', ''),
            performed_by=user.id,
            cost=repair_data.get('cost'),
            documents=repair_data.get('documents', [])
        )
        
        db.add(new_repair)
        await db.commit()
        await db.refresh(new_repair)
        
        return {
            "id": str(new_repair.id),
            "status": "created",
            "message": "Запись в журнале ремонта успешно создана"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Ошибка при создании записи: {str(e)}")

@router.get("/{equipment_id}/summary", response_model=dict)
async def get_equipment_summary(
    equipment_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить сводную информацию об оборудовании (история + ремонты)"""
    try:
        # Проверяем существование оборудования
        equipment_result = await db.execute(
            select(Equipment).where(Equipment.id == equipment_id)
        )
        equipment = equipment_result.scalar_one_or_none()
        
        if not equipment:
            raise HTTPException(status_code=404, detail="Оборудование не найдено")
        
        # Получаем количество обследований
        history_count_result = await db.execute(
            select(InspectionHistory).where(InspectionHistory.equipment_id == uuid_lib.UUID(equipment_id))
        )
        history_count = len(history_count_result.scalars().all())
        
        # Получаем последнее обследование
        last_inspection_result = await db.execute(
            select(InspectionHistory)
            .where(InspectionHistory.equipment_id == uuid_lib.UUID(equipment_id))
            .order_by(desc(InspectionHistory.inspection_date))
            .limit(1)
        )
        last_inspection = last_inspection_result.scalar_one_or_none()
        
        # Получаем количество ремонтов
        repairs_count_result = await db.execute(
            select(RepairJournal).where(RepairJournal.equipment_id == uuid_lib.UUID(equipment_id))
        )
        repairs_count = len(repairs_count_result.scalars().all())
        
        # Получаем последний ремонт
        last_repair_result = await db.execute(
            select(RepairJournal)
            .where(RepairJournal.equipment_id == uuid_lib.UUID(equipment_id))
            .order_by(desc(RepairJournal.repair_date))
            .limit(1)
        )
        last_repair = last_repair_result.scalar_one_or_none()
        
        # Получаем активные задания
        active_assignments_result = await db.execute(
            select(Assignment)
            .where(
                and_(
                    Assignment.equipment_id == uuid_lib.UUID(equipment_id),
                    Assignment.status.in_(['PENDING', 'IN_PROGRESS'])
                )
            )
        )
        active_assignments = active_assignments_result.scalars().all()
        
        return {
            "equipment": {
                "id": str(equipment.id),
                "equipment_code": equipment.equipment_code,
                "name": equipment.name,
                "serial_number": equipment.serial_number,
                "location": equipment.location,
            },
            "statistics": {
                "total_inspections": history_count,
                "total_repairs": repairs_count,
                "active_assignments": len(active_assignments),
            },
            "last_inspection": {
                "id": str(last_inspection.id),
                "date": last_inspection.inspection_date.isoformat(),
                "type": last_inspection.inspection_type,
                "status": last_inspection.status,
            } if last_inspection else None,
            "last_repair": {
                "id": str(last_repair.id),
                "date": last_repair.repair_date.isoformat(),
                "type": last_repair.repair_type,
            } if last_repair else None,
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Ошибка при получении сводной информации: {str(e)}")

