"""
Эндпоинт для получения истории синхронизаций
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from typing import List, Optional
from datetime import datetime
import logging

from database import get_db
from models import SyncHistory, User as UserModel, Inspection
from auth import verify_token, require_role

router = APIRouter(prefix="/api/v1/sync-history", tags=["sync-history"])
logger = logging.getLogger(__name__)


@router.get("")
async def get_sync_history(
    user_id: Optional[str] = None,  # Фильтр по инженеру (только для админов)
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
    current_user: UserModel = Depends(verify_token)
):
    """
    Получить историю синхронизаций
    
    - Админы, операторы могут видеть все синхронизации
    - Инженеры видят только свои синхронизации
    """
    try:
        # Определяем, чью историю показывать
        target_user_id = None
        if user_id:
            # Если указан user_id, проверяем права
            if current_user.role in ['admin', 'chief_operator', 'operator']:
                target_user_id = user_id
            else:
                # Инженеры могут видеть только свою историю
                if user_id != str(current_user.id):
                    raise HTTPException(
                        status_code=403,
                        detail="Доступ запрещен. Вы можете видеть только свою историю синхронизаций."
                    )
                target_user_id = str(current_user.id)
        else:
            # Если user_id не указан, показываем историю текущего пользователя
            if current_user.role == 'engineer':
                target_user_id = str(current_user.id)
            # Админы и операторы видят все, если user_id не указан
        
        # Формируем запрос
        query = select(SyncHistory)
        if target_user_id:
            query = query.where(SyncHistory.user_id == target_user_id)
        
        query = query.order_by(SyncHistory.created_at.desc()).limit(limit).offset(offset)
        
        result = await db.execute(query)
        sync_records = result.scalars().all()
        
        # Получаем информацию о пользователях для каждой записи
        items = []
        for record in sync_records:
            # Получаем информацию о пользователе
            user_result = await db.execute(
                select(UserModel).where(UserModel.id == record.user_id)
            )
            user = user_result.scalar_one_or_none()
            
            # Получаем информацию об инспекциях
            inspections_info = []
            if record.inspection_ids:
                for insp_id in record.inspection_ids[:10]:  # Ограничиваем до 10 для производительности
                    insp_result = await db.execute(
                        select(Inspection).where(Inspection.id == insp_id)
                    )
                    insp = insp_result.scalar_one_or_none()
                    if insp:
                        # Получаем информацию об оборудовании
                        eq_result = await db.execute(
                            select(Equipment).where(Equipment.id == insp.equipment_id)
                        )
                        equipment = eq_result.scalar_one_or_none()
                        inspections_info.append({
                            "id": str(insp.id),
                            "equipment_name": equipment.name if equipment else "Неизвестно",
                            "status": insp.status,
                            "date_performed": insp.date_performed.isoformat() if insp.date_performed else None,
                        })
            
            items.append({
                "id": str(record.id),
                "engineer": {
                    "id": str(record.user_id),
                    "username": user.username if user else "Неизвестно",
                    "full_name": user.full_name if user else None,
                },
                "synced_count": record.synced_count,
                "failed_count": record.failed_count,
                "sync_type": record.sync_type,
                "inspections": inspections_info,
                "total_inspections": len(record.inspection_ids) if record.inspection_ids else 0,
                "created_at": record.created_at.isoformat() if record.created_at else None,
            })
        
        return {
            "items": items,
            "total": len(items),
            "limit": limit,
            "offset": offset,
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Ошибка при получении истории синхронизаций: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Ошибка при получении истории синхронизаций: {str(e)}"
        )

