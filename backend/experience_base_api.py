"""
Опытная база диагностики (колонка «ДАННЫЕ/ОПЫТНАЯ БАЗА» из структуры xlsx).

Записи привязываются к категории объекта, марке/типу и опционально к паре «Задание — Объект».
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import text, select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from auth import verify_token
from database import get_db
from models import Assignment, Equipment, User

logger = logging.getLogger(__name__)
router = APIRouter(tags=["experience-base"])

ENTRY_TYPES = ("note", "recommendation", "operator_feedback")
ENTRY_TYPE_LABELS = {
    "note": "Заметка",
    "recommendation": "Рекомендация",
    "operator_feedback": "Отзыв эксплуатации",
}

# Категории из diagnostic_menu_structure (xlsx «РАЗДЕЛ»).
DIAGNOSTIC_CATEGORIES = [
    {"code": "srpd", "title": "СРпД (сосуды, аппараты, ёмкости)"},
    {"code": "bu", "title": "БУ (буровая установка)"},
    {"code": "boiler", "title": "Котёл"},
    {"code": "bo", "title": "БО (буровое оборудование)"},
    {"code": "valve_ps", "title": "Клапан предохранительный"},
]

# Архетипы для начального наполнения (идемпотентный seed).
ARCHETYPE_SEED: list[dict[str, str]] = [
    {"category_code": "srpd", "equipment_kind": "Сепаратор", "equipment_mark": "М-103А"},
    {"category_code": "srpd", "equipment_kind": "Ресивер", "equipment_mark": ""},
    {"category_code": "srpd", "equipment_kind": "Ёмкость подземная", "equipment_mark": "ЕП-12,5-2000-1300-2"},
    {"category_code": "srpd", "equipment_kind": "Нефтегазосепаратор", "equipment_mark": "НГС1-1,0-3000-2"},
    {"category_code": "srpd", "equipment_kind": "Нефтегазосепаратор", "equipment_mark": "НГС-1-10-2600-0,9Г2С"},
    {"category_code": "srpd", "equipment_kind": "Сепаратор факельный", "equipment_mark": "СФ"},
    {"category_code": "srpd", "equipment_kind": "Отстойник", "equipment_mark": "ОГ-200"},
    {"category_code": "srpd", "equipment_kind": "Воздухосборник", "equipment_mark": "V-2,7 м³"},
    {"category_code": "bu", "equipment_kind": "Буровая установка", "equipment_mark": "БУ 3000 ЭУК-1М"},
    {"category_code": "bu", "equipment_kind": "Буровая установка", "equipment_mark": "БУ 3900/225 ЭК-БМ"},
    {"category_code": "bu", "equipment_kind": "Буровая установка", "equipment_mark": "БУ 2900/175 ДЭП-11"},
    {"category_code": "bu", "equipment_kind": "Буровая установка", "equipment_mark": "БУ 2900/175 ЭПК БМ"},
    {"category_code": "boiler", "equipment_kind": "Котёл паровой", "equipment_mark": "Е 1,0-0,9М"},
    {"category_code": "boiler", "equipment_kind": "Котёл паровой", "equipment_mark": "КПН-1,0-9М"},
    {"category_code": "boiler", "equipment_kind": "Котёл паровой", "equipment_mark": "ПКН-2М"},
    {"category_code": "boiler", "equipment_kind": "Горелка", "equipment_mark": "PN-65"},
    {"category_code": "boiler", "equipment_kind": "Горелка", "equipment_mark": "PN-70"},
    {"category_code": "bo", "equipment_kind": "Насос буровой трехпоршневой", "equipment_mark": "УНБ-600"},
    {"category_code": "bo", "equipment_kind": "Насос буровой трехпоршневой", "equipment_mark": "УНБТ-1180"},
    {"category_code": "bo", "equipment_kind": "Ротор буровой", "equipment_mark": "Р-700"},
    {"category_code": "bo", "equipment_kind": "Лебедка буровая", "equipment_mark": "ЛБУ-750Э-СНГ"},
    {"category_code": "bo", "equipment_kind": "Лебедка вспомогательная", "equipment_mark": "ЛВ-44-1"},
    {"category_code": "valve_ps", "equipment_kind": "СППК", "equipment_mark": "4P 80-40"},
    {"category_code": "valve_ps", "equipment_kind": "СППК", "equipment_mark": "4 50х16 УХЛ1"},
    {"category_code": "valve_ps", "equipment_kind": "Клапан предохранительно-сбросной", "equipment_mark": "ПСК 535 DN20 PN40"},
    {"category_code": "valve_ps", "equipment_kind": "СППК", "equipment_mark": "5 100х16 УХЛ1"},
]


class ExperienceEntryCreate(BaseModel):
    category_code: str = Field(..., min_length=1, max_length=50)
    equipment_kind: str = Field(..., min_length=1, max_length=255)
    equipment_mark: Optional[str] = Field(None, max_length=255)
    entry_type: str = Field(default="note")
    title: Optional[str] = Field(None, max_length=500)
    body: str = Field(..., min_length=1)
    equipment_id: Optional[str] = None
    assignment_id: Optional[str] = None


class ExperienceEntryUpdate(BaseModel):
    entry_type: Optional[str] = None
    title: Optional[str] = Field(None, max_length=500)
    body: Optional[str] = Field(None, min_length=1)
    equipment_id: Optional[str] = None
    assignment_id: Optional[str] = None


async def _ensure_table(db: AsyncSession) -> None:
    await db.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS experience_base_entries (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                category_code VARCHAR(50) NOT NULL,
                equipment_kind VARCHAR(255) NOT NULL,
                equipment_mark VARCHAR(255),
                entry_type VARCHAR(40) NOT NULL DEFAULT 'note',
                title VARCHAR(500),
                body TEXT NOT NULL,
                equipment_id UUID REFERENCES equipment(id) ON DELETE SET NULL,
                assignment_id UUID REFERENCES assignments(id) ON DELETE SET NULL,
                is_archetype BOOLEAN NOT NULL DEFAULT FALSE,
                is_archived BOOLEAN NOT NULL DEFAULT FALSE,
                created_by UUID REFERENCES users(id) ON DELETE SET NULL,
                updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
            """
        )
    )
    await db.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_exp_base_category "
            "ON experience_base_entries(category_code)"
        )
    )
    await db.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_exp_base_equipment "
            "ON experience_base_entries(equipment_id)"
        )
    )
    await db.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_exp_base_assignment "
            "ON experience_base_entries(assignment_id)"
        )
    )
    await db.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_exp_base_kind_mark "
            "ON experience_base_entries(equipment_kind, equipment_mark)"
        )
    )


async def _user_row(db: AsyncSession, username: str) -> User:
    r = await db.execute(
        select(User).where(or_(User.username == username, User.email == username))
    )
    user = r.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=401, detail="Пользователь не найден")
    return user


def _row_to_dict(row) -> dict[str, Any]:
    d = dict(row._mapping)
    for k in ("id", "equipment_id", "assignment_id", "created_by", "updated_by"):
        if d.get(k) is not None:
            d[k] = str(d[k])
    for k in ("created_at", "updated_at"):
        if d.get(k) is not None:
            d[k] = d[k].isoformat()
    return d


def _validate_entry_type(entry_type: str) -> str:
    et = (entry_type or "note").strip().lower()
    if et not in ENTRY_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"entry_type должен быть одним из: {', '.join(ENTRY_TYPES)}",
        )
    return et


async def _validate_assignment_equipment(
    db: AsyncSession,
    assignment_id: Optional[str],
    equipment_id: Optional[str],
) -> None:
    if not assignment_id:
        return
    try:
        aid = uuid.UUID(assignment_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Некорректный assignment_id")
    ar = await db.execute(select(Assignment).where(Assignment.id == aid))
    asg = ar.scalar_one_or_none()
    if not asg:
        raise HTTPException(status_code=404, detail="Задание не найдено")
    if equipment_id:
        try:
            eid = uuid.UUID(equipment_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Некорректный equipment_id")
        if asg.equipment_id != eid:
            raise HTTPException(
                status_code=400,
                detail="Оборудование не совпадает с оборудованием в задании",
            )


async def ensure_experience_archetype_seed(db: AsyncSession) -> int:
    """Идемпотентно создать справочные записи-архетипы без пользовательского текста."""
    await _ensure_table(db)
    count = 0
    for item in ARCHETYPE_SEED:
        mark = (item.get("equipment_mark") or "").strip()
        await db.execute(
            text(
                """
                INSERT INTO experience_base_entries (
                    category_code, equipment_kind, equipment_mark,
                    entry_type, title, body, is_archetype, is_archived
                )
                SELECT :cat, :kind, :mark, 'note', :title, :body, TRUE, FALSE
                WHERE NOT EXISTS (
                    SELECT 1 FROM experience_base_entries
                    WHERE is_archetype = TRUE
                      AND is_archived = FALSE
                      AND category_code = :cat
                      AND equipment_kind = :kind
                      AND COALESCE(equipment_mark, '') = :mark
                )
                """
            ),
            {
                "cat": item["category_code"],
                "kind": item["equipment_kind"],
                "mark": mark,
                "title": f"{item['equipment_kind']} {mark}".strip(),
                "body": "Справочная запись из структуры ТЗ. Добавьте рекомендации и отзывы эксплуатации.",
            },
        )
        count += 1
    await db.commit()
    return count


@router.get("/api/experience-base/categories")
async def list_categories(current_user: str = Depends(verify_token)):
    """Категории объектов (разделы xlsx)."""
    return {"categories": DIAGNOSTIC_CATEGORIES, "entry_types": ENTRY_TYPE_LABELS}


@router.get("/api/experience-base/entries")
async def list_entries(
    category_code: Optional[str] = None,
    equipment_id: Optional[str] = None,
    assignment_id: Optional[str] = None,
    equipment_kind: Optional[str] = None,
    equipment_mark: Optional[str] = None,
    entry_type: Optional[str] = None,
    include_archetypes: bool = True,
    q: Optional[str] = None,
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Список записей опытной базы с фильтрами."""
    await _ensure_table(db)
    conditions = ["is_archived = FALSE"]
    params: dict[str, Any] = {"limit": limit, "offset": offset}

    if not include_archetypes:
        conditions.append("is_archetype = FALSE")
    if category_code:
        conditions.append("category_code = :category_code")
        params["category_code"] = category_code.strip()
    if equipment_id:
        conditions.append("equipment_id = CAST(:equipment_id AS uuid)")
        params["equipment_id"] = equipment_id.strip()
    if assignment_id:
        conditions.append("assignment_id = CAST(:assignment_id AS uuid)")
        params["assignment_id"] = assignment_id.strip()
    if equipment_kind:
        conditions.append("equipment_kind ILIKE :equipment_kind")
        params["equipment_kind"] = f"%{equipment_kind.strip()}%"
    if equipment_mark:
        conditions.append("equipment_mark ILIKE :equipment_mark")
        params["equipment_mark"] = f"%{equipment_mark.strip()}%"
    if entry_type:
        conditions.append("entry_type = :entry_type")
        params["entry_type"] = _validate_entry_type(entry_type)
    if q and q.strip():
        conditions.append(
            "(title ILIKE :q OR body ILIKE :q OR equipment_kind ILIKE :q OR equipment_mark ILIKE :q)"
        )
        params["q"] = f"%{q.strip()}%"

    where = " AND ".join(conditions)
    result = await db.execute(
        text(
            f"""
            SELECT * FROM experience_base_entries
            WHERE {where}
            ORDER BY is_archetype ASC, updated_at DESC
            LIMIT :limit OFFSET :offset
            """
        ),
        params,
    )
    rows = result.fetchall()
    await db.commit()
    return [_row_to_dict(r) for r in rows]


@router.get("/api/experience-base/context")
async def context_for_task_object(
    assignment_id: Optional[str] = None,
    equipment_id: Optional[str] = None,
    category_code: Optional[str] = None,
    equipment_kind: Optional[str] = None,
    equipment_mark: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """
    Записи для пары «Задание — Объект»: прямая привязка + совпадение по типу/марке оборудования.
    """
    await _ensure_table(db)
    eq_name = ""
    eq_kind_hint = equipment_kind
    eq_mark_hint = equipment_mark
    resolved_category = category_code
    resolved_equipment_id = equipment_id

    if assignment_id:
        try:
            aid = uuid.UUID(assignment_id.strip())
        except ValueError:
            raise HTTPException(status_code=400, detail="Некорректный assignment_id")
        ar = await db.execute(select(Assignment).where(Assignment.id == aid))
        asg = ar.scalar_one_or_none()
        if not asg:
            raise HTTPException(status_code=404, detail="Задание не найдено")
        if not resolved_equipment_id and asg.equipment_id:
            resolved_equipment_id = str(asg.equipment_id)

    if resolved_equipment_id:
        try:
            eid = uuid.UUID(resolved_equipment_id.strip())
        except ValueError:
            raise HTTPException(status_code=400, detail="Некорректный equipment_id")
        er = await db.execute(select(Equipment).where(Equipment.id == eid))
        eq = er.scalar_one_or_none()
        if eq:
            eq_name = eq.name or ""
            if not eq_kind_hint and eq.name:
                eq_kind_hint = eq.name
            if not eq_mark_hint and getattr(eq, "model", None):
                eq_mark_hint = str(eq.model)

    clauses = ["is_archived = FALSE"]
    params: dict[str, Any] = {}

    bind_parts = []
    if assignment_id:
        bind_parts.append("assignment_id = CAST(:assignment_id AS uuid)")
        params["assignment_id"] = assignment_id.strip()
    if resolved_equipment_id:
        bind_parts.append("equipment_id = CAST(:equipment_id AS uuid)")
        params["equipment_id"] = resolved_equipment_id.strip()
    if eq_kind_hint and eq_kind_hint.strip():
        bind_parts.append(
            "(equipment_kind ILIKE :kind_hint OR :eq_name ILIKE '%' || equipment_kind || '%')"
        )
        params["kind_hint"] = f"%{eq_kind_hint.strip()}%"
        params["eq_name"] = eq_name or eq_kind_hint.strip()
    if eq_mark_hint and eq_mark_hint.strip():
        bind_parts.append("equipment_mark ILIKE :mark_hint")
        params["mark_hint"] = f"%{eq_mark_hint.strip()}%"
    if resolved_category:
        bind_parts.append("category_code = :category_code")
        params["category_code"] = resolved_category.strip()

    if bind_parts:
        clauses.append("(" + " OR ".join(bind_parts) + ")")
    else:
        clauses.append("is_archetype = TRUE")

    where = " AND ".join(clauses)
    result = await db.execute(
        text(
            f"""
            SELECT * FROM experience_base_entries
            WHERE {where}
            ORDER BY is_archetype ASC, updated_at DESC
            LIMIT 80
            """
        ),
        params,
    )
    rows = result.fetchall()
    await db.commit()
    items = [_row_to_dict(r) for r in rows]
    return {
        "assignment_id": assignment_id,
        "equipment_id": resolved_equipment_id,
        "equipment_name": eq_name,
        "items": items,
    }


@router.post("/api/experience-base/entries", status_code=201)
async def create_entry(
    body: ExperienceEntryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    await _ensure_table(db)
    user = await _user_row(db, current_user)
    et = _validate_entry_type(body.entry_type)
    await _validate_assignment_equipment(db, body.assignment_id, body.equipment_id)

    eid = uuid.uuid4()
    now = datetime.now(timezone.utc)
    await db.execute(
        text(
            """
            INSERT INTO experience_base_entries (
                id, category_code, equipment_kind, equipment_mark,
                entry_type, title, body,
                equipment_id, assignment_id,
                is_archetype, created_by, updated_by, created_at, updated_at
            ) VALUES (
                :id, :cat, :kind, :mark,
                :etype, :title, :body,
                CAST(NULLIF(:equipment_id, '') AS uuid),
                CAST(NULLIF(:assignment_id, '') AS uuid),
                FALSE, :uid, :uid, :now, :now
            )
            """
        ),
        {
            "id": eid,
            "cat": body.category_code.strip()[:50],
            "kind": body.equipment_kind.strip()[:255],
            "mark": (body.equipment_mark or "").strip()[:255] or None,
            "etype": et,
            "title": (body.title or "").strip()[:500] or None,
            "body": body.body.strip(),
            "equipment_id": (body.equipment_id or "").strip(),
            "assignment_id": (body.assignment_id or "").strip(),
            "uid": user.id,
            "now": now,
        },
    )
    await db.commit()
    result = await db.execute(
        text("SELECT * FROM experience_base_entries WHERE id = :id"),
        {"id": eid},
    )
    row = result.fetchone()
    return _row_to_dict(row)


@router.patch("/api/experience-base/entries/{entry_id}")
async def update_entry(
    entry_id: str,
    body: ExperienceEntryUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    await _ensure_table(db)
    user = await _user_row(db, current_user)
    try:
        eid = uuid.UUID(entry_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Некорректный id")

    cur = await db.execute(
        text("SELECT * FROM experience_base_entries WHERE id = :id AND is_archived = FALSE"),
        {"id": eid},
    )
    row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    existing = dict(row._mapping)
    if existing.get("is_archetype"):
        raise HTTPException(status_code=403, detail="Справочный архетип нельзя редактировать")

    new_assignment = (
        body.assignment_id
        if body.assignment_id is not None
        else (str(existing.get("assignment_id")) if existing.get("assignment_id") else None)
    )
    new_equipment = (
        body.equipment_id
        if body.equipment_id is not None
        else (str(existing.get("equipment_id")) if existing.get("equipment_id") else None)
    )
    await _validate_assignment_equipment(db, new_assignment, new_equipment)

    sets = ["updated_by = :uid", "updated_at = NOW()"]
    params: dict[str, Any] = {"id": eid, "uid": user.id}
    if body.entry_type is not None:
        sets.append("entry_type = :etype")
        params["etype"] = _validate_entry_type(body.entry_type)
    if body.title is not None:
        sets.append("title = :title")
        params["title"] = body.title.strip()[:500] or None
    if body.body is not None:
        sets.append("body = :body")
        params["body"] = body.body.strip()
    if body.equipment_id is not None:
        sets.append("equipment_id = CAST(NULLIF(:equipment_id, '') AS uuid)")
        params["equipment_id"] = body.equipment_id.strip()
    if body.assignment_id is not None:
        sets.append("assignment_id = CAST(NULLIF(:assignment_id, '') AS uuid)")
        params["assignment_id"] = body.assignment_id.strip()

    await db.execute(
        text(f"UPDATE experience_base_entries SET {', '.join(sets)} WHERE id = :id"),
        params,
    )
    await db.commit()
    result = await db.execute(
        text("SELECT * FROM experience_base_entries WHERE id = :id"),
        {"id": eid},
    )
    return _row_to_dict(result.fetchone())


@router.delete("/api/experience-base/entries/{entry_id}")
async def archive_entry(
    entry_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    await _ensure_table(db)
    await _user_row(db, current_user)
    try:
        eid = uuid.UUID(entry_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Некорректный id")

    cur = await db.execute(
        text("SELECT is_archetype FROM experience_base_entries WHERE id = :id"),
        {"id": eid},
    )
    row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Запись не найдена")
    if row[0]:
        raise HTTPException(status_code=403, detail="Справочный архетип нельзя удалить")

    await db.execute(
        text(
            "UPDATE experience_base_entries SET is_archived = TRUE, updated_at = NOW() WHERE id = :id"
        ),
        {"id": eid},
    )
    await db.commit()
    return {"ok": True}
