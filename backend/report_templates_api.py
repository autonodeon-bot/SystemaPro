"""API для управления шаблонами (правилами) отчетов.

MVP без миграций БД: шаблоны храним в JSON-файле на диске сервера.
"""

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from pathlib import Path
from datetime import datetime
import uuid
import json

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from auth import verify_token
from database import get_db
from models import User

router = APIRouter(prefix="/api/report-templates", tags=["report-templates"])

# Храним рядом с отчетами (том /app/reports примонтирован в docker-compose)
TEMPLATES_FILE = Path("/app/reports/report_templates.json")
ASSETS_DIR = Path("/app/reports/assets")
DEFAULT_LOGO_PATH = str(ASSETS_DIR / "yutar_logo.png")


def _load_templates() -> List[Dict[str, Any]]:
    try:
        if not TEMPLATES_FILE.exists():
            return []
        return json.loads(TEMPLATES_FILE.read_text(encoding="utf-8") or "[]")
    except Exception:
        return []


def _save_templates(items: List[Dict[str, Any]]) -> None:
    TEMPLATES_FILE.parent.mkdir(parents=True, exist_ok=True)
    TEMPLATES_FILE.write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")


class ReportTemplateCreate(BaseModel):
    name: str
    report_type: str  # DIAGNOSTICS / EXPERTISE / TECHNICAL ...
    format: str = "docx"  # docx/pdf
    equipment_type_id: Optional[str] = None  # если null -> шаблон по умолчанию
    is_active: bool = True
    definition: Optional[Dict[str, Any]] = None  # JSON описание макета


class ReportTemplateUpdate(BaseModel):
    name: Optional[str] = None
    report_type: Optional[str] = None
    format: Optional[str] = None
    equipment_type_id: Optional[str] = None
    is_active: Optional[bool] = None
    definition: Optional[Dict[str, Any]] = None


async def _require_admin(username: str, db: AsyncSession) -> User:
    res = await db.execute(select(User).where(User.username == username))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if getattr(user, "role", None) != "admin":
        raise HTTPException(status_code=403, detail="Admin only")
    return user


@router.get("", response_model=List[dict])
async def list_templates(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _require_admin(username, db)
    return _load_templates()


@router.post("", response_model=dict)
async def create_template(
    body: ReportTemplateCreate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _require_admin(username, db)
    items = _load_templates()
    now = datetime.utcnow().isoformat()
    new_item = {
        "id": str(uuid.uuid4()),
        "name": body.name,
        "report_type": body.report_type,
        "format": body.format,
        "equipment_type_id": body.equipment_type_id,
        "is_active": bool(body.is_active),
        "definition": body.definition or {
            "logo_path": DEFAULT_LOGO_PATH,
            "fields": {
                "contractor_name": 'ООО «ЮТАР»',
                "director_title": 'Генеральный директор',
                "director_name": '__________________',
                "report_city": 'г. Урай',
            },
            "sections": [
                {"key": "title", "enabled": True},
                {"key": "toc", "enabled": True},
                {"key": "sections_1_15", "enabled": True},
                {"key": "appendices", "enabled": True},
            ],
        },
        "created_at": now,
        "updated_at": now,
        "created_by": username,
    }
    items.insert(0, new_item)
    _save_templates(items)
    return new_item


@router.put("/{template_id}", response_model=dict)
async def update_template(
    template_id: str,
    body: ReportTemplateUpdate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _require_admin(username, db)
    items = _load_templates()
    found = None
    for it in items:
        if it.get("id") == template_id:
            found = it
            break
    if not found:
        raise HTTPException(status_code=404, detail="Шаблон не найден")

    if body.name is not None:
        found["name"] = body.name
    if body.report_type is not None:
        found["report_type"] = body.report_type
    if body.format is not None:
        found["format"] = body.format
    if body.equipment_type_id is not None:
        found["equipment_type_id"] = body.equipment_type_id
    if body.is_active is not None:
        found["is_active"] = bool(body.is_active)
    if body.definition is not None:
        found["definition"] = body.definition

    found["updated_at"] = datetime.utcnow().isoformat()
    found["updated_by"] = username

    _save_templates(items)
    return found


@router.delete("/{template_id}", response_model=dict)
async def delete_template(
    template_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _require_admin(username, db)
    items = _load_templates()
    new_items = [it for it in items if it.get("id") != template_id]
    _save_templates(new_items)
    return {"deleted": 1 if len(new_items) != len(items) else 0}


@router.get("/resolve", response_model=dict)
async def resolve_template(
    equipment_type_id: Optional[str] = None,
    fallback_report_type: str = "DIAGNOSTICS",
    fallback_format: str = "docx",
    username: str = Depends(verify_token),
):
    """Подобрать шаблон: сначала по equipment_type_id, иначе общий (equipment_type_id=null).

    Также учитываем report_type/format: если в файле несколько шаблонов.
    """
    items = [it for it in _load_templates() if it.get("is_active")]

    # Сначала пытаемся найти по type+report_type+format
    chosen = None
    if equipment_type_id:
        for it in items:
            if (it.get("equipment_type_id") or None) == equipment_type_id and (it.get("report_type") or "") == fallback_report_type and (it.get("format") or "") == fallback_format:
                chosen = it
                break

    if not chosen and equipment_type_id:
        for it in items:
            if (it.get("equipment_type_id") or None) == equipment_type_id:
                chosen = it
                break

    if not chosen:
        for it in items:
            if it.get("equipment_type_id") in (None, "", "null") and (it.get("report_type") or "") == fallback_report_type and (it.get("format") or "") == fallback_format:
                chosen = it
                break

    if not chosen:
        for it in items:
            if it.get("equipment_type_id") in (None, "", "null"):
                chosen = it
                break

    if not chosen:
        return {
            "id": None,
            "name": "По умолчанию",
            "report_type": fallback_report_type,
            "format": fallback_format,
        }

    return {
        "id": chosen.get("id"),
        "name": chosen.get("name"),
        "report_type": chosen.get("report_type") or fallback_report_type,
        "format": chosen.get("format") or fallback_format,
        "equipment_type_id": chosen.get("equipment_type_id"),
        "definition": chosen.get("definition") or {},
    }


@router.post("/assets/logo", response_model=dict)
async def upload_logo_asset(
    file: UploadFile = File(...),
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """
    Загрузить логотип для отчетов (в /app/reports/assets).
    Возвращает путь, который можно указать в definition.logo_path.
    """
    await _require_admin(username, db)
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)

    # Всегда сохраняем как .png (для предсказуемости)
    target = ASSETS_DIR / "yutar_logo.png"
    content = await file.read()
    target.write_bytes(content)
    return {"path": str(target)}
