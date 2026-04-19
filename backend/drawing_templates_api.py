"""API шаблонов чертежей оборудования с точками замера (П.2 ТЗ 2026-04).

Хранение:
  * Изображения — в /app/uploads/equipment_drawings/{uuid}.{ext}
  * Метаданные и точки — в таблицах drawing_templates, drawing_template_points

Возможности:
  * Библиотека общих шаблонов (equipment_type_id) + индивидуальные (equipment_id)
  * Точки замера хранятся в процентах (0-100) от размеров изображения — переносимо между устройствами
  * Версионирование (version) + дельта-sync для мобильного (GET /sync)
  * Раздача изображений с ETag / Last-Modified для офлайн-кэша
"""
import os
import uuid
import logging
import mimetypes
from io import BytesIO
from pathlib import Path
from datetime import datetime, timezone
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Query, Response
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from pydantic import BaseModel, Field

from database import get_db
from auth import verify_token
from shared import (
    ALLOWED_IMAGE_MIME_TYPES,
    normalize_image_content_type,
    read_upload_with_limit,
    log_audit,
)

logger = logging.getLogger(__name__)
router = APIRouter()

# Каталог для файлов шаблонов чертежей
UPLOAD_DIR = Path("/app/uploads/equipment_drawings")
# В режиме локальной разработки (Windows) — /app/uploads может не существовать
FALLBACK_UPLOAD_DIR = Path.cwd() / "uploads" / "equipment_drawings"

MAX_DRAWING_SIZE_BYTES = 10 * 1024 * 1024  # 10 МБ


def _ensure_upload_dir() -> Path:
    """Возвращает реально доступный каталог (с авто-fallback для локальной разработки)."""
    try:
        UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
        return UPLOAD_DIR
    except Exception:
        FALLBACK_UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
        return FALLBACK_UPLOAD_DIR


# ── Pydantic схемы ────────────────────────────────────────────────────────────

class DrawingTemplatePointIn(BaseModel):
    id: Optional[str] = None
    label: str = Field(..., max_length=50)
    point_type: str = Field(default="thickness", max_length=30)
    x_percent: float = Field(..., ge=0, le=100)
    y_percent: float = Field(..., ge=0, le=100)
    expected_value: Optional[float] = None
    notes: Optional[str] = None
    sort_order: int = 0


class DrawingTemplatePointsUpdate(BaseModel):
    points: List[DrawingTemplatePointIn] = Field(default_factory=list)


class DrawingTemplateMetaUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    equipment_type_id: Optional[str] = None
    equipment_id: Optional[str] = None
    is_active: Optional[bool] = None


# ── helpers ───────────────────────────────────────────────────────────────────

def _row_to_dict(row) -> dict:
    d = dict(row._mapping) if hasattr(row, "_mapping") else dict(row)
    for k, v in list(d.items()):
        if hasattr(v, "isoformat"):
            d[k] = v.isoformat()
        elif isinstance(v, uuid.UUID):
            d[k] = str(v)
    return d


async def _load_points(db: AsyncSession, template_id: str) -> List[dict]:
    result = await db.execute(
        text(
            "SELECT id, label, point_type, x_percent, y_percent, expected_value, notes, sort_order "
            "FROM drawing_template_points WHERE template_id = :tid "
            "ORDER BY sort_order, label"
        ),
        {"tid": template_id},
    )
    points = []
    for r in result.fetchall():
        d = _row_to_dict(r)
        # numeric → float для JSON
        for f in ("x_percent", "y_percent", "expected_value"):
            if d.get(f) is not None:
                try:
                    d[f] = float(d[f])
                except Exception:
                    pass
        points.append(d)
    return points


def _get_user_id_sql() -> str:
    # Встроенные admin/engineer/client — строковые id. Поэтому created_by может быть NULL.
    return "SELECT id FROM users WHERE username = :u LIMIT 1"


async def _resolve_user_uuid(db: AsyncSession, username: str) -> Optional[str]:
    try:
        res = await db.execute(text(_get_user_id_sql()), {"u": username})
        row = res.fetchone()
        return str(row[0]) if row else None
    except Exception:
        return None


# ── GET /api/drawing-templates ────────────────────────────────────────────────

@router.get("/api/drawing-templates")
async def list_drawing_templates(
    equipment_id: Optional[str] = Query(None),
    equipment_type_id: Optional[str] = Query(None),
    category: Optional[str] = Query(None),
    active_only: bool = Query(True),
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Список шаблонов чертежей.

    Логика фильтрации для мобильного:
      * если указан equipment_id — возвращаются (a) шаблоны, привязанные к этой единице,
        (b) общие шаблоны по типу оборудования этой единицы, (c) универсальные (без привязок)
      * если указан только equipment_type_id — шаблоны этого типа + универсальные
      * без фильтров — все активные шаблоны (для менеджера web)
    """
    try:
        where: list = []
        params: dict = {}
        if active_only:
            where.append("t.is_active = TRUE")

        if equipment_id:
            # Достанем type_id конкретного оборудования
            type_res = await db.execute(
                text("SELECT type_id FROM equipment WHERE id = :id"),
                {"id": equipment_id},
            )
            type_row = type_res.fetchone()
            eq_type_id = str(type_row[0]) if type_row and type_row[0] else None

            where.append(
                "(t.equipment_id = :eq_id "
                "OR (t.equipment_id IS NULL AND ("
                "   t.equipment_type_id = :eq_type_id "
                "   OR t.equipment_type_id IS NULL"
                ")))"
            )
            params["eq_id"] = equipment_id
            params["eq_type_id"] = eq_type_id
        elif equipment_type_id:
            where.append(
                "(t.equipment_type_id = :eq_type_id OR t.equipment_type_id IS NULL)"
            )
            params["eq_type_id"] = equipment_type_id

        if category:
            where.append("t.category = :category")
            params["category"] = category

        where_sql = ("WHERE " + " AND ".join(where)) if where else ""
        result = await db.execute(
            text(
                f"""
                SELECT
                    t.id, t.name, t.description, t.category,
                    t.equipment_type_id, t.equipment_id,
                    t.image_file_path, t.image_width, t.image_height,
                    t.mime_type, t.file_size, t.version, t.is_active,
                    t.created_at, t.updated_at,
                    et.name AS equipment_type_name,
                    eq.name AS equipment_name,
                    (SELECT COUNT(*) FROM drawing_template_points p WHERE p.template_id = t.id) AS points_count
                FROM drawing_templates t
                LEFT JOIN equipment_types et ON et.id = t.equipment_type_id
                LEFT JOIN equipment eq ON eq.id = t.equipment_id
                {where_sql}
                ORDER BY t.updated_at DESC
                """
            ),
            params,
        )
        items = [_row_to_dict(r) for r in result.fetchall()]
        return {"items": items, "total": len(items)}
    except Exception as exc:
        logger.error("list_drawing_templates error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


# ── GET /api/drawing-templates/sync ───────────────────────────────────────────

@router.get("/api/drawing-templates/sync")
async def sync_drawing_templates(
    since: Optional[str] = Query(None, description="ISO timestamp — вернуть изменения после этого момента"),
    equipment_ids: Optional[str] = Query(None, description="CSV equipment_id — шаблоны только для этих единиц"),
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Дельта-sync для мобильного: лёгкий ответ без изображений (только id + version + updated_at)."""
    try:
        where = ["t.is_active = TRUE"]
        params: dict = {}
        if since:
            where.append("t.updated_at > :since")
            params["since"] = since
        if equipment_ids:
            ids = [s.strip() for s in equipment_ids.split(",") if s.strip()]
            if ids:
                # подтянем ещё type_id для этих единиц
                type_res = await db.execute(
                    text("SELECT DISTINCT type_id FROM equipment WHERE id = ANY(:ids)"),
                    {"ids": ids},
                )
                type_ids = [str(r[0]) for r in type_res.fetchall() if r[0]]
                where.append(
                    "(t.equipment_id = ANY(:eq_ids) "
                    "OR (t.equipment_id IS NULL AND ("
                    "   t.equipment_type_id = ANY(:eq_type_ids) "
                    "   OR t.equipment_type_id IS NULL"
                    ")))"
                )
                params["eq_ids"] = ids
                params["eq_type_ids"] = type_ids

        where_sql = ("WHERE " + " AND ".join(where)) if where else ""
        result = await db.execute(
            text(
                f"""
                SELECT t.id, t.version, t.updated_at, t.name, t.category,
                       t.equipment_id, t.equipment_type_id,
                       t.image_width, t.image_height, t.file_size
                FROM drawing_templates t
                {where_sql}
                ORDER BY t.updated_at DESC
                """
            ),
            params,
        )
        items = [_row_to_dict(r) for r in result.fetchall()]
        return {
            "items": items,
            "server_time": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as exc:
        logger.error("sync_drawing_templates error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


# ── GET /api/drawing-templates/{id} ───────────────────────────────────────────

@router.get("/api/drawing-templates/{template_id}")
async def get_drawing_template(
    template_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Детали шаблона + все точки замера."""
    try:
        result = await db.execute(
            text(
                """
                SELECT t.*,
                       et.name AS equipment_type_name,
                       eq.name AS equipment_name
                FROM drawing_templates t
                LEFT JOIN equipment_types et ON et.id = t.equipment_type_id
                LEFT JOIN equipment eq ON eq.id = t.equipment_id
                WHERE t.id = :id
                """
            ),
            {"id": template_id},
        )
        row = result.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        data = _row_to_dict(row)
        data["points"] = await _load_points(db, template_id)
        return data
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("get_drawing_template error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


# ── GET /api/drawing-templates/{id}/image ─────────────────────────────────────

@router.get("/api/drawing-templates/{template_id}/image")
async def get_drawing_template_image(
    template_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Отдать файл изображения шаблона."""
    try:
        result = await db.execute(
            text("SELECT image_file_path, mime_type, version FROM drawing_templates WHERE id = :id"),
            {"id": template_id},
        )
        row = result.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        path = row[0]
        mime = row[1] or "image/png"
        version = row[2]

        if not path or not os.path.exists(path):
            # Пробуем относительный путь внутри локального fallback-каталога
            alt = FALLBACK_UPLOAD_DIR / os.path.basename(path or "")
            if alt.exists():
                path = str(alt)
            else:
                raise HTTPException(status_code=404, detail="Файл изображения не найден на диске")

        # ETag на основе id+version — для офлайн-кэша мобильного
        headers = {"ETag": f'"{template_id}-v{version}"', "Cache-Control": "private, max-age=604800"}
        return FileResponse(path, media_type=mime, headers=headers)
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("get_drawing_template_image error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


# ── POST /api/drawing-templates ───────────────────────────────────────────────

@router.post("/api/drawing-templates", status_code=201)
async def create_drawing_template(
    file: UploadFile = File(...),
    name: str = Form(...),
    description: Optional[str] = Form(None),
    category: Optional[str] = Form(None),
    equipment_type_id: Optional[str] = Form(None),
    equipment_id: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Создать новый шаблон чертежа (multipart: файл + метаданные)."""
    try:
        mime = normalize_image_content_type(file)
        if not mime or mime not in ALLOWED_IMAGE_MIME_TYPES:
            raise HTTPException(status_code=400, detail="Поддерживаются только PNG и JPEG")

        content = await read_upload_with_limit(file, MAX_DRAWING_SIZE_BYTES)
        file_size = len(content)

        # Определяем размеры, если Pillow доступен
        width = height = None
        try:
            from PIL import Image
            img = Image.open(BytesIO(content))
            width, height = img.size
        except Exception:
            pass

        upload_dir = _ensure_upload_dir()
        ext = ".png" if mime == "image/png" else ".jpg"
        template_id = str(uuid.uuid4())
        file_path = upload_dir / f"{template_id}{ext}"
        file_path.write_bytes(content)

        created_by_uuid = await _resolve_user_uuid(db, current_user)

        await db.execute(
            text(
                """
                INSERT INTO drawing_templates (
                    id, name, description, category,
                    equipment_type_id, equipment_id,
                    image_file_path, image_width, image_height, mime_type, file_size,
                    version, is_active, created_by, created_at, updated_at
                ) VALUES (
                    :id, :name, :description, :category,
                    :eq_type_id, :eq_id,
                    :path, :w, :h, :mime, :size,
                    1, TRUE, :created_by, NOW(), NOW()
                )
                """
            ),
            {
                "id": template_id,
                "name": name,
                "description": description,
                "category": category,
                "eq_type_id": equipment_type_id or None,
                "eq_id": equipment_id or None,
                "path": str(file_path),
                "w": width,
                "h": height,
                "mime": mime,
                "size": file_size,
                "created_by": created_by_uuid,
            },
        )
        await log_audit(
            db,
            user_id=uuid.UUID(created_by_uuid) if created_by_uuid else None,
            action="CREATE",
            entity_type="drawing_template",
            entity_id=uuid.UUID(template_id),
            details={"name": name, "size": file_size},
        )
        await db.commit()

        return await get_drawing_template(template_id, db, current_user)
    except HTTPException:
        await db.rollback()
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("create_drawing_template error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


# ── PUT /api/drawing-templates/{id} ───────────────────────────────────────────

@router.put("/api/drawing-templates/{template_id}")
async def update_drawing_template_meta(
    template_id: str,
    body: DrawingTemplateMetaUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Обновить метаданные шаблона (без файла изображения)."""
    try:
        check = await db.execute(
            text("SELECT id FROM drawing_templates WHERE id = :id"),
            {"id": template_id},
        )
        if not check.fetchone():
            raise HTTPException(status_code=404, detail="Шаблон не найден")

        sets = ["updated_at = NOW()", "version = version + 1"]
        params: dict = {"id": template_id}
        for f in ("name", "description", "category", "is_active"):
            v = getattr(body, f)
            if v is not None:
                sets.append(f"{f} = :{f}")
                params[f] = v
        if body.equipment_type_id is not None:
            sets.append("equipment_type_id = :equipment_type_id")
            params["equipment_type_id"] = body.equipment_type_id or None
        if body.equipment_id is not None:
            sets.append("equipment_id = :equipment_id")
            params["equipment_id"] = body.equipment_id or None

        await db.execute(
            text(f"UPDATE drawing_templates SET {', '.join(sets)} WHERE id = :id"),
            params,
        )
        await db.commit()
        return await get_drawing_template(template_id, db, current_user)
    except HTTPException:
        await db.rollback()
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("update_drawing_template_meta error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


# ── PUT /api/drawing-templates/{id}/image — заменить файл ─────────────────────

@router.put("/api/drawing-templates/{template_id}/image")
async def replace_drawing_template_image(
    template_id: str,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    try:
        check = await db.execute(
            text("SELECT image_file_path FROM drawing_templates WHERE id = :id"),
            {"id": template_id},
        )
        row = check.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Шаблон не найден")
        old_path = row[0]

        mime = normalize_image_content_type(file)
        if not mime or mime not in ALLOWED_IMAGE_MIME_TYPES:
            raise HTTPException(status_code=400, detail="Поддерживаются только PNG и JPEG")
        content = await read_upload_with_limit(file, MAX_DRAWING_SIZE_BYTES)

        width = height = None
        try:
            from PIL import Image
            img = Image.open(BytesIO(content))
            width, height = img.size
        except Exception:
            pass

        upload_dir = _ensure_upload_dir()
        ext = ".png" if mime == "image/png" else ".jpg"
        file_path = upload_dir / f"{template_id}{ext}"
        file_path.write_bytes(content)

        # Удаляем старый файл, если путь отличается
        try:
            if old_path and str(old_path) != str(file_path) and os.path.exists(old_path):
                os.remove(old_path)
        except Exception:
            pass

        await db.execute(
            text(
                """
                UPDATE drawing_templates
                SET image_file_path = :path, image_width = :w, image_height = :h,
                    mime_type = :mime, file_size = :size,
                    version = version + 1, updated_at = NOW()
                WHERE id = :id
                """
            ),
            {
                "id": template_id,
                "path": str(file_path),
                "w": width,
                "h": height,
                "mime": mime,
                "size": len(content),
            },
        )
        await db.commit()
        return await get_drawing_template(template_id, db, current_user)
    except HTTPException:
        await db.rollback()
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("replace_drawing_template_image error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


# ── PUT /api/drawing-templates/{id}/points — bulk ─────────────────────────────

@router.put("/api/drawing-templates/{template_id}/points")
async def update_drawing_template_points(
    template_id: str,
    body: DrawingTemplatePointsUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Заменить все точки шаблона (атомарно). Инкрементирует version."""
    try:
        check = await db.execute(
            text("SELECT id FROM drawing_templates WHERE id = :id"),
            {"id": template_id},
        )
        if not check.fetchone():
            raise HTTPException(status_code=404, detail="Шаблон не найден")

        await db.execute(
            text("DELETE FROM drawing_template_points WHERE template_id = :tid"),
            {"tid": template_id},
        )

        for idx, p in enumerate(body.points):
            await db.execute(
                text(
                    """
                    INSERT INTO drawing_template_points (
                        id, template_id, label, point_type,
                        x_percent, y_percent, expected_value, notes, sort_order
                    ) VALUES (
                        :id, :tid, :label, :pt, :x, :y, :ev, :notes, :so
                    )
                    """
                ),
                {
                    "id": p.id or str(uuid.uuid4()),
                    "tid": template_id,
                    "label": p.label,
                    "pt": p.point_type,
                    "x": p.x_percent,
                    "y": p.y_percent,
                    "ev": p.expected_value,
                    "notes": p.notes,
                    "so": p.sort_order if p.sort_order is not None else idx,
                },
            )

        await db.execute(
            text(
                "UPDATE drawing_templates SET version = version + 1, updated_at = NOW() WHERE id = :id"
            ),
            {"id": template_id},
        )
        await db.commit()
        return await get_drawing_template(template_id, db, current_user)
    except HTTPException:
        await db.rollback()
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("update_drawing_template_points error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))


# ── DELETE /api/drawing-templates/{id} ────────────────────────────────────────

@router.delete("/api/drawing-templates/{template_id}", status_code=204)
async def delete_drawing_template(
    template_id: str,
    hard: bool = Query(False, description="Жёсткое удаление файла и записи"),
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Мягкое удаление (is_active=False) или жёсткое с удалением файла."""
    try:
        if hard:
            res = await db.execute(
                text("SELECT image_file_path FROM drawing_templates WHERE id = :id"),
                {"id": template_id},
            )
            row = res.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Шаблон не найден")
            path = row[0]
            await db.execute(
                text("DELETE FROM drawing_templates WHERE id = :id"),
                {"id": template_id},
            )
            try:
                if path and os.path.exists(path):
                    os.remove(path)
            except Exception:
                pass
        else:
            result = await db.execute(
                text(
                    "UPDATE drawing_templates SET is_active = FALSE, updated_at = NOW() "
                    "WHERE id = :id"
                ),
                {"id": template_id},
            )
            if result.rowcount == 0:
                raise HTTPException(status_code=404, detail="Шаблон не найден")
        await db.commit()
    except HTTPException:
        await db.rollback()
        raise
    except Exception as exc:
        await db.rollback()
        logger.error("delete_drawing_template error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=str(exc))
