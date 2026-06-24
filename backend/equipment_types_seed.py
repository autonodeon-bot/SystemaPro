"""
Идемпотентное наполнение справочника типов оборудования.
"""
from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models import EquipmentType

DEFAULT_EQUIPMENT_TYPES = [
    {
        "code": "VESSEL",
        "name": "Сосуд под давлением",
        "description": "Сосуды и аппараты СРпД",
    },
    {
        "code": "GAS_SEPARATOR",
        "name": "Газосепаратор",
        "description": "Газосепаратор (аппарат СРпД) — сепарация фаз нефтегазовой смеси",
    },
    {
        "code": "UNDERGROUND_TANK",
        "name": "Ёмкость подземная",
        "description": "Подземная горизонтальная ёмкость СРпД (давление до 0,07 МПа)",
    },
    {
        "code": "OIL_SETTLER",
        "name": "Отстойник нефти",
        "description": "Отстойник нефти (аппарат СРпД) — трёхфазное разделение НГВС",
    },
    {
        "code": "PIPELINE",
        "name": "Трубопровод",
        "description": "Трубопроводы технологические",
    },
    {
        "code": "COMPRESSOR",
        "name": "Компрессор",
        "description": "Компрессорное оборудование",
    },
]


async def ensure_default_equipment_types(db: AsyncSession) -> int:
    """Создать или обновить базовые типы оборудования по коду."""
    count = 0
    for item in DEFAULT_EQUIPMENT_TYPES:
        result = await db.execute(
            select(EquipmentType).where(EquipmentType.code == item["code"])
        )
        existing = result.scalar_one_or_none()
        if existing:
            existing.name = item["name"]
            existing.description = item["description"]
            existing.is_active = True
        else:
            db.add(
                EquipmentType(
                    id=uuid.uuid4(),
                    code=item["code"],
                    name=item["name"],
                    description=item["description"],
                    is_active=True,
                )
            )
        count += 1
    await db.commit()
    return count
