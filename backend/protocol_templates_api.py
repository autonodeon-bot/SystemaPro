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
from sqlalchemy import text, select, or_
from pydantic import BaseModel
from database import get_db
from auth import verify_token
from models import User

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
    status: str = "draft"


class ProtocolTemplateUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    structure: Optional[List[TemplateBlock]] = None
    is_active: Optional[bool] = None
    status: Optional[str] = None


ALLOWED_TEMPLATE_EDITOR_ROLES = {"admin", "chief_operator", "operator"}
ALLOWED_TEMPLATE_STATUSES = {"draft", "published", "archived"}


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
    await db.execute(text("ALTER TABLE protocol_templates ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'draft'"))
    await db.execute(text("ALTER TABLE protocol_templates ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1"))
    await db.execute(text("""
        CREATE TABLE IF NOT EXISTS protocol_template_versions (
            id BIGSERIAL PRIMARY KEY,
            template_id TEXT NOT NULL,
            version INTEGER NOT NULL,
            snapshot JSONB NOT NULL,
            created_by TEXT,
            created_at TIMESTAMPTZ DEFAULT NOW()
        )
    """))
    await db.execute(text("""
        CREATE UNIQUE INDEX IF NOT EXISTS ux_protocol_template_versions_tpl_ver
        ON protocol_template_versions(template_id, version)
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


async def _get_user(db: AsyncSession, username: str) -> Optional[User]:
    result = await db.execute(
        select(User).where(or_(User.username == username, User.email == username))
    )
    return result.scalar_one_or_none()


def _ensure_can_edit(user: Optional[User]) -> None:
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if getattr(user, "role", None) not in ALLOWED_TEMPLATE_EDITOR_ROLES:
        raise HTTPException(status_code=403, detail="Недостаточно прав для редактирования шаблонов")


async def _append_version_snapshot(
    db: AsyncSession,
    template_id: str,
    version: int,
    changed_by: str,
) -> None:
    row = await db.execute(
        text("SELECT * FROM protocol_templates WHERE id = :id"),
        {"id": template_id},
    )
    current = row.fetchone()
    if not current:
        return
    snapshot = _row_to_dict(current)
    await db.execute(
        text("""
            INSERT INTO protocol_template_versions (template_id, version, snapshot, created_by)
            VALUES (:template_id, :version, :snapshot::JSONB, :created_by)
            ON CONFLICT (template_id, version) DO UPDATE SET
                snapshot = EXCLUDED.snapshot,
                created_by = EXCLUDED.created_by,
                created_at = NOW()
        """),
        {
            "template_id": template_id,
            "version": version,
            "snapshot": json.dumps(snapshot, ensure_ascii=False),
            "created_by": changed_by,
        },
    )


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
        user = await _get_user(db, current_user)
        _ensure_can_edit(user)
        template_id = str(uuid.uuid4())
        status = (body.status or "draft").lower()
        if status not in ALLOWED_TEMPLATE_STATUSES:
            raise HTTPException(status_code=400, detail="Некорректный статус шаблона")
        structure_json = json.dumps(
            [b.model_dump() for b in body.structure],
            ensure_ascii=False,
        )
        await db.execute(
            text("""
                INSERT INTO protocol_templates
                    (id, name, description, category, structure, created_by, status, version)
                VALUES (:id, :name, :description, :category, :structure::JSONB, :created_by, :status, 1)
            """),
            {
                "id": template_id,
                "name": body.name,
                "description": body.description,
                "category": body.category,
                "structure": structure_json,
                "created_by": current_user,
                "status": status,
            },
        )
        await _append_version_snapshot(db, template_id, 1, current_user)
        result = await db.execute(text("SELECT * FROM protocol_templates WHERE id = :id"), {"id": template_id})
        row = result.fetchone()
        await db.commit()
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
        user = await _get_user(db, current_user)
        _ensure_can_edit(user)
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
        if body.status is not None:
            status = body.status.lower()
            if status not in ALLOWED_TEMPLATE_STATUSES:
                raise HTTPException(status_code=400, detail="Некорректный статус шаблона")
            sets.append("status = :status")
            params["status"] = status
        if body.structure is not None:
            params["structure"] = json.dumps(
                [b.model_dump() for b in body.structure],
                ensure_ascii=False,
            )
            sets.append("structure = :structure::JSONB")

        sets.append("version = version + 1")

        await db.execute(
            text(f"UPDATE protocol_templates SET {', '.join(sets)} WHERE id = :id"),
            params,
        )
        result = await db.execute(
            text("SELECT * FROM protocol_templates WHERE id = :id"),
            {"id": template_id},
        )
        row = result.fetchone()
        row_dict = _row_to_dict(row)
        await _append_version_snapshot(db, template_id, int(row_dict.get("version") or 1), current_user)
        await db.commit()
        return row_dict
    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("update_template error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/api/protocol-templates/{template_id}/versions")
async def list_template_versions(
    template_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """История версий шаблона."""
    try:
        await _ensure_table(db)
        user = await _get_user(db, current_user)
        _ensure_can_edit(user)
        result = await db.execute(
            text(
                """
                SELECT version, created_by, created_at
                FROM protocol_template_versions
                WHERE template_id = :template_id
                ORDER BY version DESC
                """
            ),
            {"template_id": template_id},
        )
        rows = result.fetchall()
        await db.commit()
        return [
            {
                "version": int(r[0]),
                "created_by": r[1],
                "created_at": r[2].isoformat() if hasattr(r[2], "isoformat") else r[2],
            }
            for r in rows
        ]
    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("list_template_versions error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/api/protocol-templates/{template_id}/publish")
async def publish_template(
    template_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Публикация шаблона (draft -> published)."""
    try:
        await _ensure_table(db)
        user = await _get_user(db, current_user)
        _ensure_can_edit(user)
        result = await db.execute(
            text(
                """
                UPDATE protocol_templates
                SET status = 'published', is_active = TRUE, version = version + 1, updated_at = NOW()
                WHERE id = :id
                RETURNING version
                """
            ),
            {"id": template_id},
        )
        row = result.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        await _append_version_snapshot(db, template_id, int(row[0]), current_user)
        await db.commit()
        return {"status": "published", "version": int(row[0])}
    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("publish_template error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/api/protocol-templates/{template_id}/restore/{version}")
async def restore_template_version(
    template_id: str,
    version: int,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Откат шаблона к выбранной версии."""
    try:
        await _ensure_table(db)
        user = await _get_user(db, current_user)
        _ensure_can_edit(user)
        row = await db.execute(
            text(
                """
                SELECT snapshot
                FROM protocol_template_versions
                WHERE template_id = :template_id AND version = :version
                """
            ),
            {"template_id": template_id, "version": version},
        )
        snap_row = row.fetchone()
        if not snap_row:
            raise HTTPException(status_code=404, detail="Версия не найдена")
        snapshot = snap_row[0] or {}
        if isinstance(snapshot, str):
            snapshot = json.loads(snapshot)

        structure = json.dumps(snapshot.get("structure") or [], ensure_ascii=False)
        result = await db.execute(
            text(
                """
                UPDATE protocol_templates
                SET name = :name,
                    description = :description,
                    category = :category,
                    structure = :structure::JSONB,
                    is_active = :is_active,
                    status = :status,
                    version = version + 1,
                    updated_at = NOW()
                WHERE id = :id
                RETURNING version
                """
            ),
            {
                "id": template_id,
                "name": snapshot.get("name"),
                "description": snapshot.get("description"),
                "category": snapshot.get("category"),
                "structure": structure,
                "is_active": bool(snapshot.get("is_active", True)),
                "status": snapshot.get("status") or "draft",
            },
        )
        restored = result.fetchone()
        if not restored:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        new_version = int(restored[0])
        await _append_version_snapshot(db, template_id, new_version, current_user)
        await db.commit()
        return {"status": "restored", "from_version": version, "version": new_version}
    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("restore_template_version error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/api/protocol-templates/{template_id}/diff")
async def get_template_diff(
    template_id: str,
    from_version: int,
    to_version: int,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Сравнение двух версий шаблона по ключам блоков."""
    try:
        await _ensure_table(db)
        user = await _get_user(db, current_user)
        _ensure_can_edit(user)

        result = await db.execute(
            text(
                """
                SELECT version, snapshot
                FROM protocol_template_versions
                WHERE template_id = :template_id
                  AND version IN (:from_version, :to_version)
                """
            ),
            {
                "template_id": template_id,
                "from_version": from_version,
                "to_version": to_version,
            },
        )
        rows = result.fetchall()
        versions: dict[int, dict] = {}
        for v, snapshot in rows:
            parsed = snapshot or {}
            if isinstance(parsed, str):
                parsed = json.loads(parsed)
            versions[int(v)] = parsed

        if from_version not in versions or to_version not in versions:
            raise HTTPException(status_code=404, detail="Одна из версий не найдена")

        def _field_keys(snapshot: dict) -> set[str]:
            structure = snapshot.get("structure") or []
            keys = set()
            for b in structure:
                if isinstance(b, dict):
                    key = str(b.get("field_key") or b.get("id") or "").strip()
                    if key:
                        keys.add(key)
            return keys

        base_keys = _field_keys(versions[from_version])
        target_keys = _field_keys(versions[to_version])

        await db.commit()
        return {
            "from_version": from_version,
            "to_version": to_version,
            "added": sorted(target_keys - base_keys),
            "removed": sorted(base_keys - target_keys),
            "unchanged_count": len(base_keys & target_keys),
        }
    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("get_template_diff error: %s", exc, exc_info=True)
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
        user = await _get_user(db, current_user)
        _ensure_can_edit(user)
        result = await db.execute(
            text(
                """
                UPDATE protocol_templates
                SET is_active = FALSE, status = 'archived', version = version + 1, updated_at = NOW()
                WHERE id = :id
                RETURNING version
                """
            ),
            {"id": template_id},
        )
        row = result.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        await _append_version_snapshot(db, template_id, int(row[0]), current_user)
        await db.commit()
    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("delete_template error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))
