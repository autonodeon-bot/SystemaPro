"""
API для уведомлений (FCM push-уведомления + in-app)
"""
import logging
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, update
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime, timezone
import uuid as uuid_lib

from database import get_db
from models import User, Assignment, UserDevice
from auth import verify_token

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/notifications", tags=["notifications"])


class NotificationResponse(BaseModel):
    id: str
    type: str
    title: str
    message: str
    is_read: bool
    created_at: str
    data: Optional[dict] = None


class DeviceRegistrationRequest(BaseModel):
    fcm_token: str
    platform: str = "android"


@router.get("", response_model=List[NotificationResponse])
async def get_notifications(
    unread_only: bool = False,
    limit: int = 50,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Получить уведомления пользователя.

    В текущей версии генерирует уведомления на основе новых/обновлённых заданий.
    В будущем будет использовать отдельную таблицу notifications и FCM push.
    """
    user_result = await db.execute(
        select(User).where(or_(User.username == username, User.email == username))
    )
    user = user_result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    notifications = []

    if user.role == 'engineer':
        new_assignments = await db.execute(
            select(Assignment)
            .where(
                and_(
                    Assignment.assigned_to == user.id,
                    Assignment.status == 'PENDING'
                )
            )
            .order_by(Assignment.created_at.desc())
            .limit(limit)
        )
        for assignment in new_assignments.scalars().all():
            notifications.append({
                "id": str(assignment.id),
                "type": "new_assignment",
                "title": "Новое задание",
                "message": f"Вам назначено задание: {assignment.assignment_type}",
                "is_read": False,
                "created_at": assignment.created_at.isoformat() if assignment.created_at else datetime.now(timezone.utc).isoformat(),
                "data": {
                    "assignment_id": str(assignment.id),
                    "equipment_id": str(assignment.equipment_id),
                    "assignment_type": assignment.assignment_type,
                    "priority": assignment.priority,
                }
            })

    return notifications


@router.get("/count")
async def get_unread_count(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db)
):
    """Количество непрочитанных уведомлений"""
    user_result = await db.execute(
        select(User).where(or_(User.username == username, User.email == username))
    )
    user = user_result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    from sqlalchemy import func

    if user.role == 'engineer':
        count_result = await db.execute(
            select(func.count()).select_from(Assignment).where(
                and_(
                    Assignment.assigned_to == user.id,
                    Assignment.status == 'PENDING'
                )
            )
        )
        count = count_result.scalar() or 0
    else:
        count = 0

    return {"unread_count": count}


@router.post("/register-device")
async def register_device(
    request: DeviceRegistrationRequest,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Зарегистрировать FCM токен устройства"""
    user_result = await db.execute(
        select(User).where(or_(User.username == username, User.email == username))
    )
    user = user_result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    # Деактивируем старые токены пользователя на этой платформе
    await db.execute(
        update(UserDevice)
        .where(and_(UserDevice.user_id == user.id, UserDevice.platform == request.platform))
        .values(is_active=False)
    )

    # Upsert: если токен уже есть — обновляем, иначе создаём
    existing = await db.execute(
        select(UserDevice).where(UserDevice.fcm_token == request.fcm_token)
    )
    device = existing.scalar_one_or_none()

    if device:
        device.user_id = user.id
        device.is_active = True
        device.platform = request.platform
    else:
        device = UserDevice(
            user_id=user.id,
            fcm_token=request.fcm_token,
            platform=request.platform,
        )
        db.add(device)

    await db.commit()
    return {"status": "ok"}


async def send_push_notification(
    db: AsyncSession,
    user_id,
    title: str,
    body: str,
    data: dict = None,
):
    """Отправить push-уведомление на устройства пользователя через FCM.

    Полная интеграция с FCM v1 API требует google-auth и сервисный аккаунт.
    Сейчас логируем намерение — подключение реального FCM будет следующим шагом.
    """
    devices = await db.execute(
        select(UserDevice).where(
            and_(UserDevice.user_id == user_id, UserDevice.is_active == True)
        )
    )

    for device in devices.scalars().all():
        try:
            logger.info(
                f"Push notification to {device.fcm_token[:20]}...: {title} — {body}"
            )
        except Exception as e:
            logger.warning(f"FCM send error: {e}")
