"""Доступ роли client к оборудованию (и производным сущностям)."""

from __future__ import annotations

import uuid as uuid_lib
from typing import List, Set

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models import (
    User,
    Enterprise,
    Branch,
    Workshop,
    Equipment,
    Project,
    Assignment,
    Inspection,
    UserEquipmentAccess,
)


async def get_client_accessible_equipment_ids(db: AsyncSession, user: User) -> List[uuid_lib.UUID]:
    """
    ID оборудования, доступного пользователю с ролью client.

    Источники:
    - предприятия с enterprises.client_id = user.client_id;
    - задания/обследования по проектам с projects.client_id = user.client_id;
    - явные записи user_equipment_access для данного пользователя.
    """
    if user.role != "client" or not user.client_id:
        return []

    cid = user.client_id
    ids: Set[uuid_lib.UUID] = set()

    ent_res = await db.execute(select(Enterprise.id).where(Enterprise.client_id == cid))
    ent_ids = [r[0] for r in ent_res.all()]
    if ent_ids:
        br_res = await db.execute(select(Branch.id).where(Branch.enterprise_id.in_(ent_ids)))
        br_ids = [r[0] for r in br_res.all()]
        if br_ids:
            ws_res = await db.execute(select(Workshop.id).where(Workshop.branch_id.in_(br_ids)))
            ws_ids = [r[0] for r in ws_res.all()]
            if ws_ids:
                eq_res = await db.execute(select(Equipment.id).where(Equipment.workshop_id.in_(ws_ids)))
                for row in eq_res.all():
                    ids.add(row[0])

    proj_res = await db.execute(select(Project.id).where(Project.client_id == cid))
    proj_ids = [r[0] for r in proj_res.all()]
    if proj_ids:
        as_res = await db.execute(
            select(Assignment.equipment_id).where(
                Assignment.project_id.in_(proj_ids),
                Assignment.equipment_id.isnot(None),
            )
        )
        for row in as_res.all():
            if row[0]:
                ids.add(row[0])
        in_res = await db.execute(
            select(Inspection.equipment_id).where(
                Inspection.project_id.in_(proj_ids),
                Inspection.equipment_id.isnot(None),
            )
        )
        for row in in_res.all():
            if row[0]:
                ids.add(row[0])

    uea_res = await db.execute(
        select(UserEquipmentAccess.equipment_id).where(UserEquipmentAccess.user_id == user.id)
    )
    for row in uea_res.all():
        ids.add(row[0])

    return list(ids)


async def client_user_can_access_equipment(
    db: AsyncSession, user: User, equipment_id: uuid_lib.UUID
) -> bool:
    """Проверка доступа client к одному объекту оборудования (скачивание отчёта и т.п.)."""
    if user.role != "client" or not user.client_id:
        return False

    cid = user.client_id

    r = await db.execute(
        select(UserEquipmentAccess.id).where(
            UserEquipmentAccess.user_id == user.id,
            UserEquipmentAccess.equipment_id == equipment_id,
        ).limit(1)
    )
    if r.scalar_one_or_none():
        return True

    eq = (await db.execute(select(Equipment).where(Equipment.id == equipment_id))).scalar_one_or_none()
    if not eq or not eq.workshop_id:
        pass
    else:
        ws = (await db.execute(select(Workshop).where(Workshop.id == eq.workshop_id))).scalar_one_or_none()
        if ws:
            br = (await db.execute(select(Branch).where(Branch.id == ws.branch_id))).scalar_one_or_none()
            if br:
                ent = (
                    await db.execute(select(Enterprise).where(Enterprise.id == br.enterprise_id))
                ).scalar_one_or_none()
                if ent and ent.client_id == cid:
                    return True

    r2 = await db.execute(
        select(Assignment.id).where(
            Assignment.equipment_id == equipment_id,
            Assignment.project_id.in_(select(Project.id).where(Project.client_id == cid)),
        ).limit(1)
    )
    if r2.scalar_one_or_none():
        return True

    r3 = await db.execute(
        select(Inspection.id).where(
            Inspection.equipment_id == equipment_id,
            Inspection.project_id.in_(select(Project.id).where(Project.client_id == cid)),
        ).limit(1)
    )
    return r3.scalar_one_or_none() is not None
