"""
Шаблоны обследования объектов (xlsx: выбор объекта + редактируемые данные).

Хранят предзаполнение чек-листа / параметров обследования по категории объекта и направлению.
"""
from __future__ import annotations

import json
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
from models import Equipment, User

logger = logging.getLogger(__name__)
router = APIRouter(tags=["inspection-object-templates"])

EDITOR_ROLES = {"admin", "chief_operator", "operator"}
TARGET_FLOWS = ("vessel_checklist", "ndk_protocol", "pressure_test", "questionnaire")


class InspectionObjectTemplateCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    category_code: str = Field(..., min_length=1, max_length=50)
    equipment_preset: Optional[str] = Field(None, max_length=50)
    inspection_direction: str = Field(..., min_length=1, max_length=50)
    target_flow: str = Field(default="vessel_checklist")
    equipment_kind: Optional[str] = None
    equipment_mark: Optional[str] = None
    default_data: dict[str, Any] = Field(default_factory=dict)


class InspectionObjectTemplateUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    category_code: Optional[str] = None
    equipment_preset: Optional[str] = None
    inspection_direction: Optional[str] = None
    target_flow: Optional[str] = None
    equipment_kind: Optional[str] = None
    equipment_mark: Optional[str] = None
    default_data: Optional[dict[str, Any]] = None
    is_active: Optional[bool] = None


# Стартовые шаблоны (идемпотентный seed).
SEED_TEMPLATES: list[dict[str, Any]] = [
    {
        "id": "iot-srpd-nivo",
        "name": "СРпД · Наружный/внутренний осмотр (НиВО)",
        "category_code": "srpd",
        "equipment_preset": "vessel",
        "inspection_direction": "external",
        "target_flow": "vessel_checklist",
        "equipment_kind": "Сепаратор",
        "default_data": {
            "inspection_type": "VISUAL",
            "include_opo_data": True,
            "purpose": "Разделение фаз / учёт параметров эксплуатации",
        },
    },
    {
        "id": "iot-srpd-td",
        "name": "СРпД · Техническая диагностика",
        "category_code": "srpd",
        "equipment_preset": "vessel",
        "inspection_direction": "technical",
        "target_flow": "vessel_checklist",
        "default_data": {"inspection_type": "NDT"},
    },
    {
        "id": "iot-bu-epb",
        "name": "БУ · ТД (ЭПБ)",
        "category_code": "bu",
        "equipment_preset": "drilling",
        "inspection_direction": "technical",
        "target_flow": "vessel_checklist",
        "equipment_kind": "Буровая установка",
        "default_data": {"inspection_type": "EXPERTISE"},
    },
    {
        "id": "iot-valve-test",
        "name": "Клапан ПС · Испытания",
        "category_code": "valve_ps",
        "equipment_preset": "valve_ps",
        "inspection_direction": "hydraulic",
        "target_flow": "pressure_test",
        "default_data": {"test_type": "ГИ"},
    },
]


async def _ensure_table(db: AsyncSession) -> None:
    await db.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS inspection_object_templates (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT,
                category_code TEXT NOT NULL,
                equipment_preset TEXT,
                inspection_direction TEXT NOT NULL,
                target_flow TEXT NOT NULL DEFAULT 'vessel_checklist',
                equipment_kind TEXT,
                equipment_mark TEXT,
                default_data JSONB NOT NULL DEFAULT '{}'::jsonb,
                is_active BOOLEAN NOT NULL DEFAULT TRUE,
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
            "CREATE INDEX IF NOT EXISTS idx_iot_category "
            "ON inspection_object_templates(category_code)"
        )
    )
    await db.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_iot_direction "
            "ON inspection_object_templates(inspection_direction)"
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
    for k in ("id", "created_by", "updated_by"):
        if d.get(k) is not None:
            d[k] = str(d[k])
    if isinstance(d.get("default_data"), str):
        d["default_data"] = json.loads(d["default_data"])
    for k in ("created_at", "updated_at"):
        if d.get(k) is not None:
            d[k] = d[k].isoformat()
    return d


def _validate_target_flow(flow: str) -> str:
    f = (flow or "vessel_checklist").strip()
    if f not in TARGET_FLOWS:
        raise HTTPException(
            status_code=400,
            detail=f"target_flow: один из {', '.join(TARGET_FLOWS)}",
        )
    return f


async def ensure_inspection_object_templates_seed(db: AsyncSession) -> int:
    await _ensure_table(db)
    count = 0
    for item in SEED_TEMPLATES:
        await db.execute(
            text(
                """
                INSERT INTO inspection_object_templates (
                    id, name, description, category_code, equipment_preset,
                    inspection_direction, target_flow, equipment_kind, equipment_mark,
                    default_data, is_active
                ) VALUES (
                    :id, :name, :desc, :cat, :preset, :dir, :flow, :kind, :mark,
                    CAST(:data AS jsonb), TRUE
                )
                ON CONFLICT (id) DO UPDATE SET
                    name = EXCLUDED.name,
                    description = EXCLUDED.description,
                    category_code = EXCLUDED.category_code,
                    equipment_preset = EXCLUDED.equipment_preset,
                    inspection_direction = EXCLUDED.inspection_direction,
                    target_flow = EXCLUDED.target_flow,
                    equipment_kind = EXCLUDED.equipment_kind,
                    equipment_mark = EXCLUDED.equipment_mark,
                    default_data = EXCLUDED.default_data,
                    is_active = TRUE,
                    updated_at = NOW()
                """
            ),
            {
                "id": item["id"],
                "name": item["name"],
                "desc": item.get("description"),
                "cat": item["category_code"],
                "preset": item.get("equipment_preset"),
                "dir": item["inspection_direction"],
                "flow": item.get("target_flow", "vessel_checklist"),
                "kind": item.get("equipment_kind"),
                "mark": item.get("equipment_mark"),
                "data": json.dumps(item.get("default_data") or {}, ensure_ascii=False),
            },
        )
        count += 1
    await db.commit()
    return count


@router.get("/api/inspection-object-templates")
async def list_templates(
    category_code: Optional[str] = None,
    inspection_direction: Optional[str] = None,
    equipment_preset: Optional[str] = None,
    target_flow: Optional[str] = None,
    active_only: bool = True,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    await _ensure_table(db)
    conditions = []
    params: dict[str, Any] = {}
    if active_only:
        conditions.append("is_active = TRUE")
    if category_code:
        conditions.append("category_code = :category_code")
        params["category_code"] = category_code.strip()
    if inspection_direction:
        conditions.append("inspection_direction = :inspection_direction")
        params["inspection_direction"] = inspection_direction.strip()
    if equipment_preset:
        conditions.append(
            "(equipment_preset = :equipment_preset OR equipment_preset IS NULL)"
        )
        params["equipment_preset"] = equipment_preset.strip()
    if target_flow:
        conditions.append("target_flow = :target_flow")
        params["target_flow"] = target_flow.strip()

    where = ("WHERE " + " AND ".join(conditions)) if conditions else ""
    result = await db.execute(
        text(
            f"""
            SELECT * FROM inspection_object_templates
            {where}
            ORDER BY category_code, inspection_direction, name
            """
        ),
        params,
    )
    rows = result.fetchall()
    await db.commit()
    return [_row_to_dict(r) for r in rows]


@router.get("/api/inspection-object-templates/resolve")
async def resolve_template(
    category_code: str,
    inspection_direction: str,
    equipment_id: Optional[str] = None,
    equipment_kind: Optional[str] = None,
    equipment_mark: Optional[str] = None,
    equipment_preset: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """
    Подобрать шаблон(ы) для пары категория + направление + объект.
  Возвращает список кандидатов, отсортированных по релевантности.
    """
    await _ensure_table(db)
    eq_name = ""
    eq_preset = equipment_preset
    if equipment_id:
        try:
            eid = uuid.UUID(equipment_id.strip())
        except ValueError:
            raise HTTPException(status_code=400, detail="Некорректный equipment_id")
        er = await db.execute(select(Equipment).where(Equipment.id == eid))
        eq = er.scalar_one_or_none()
        if eq:
            eq_name = eq.name or ""

    result = await db.execute(
        text(
            """
            SELECT * FROM inspection_object_templates
            WHERE is_active = TRUE
              AND category_code = :cat
              AND inspection_direction = :dir
            ORDER BY name
            """
        ),
        {"cat": category_code.strip(), "dir": inspection_direction.strip()},
    )
    rows = result.fetchall()
    items = [_row_to_dict(r) for r in rows]

    if equipment_preset:
        items = [
            t
            for t in items
            if not t.get("equipment_preset")
            or t.get("equipment_preset") == equipment_preset
        ]

    kind_hay = (equipment_kind or eq_name or "").strip().lower()
    mark_hay = (equipment_mark or "").strip().lower()

    def _score(t: dict[str, Any]) -> int:
        s = 0
        tk = (t.get("equipment_kind") or "").lower()
        tm = (t.get("equipment_mark") or "").lower()
        if kind_hay and tk and kind_hay in tk:
            s += 3
        if mark_hay and tm and mark_hay in tm:
            s += 2
        if not tk and not tm:
            s += 1
        return s

    items.sort(key=_score, reverse=True)

    await db.commit()
    return {
        "category_code": category_code,
        "inspection_direction": inspection_direction,
        "equipment_id": equipment_id,
        "equipment_name": eq_name,
        "templates": items,
        "recommended": items[0] if items else None,
    }


@router.get("/api/inspection-object-templates/{template_id}")
async def get_template(
    template_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    await _ensure_table(db)
    result = await db.execute(
        text("SELECT * FROM inspection_object_templates WHERE id = :id"),
        {"id": template_id},
    )
    row = result.fetchone()
    await db.commit()
    if not row:
        raise HTTPException(status_code=404, detail="Шаблон не найден")
    return _row_to_dict(row)


@router.post("/api/inspection-object-templates", status_code=201)
async def create_template(
    body: InspectionObjectTemplateCreate,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    user = await _user_row(db, current_user)
    if user.role not in EDITOR_ROLES:
        raise HTTPException(status_code=403, detail="Недостаточно прав")
    await _ensure_table(db)
    flow = _validate_target_flow(body.target_flow)
    tid = f"iot-{uuid.uuid4()}"
    now = datetime.now(timezone.utc)
    await db.execute(
        text(
            """
            INSERT INTO inspection_object_templates (
                id, name, description, category_code, equipment_preset,
                inspection_direction, target_flow, equipment_kind, equipment_mark,
                default_data, created_by, updated_by, created_at, updated_at
            ) VALUES (
                :id, :name, :desc, :cat, :preset, :dir, :flow, :kind, :mark,
                CAST(:data AS jsonb), :uid, :uid, :now, :now
            )
            """
        ),
        {
            "id": tid,
            "name": body.name.strip(),
            "desc": body.description,
            "cat": body.category_code.strip(),
            "preset": body.equipment_preset,
            "dir": body.inspection_direction.strip(),
            "flow": flow,
            "kind": body.equipment_kind,
            "mark": body.equipment_mark,
            "data": json.dumps(body.default_data, ensure_ascii=False),
            "uid": user.id,
            "now": now,
        },
    )
    await db.commit()
    return await get_template(tid, db, current_user)


@router.patch("/api/inspection-object-templates/{template_id}")
async def update_template(
    template_id: str,
    body: InspectionObjectTemplateUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    user = await _user_row(db, current_user)
    if user.role not in EDITOR_ROLES:
        raise HTTPException(status_code=403, detail="Недостаточно прав")
    await _ensure_table(db)
    cur = await db.execute(
        text("SELECT id FROM inspection_object_templates WHERE id = :id"),
        {"id": template_id},
    )
    if not cur.fetchone():
        raise HTTPException(status_code=404, detail="Шаблон не найден")

    sets = ["updated_by = :uid", "updated_at = NOW()"]
    params: dict[str, Any] = {"id": template_id, "uid": user.id}
    if body.name is not None:
        sets.append("name = :name")
        params["name"] = body.name.strip()
    if body.description is not None:
        sets.append("description = :desc")
        params["desc"] = body.description
    if body.category_code is not None:
        sets.append("category_code = :cat")
        params["cat"] = body.category_code.strip()
    if body.equipment_preset is not None:
        sets.append("equipment_preset = :preset")
        params["preset"] = body.equipment_preset
    if body.inspection_direction is not None:
        sets.append("inspection_direction = :dir")
        params["dir"] = body.inspection_direction.strip()
    if body.target_flow is not None:
        sets.append("target_flow = :flow")
        params["flow"] = _validate_target_flow(body.target_flow)
    if body.equipment_kind is not None:
        sets.append("equipment_kind = :kind")
        params["kind"] = body.equipment_kind
    if body.equipment_mark is not None:
        sets.append("equipment_mark = :mark")
        params["mark"] = body.equipment_mark
    if body.default_data is not None:
        sets.append("default_data = CAST(:data AS jsonb)")
        params["data"] = json.dumps(body.default_data, ensure_ascii=False)
    if body.is_active is not None:
        sets.append("is_active = :active")
        params["active"] = body.is_active

    await db.execute(
        text(f"UPDATE inspection_object_templates SET {', '.join(sets)} WHERE id = :id"),
        params,
    )
    await db.commit()
    return await get_template(template_id, db, current_user)


@router.delete("/api/inspection-object-templates/{template_id}")
async def deactivate_template(
    template_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    user = await _user_row(db, current_user)
    if user.role not in EDITOR_ROLES:
        raise HTTPException(status_code=403, detail="Недостаточно прав")
    await _ensure_table(db)
    await db.execute(
        text(
            "UPDATE inspection_object_templates SET is_active = FALSE, updated_at = NOW(), updated_by = :uid WHERE id = :id"
        ),
        {"id": template_id, "uid": user.id},
    )
    await db.commit()
    return {"ok": True}
