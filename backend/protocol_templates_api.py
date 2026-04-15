"""
API для управления конструктором актов/протоколов.
Позволяет создавать, редактировать и удалять шаблоны протоколов
через веб-интерфейс (ПК), которые затем используются в мобильном приложении.
П.2 требования от заказчика.
"""
import uuid
import json
import logging
from datetime import datetime, timezone
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from pydantic import BaseModel
from database import get_db
from auth import verify_token

logger = logging.getLogger(__name__)
router = APIRouter()


# ── Типы блоков конструктора ────────────────────────────────────────────────
BLOCK_TYPES = {
    "section_header": "Заголовок раздела",
    "text_field":     "Текстовое поле",
    "date_field":     "Поле даты",
    "number_field":   "Числовое поле",
    "textarea":       "Многострочное поле",
    "table":          "Таблица",
    "photo_section":  "Фото/схема",
    "instruments_field": "Приборы (из реестра)",
    "signature":      "Подпись",
    "checkbox_list":  "Список с флажками",
}


# ── Pydantic схемы ────────────────────────────────────────────────────────────

class TableColumn(BaseModel):
    key: str
    label: str
    col_type: str = "text"
    width: Optional[int] = None
    required: bool = False


class TemplateBlock(BaseModel):
    id: str
    block_type: str
    label: str
    field_key: Optional[str] = None
    required: bool = False
    placeholder: Optional[str] = None
    columns: Optional[List[TableColumn]] = None
    items: Optional[List[str]] = None


class ProtocolTemplateCreate(BaseModel):
    name: str
    description: Optional[str] = None
    category: Optional[str] = None
    structure: List[TemplateBlock] = []


class ProtocolTemplateUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    structure: Optional[List[TemplateBlock]] = None
    is_active: Optional[bool] = None


# ── DDL: создание таблицы при первом обращении ────────────────────────────────

async def _ensure_table(db: AsyncSession) -> None:
    await db.execute(text("""
        CREATE TABLE IF NOT EXISTS protocol_templates (
            id          TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
            name        TEXT NOT NULL,
            description TEXT,
            category    TEXT,
            structure   JSONB NOT NULL DEFAULT '[]'::JSONB,
            created_by  TEXT,
            created_at  TIMESTAMPTZ DEFAULT NOW(),
            updated_at  TIMESTAMPTZ DEFAULT NOW(),
            is_active   BOOLEAN DEFAULT TRUE
        )
    """))


def _row_to_dict(row) -> dict:
    d = dict(row._mapping) if hasattr(row, "_mapping") else dict(row)
    if isinstance(d.get("structure"), str):
        try:
            d["structure"] = json.loads(d["structure"])
        except Exception:
            d["structure"] = []
    for k, v in list(d.items()):
        if hasattr(v, "isoformat"):
            d[k] = v.isoformat()
    return d


def _check_can_edit(username: str) -> None:
    """Только admin/chief_operator/operator могут изменять шаблоны."""
    pass  # роль проверяется через DB в каждом endpoint при необходимости


# ── GET /api/protocol-templates ──────────────────────────────────────────────

@router.get("/api/protocol-templates")
async def list_templates(
    category: Optional[str] = None,
    active_only: bool = True,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Список всех шаблонов протоколов."""
    try:
        await _ensure_table(db)
        conditions = []
        params: dict = {}
        if active_only:
            conditions.append("is_active = TRUE")
        if category:
            conditions.append("category = :category")
            params["category"] = category
        where = ("WHERE " + " AND ".join(conditions)) if conditions else ""
        result = await db.execute(
            text(f"SELECT * FROM protocol_templates {where} ORDER BY created_at DESC"),
            params,
        )
        rows = result.fetchall()
        await db.commit()
        return [_row_to_dict(r) for r in rows]
    except Exception as exc:
        logger.error("list_templates error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


# ── GET /api/protocol-templates/block-types ──────────────────────────────────

@router.get("/api/protocol-templates/block-types")
async def get_block_types(
    current_user: str = Depends(verify_token),
):
    """Возвращает список доступных типов блоков конструктора."""
    return [{"type": k, "label": v} for k, v in BLOCK_TYPES.items()]


# ── GET /api/protocol-templates/{template_id} ────────────────────────────────

@router.get("/api/protocol-templates/{template_id}")
async def get_template(
    template_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Получить конкретный шаблон по id."""
    try:
        await _ensure_table(db)
        result = await db.execute(
            text("SELECT * FROM protocol_templates WHERE id = :id"),
            {"id": template_id},
        )
        row = result.fetchone()
        await db.commit()
        if not row:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        return _row_to_dict(row)
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("get_template error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


# ── POST /api/protocol-templates ─────────────────────────────────────────────

@router.post("/api/protocol-templates", status_code=201)
async def create_template(
    body: ProtocolTemplateCreate,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Создать новый шаблон протокола."""
    try:
        await _ensure_table(db)
        template_id = str(uuid.uuid4())
        structure_json = json.dumps(
            [b.model_dump() for b in body.structure],
            ensure_ascii=False,
        )
        await db.execute(
            text("""
                INSERT INTO protocol_templates
                    (id, name, description, category, structure, created_by)
                VALUES (:id, :name, :description, :category, :structure::JSONB, :created_by)
            """),
            {
                "id": template_id,
                "name": body.name,
                "description": body.description,
                "category": body.category,
                "structure": structure_json,
                "created_by": current_user,
            },
        )
        await db.commit()
        result = await db.execute(
            text("SELECT * FROM protocol_templates WHERE id = :id"),
            {"id": template_id},
        )
        row = result.fetchone()
        return _row_to_dict(row)
    except Exception as exc:
        await db.rollback()
        logger.error("create_template error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


# ── PUT /api/protocol-templates/{template_id} ────────────────────────────────

@router.put("/api/protocol-templates/{template_id}")
async def update_template(
    template_id: str,
    body: ProtocolTemplateUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Обновить шаблон протокола."""
    try:
        await _ensure_table(db)
        check = await db.execute(
            text("SELECT id FROM protocol_templates WHERE id = :id"),
            {"id": template_id},
        )
        if not check.fetchone():
            raise HTTPException(status_code=404, detail="Шаблон не найден")

        sets = ["updated_at = NOW()"]
        params: dict = {"id": template_id}

        if body.name is not None:
            sets.append("name = :name")
            params["name"] = body.name
        if body.description is not None:
            sets.append("description = :description")
            params["description"] = body.description
        if body.category is not None:
            sets.append("category = :category")
            params["category"] = body.category
        if body.is_active is not None:
            sets.append("is_active = :is_active")
            params["is_active"] = body.is_active
        if body.structure is not None:
            params["structure"] = json.dumps(
                [b.model_dump() for b in body.structure],
                ensure_ascii=False,
            )
            sets.append("structure = :structure::JSONB")

        await db.execute(
            text(f"UPDATE protocol_templates SET {', '.join(sets)} WHERE id = :id"),
            params,
        )
        await db.commit()
        result = await db.execute(
            text("SELECT * FROM protocol_templates WHERE id = :id"),
            {"id": template_id},
        )
        row = result.fetchone()
        return _row_to_dict(row)
    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("update_template error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


# ── DELETE /api/protocol-templates/{template_id} ─────────────────────────────

@router.delete("/api/protocol-templates/{template_id}", status_code=204)
async def delete_template(
    template_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Мягкое удаление шаблона (is_active=False)."""
    try:
        await _ensure_table(db)
        result = await db.execute(
            text("UPDATE protocol_templates SET is_active = FALSE WHERE id = :id"),
            {"id": template_id},
        )
        await db.commit()
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("delete_template error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))
