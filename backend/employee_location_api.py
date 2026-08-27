"""
Координаты сотрудников (мобильное приложение → карта «Текущие сотрудники»).
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import Column, DateTime, Float, String, select, text
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql import func

from auth import verify_token
from database import Base, get_db
from models import User

router = APIRouter(tags=["employee-locations"])

# Считаем «онлайн», если пинг был не позже чем ONLINE_MINUTES назад
ONLINE_MINUTES = 15


class EmployeeLocation(Base):
    """Последняя известная геопозиция пользователя (из mobile)."""

    __tablename__ = "employee_locations"

    user_id = Column(PGUUID(as_uuid=True), primary_key=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    accuracy = Column(Float, nullable=True)
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    device_label = Column(String(128), nullable=True)


class LocationPingRequest(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    accuracy: Optional[float] = None
    device_label: Optional[str] = Field(None, max_length=128)


async def ensure_employee_locations_table(db: AsyncSession) -> None:
    await db.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS employee_locations (
                user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                latitude DOUBLE PRECISION NOT NULL,
                longitude DOUBLE PRECISION NOT NULL,
                accuracy DOUBLE PRECISION,
                updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                device_label VARCHAR(128)
            )
            """
        )
    )
    await db.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_employee_locations_updated_at "
            "ON employee_locations(updated_at DESC)"
        )
    )
    await db.commit()


async def _resolve_user(username: str, db: AsyncSession) -> User:
    from sqlalchemy import or_

    result = await db.execute(
        select(User).where(or_(User.username == username, User.email == username))
    )
    user = result.scalar_one_or_none()
    if not user or not user.is_active:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    return user


@router.post("/api/employee-locations/ping")
async def ping_location(
    body: LocationPingRequest,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Принять координаты от мобильного приложения (раз в ~5 мин)."""
    user = await _resolve_user(username, db)
    now = datetime.now(timezone.utc)

    existing = await db.get(EmployeeLocation, user.id)
    if existing is None:
        existing = EmployeeLocation(user_id=user.id)
        db.add(existing)

    existing.latitude = float(body.latitude)
    existing.longitude = float(body.longitude)
    existing.accuracy = float(body.accuracy) if body.accuracy is not None else None
    existing.updated_at = now
    if body.device_label:
        existing.device_label = body.device_label[:128]

    await db.commit()
    return {
        "ok": True,
        "user_id": str(user.id),
        "updated_at": now.isoformat(),
    }


@router.get("/api/employee-locations/online")
async def list_online_employees(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
    minutes: int = ONLINE_MINUTES,
):
    """Список сотрудников с недавним пингом (онлайн на карте)."""
    await _resolve_user(username, db)
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=max(1, min(minutes, 120)))

    result = await db.execute(
        select(EmployeeLocation, User)
        .join(User, User.id == EmployeeLocation.user_id)
        .where(
            EmployeeLocation.updated_at >= cutoff,
            User.is_active == True,  # noqa: E712
        )
        .order_by(EmployeeLocation.updated_at.desc())
    )
    rows = result.all()
    employees: List[Dict[str, Any]] = []
    for loc, user in rows:
        employees.append(
            {
                "user_id": str(user.id),
                "username": user.username,
                "full_name": user.full_name or user.username,
                "role": user.role,
                "latitude": loc.latitude,
                "longitude": loc.longitude,
                "accuracy": loc.accuracy,
                "updated_at": loc.updated_at.isoformat() if loc.updated_at else None,
                "device_label": loc.device_label,
                "online": True,
            }
        )
    return {
        "employees": employees,
        "online_window_minutes": minutes,
        "count": len(employees),
    }
