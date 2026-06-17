"""
Редактируемая структура меню диагностики (мобильное «Протокол → создать»).
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import text, select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from auth import verify_token
from database import get_db
from diagnostic_menu_default import DEFAULT_DIAGNOSTIC_MENU, build_default_diagnostic_menu
from models import User

logger = logging.getLogger(__name__)
router = APIRouter(tags=["diagnostic-menu"])

MENU_ROW_ID = "default"
EDITOR_ROLES = {"admin", "chief_operator"}


class DiagnosticMenuPayload(BaseModel):
    version: int = 1
    new_protocol_description: str = ""
    quick_control_tree: list[dict[str, Any]] = Field(default_factory=list)
    object_categories: list[dict[str, Any]] = Field(default_factory=list)
    create_menu_actions: list[dict[str, Any]] = Field(default_factory=list)


async def _ensure_table(db: AsyncSession) -> None:
    await db.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS diagnostic_menu_config (
                id TEXT PRIMARY KEY DEFAULT 'default',
                draft_payload JSONB,
                published_payload JSONB NOT NULL,
                published_version INTEGER NOT NULL DEFAULT 1,
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_by TEXT
            )
            """
        )
    )


async def _editor_user(db: AsyncSession, username: str) -> User:
    r = await db.execute(
        select(User).where(or_(User.username == username, User.email == username))
    )
    user = r.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=401, detail="Пользователь не найден")
    if user.role not in EDITOR_ROLES:
        raise HTTPException(status_code=403, detail="Недостаточно прав для редактирования меню")
    return user


def _validate_menu_payload(data: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(data.get("quick_control_tree"), list):
        raise HTTPException(status_code=400, detail="quick_control_tree должен быть массивом")
    if not isinstance(data.get("object_categories"), list):
        raise HTTPException(status_code=400, detail="object_categories должен быть массивом")
    if not data["quick_control_tree"]:
        raise HTTPException(status_code=400, detail="quick_control_tree не может быть пустым")
    return data


async def ensure_default_diagnostic_menu(db: AsyncSession, updated_by: str = "system") -> None:
    """Идемпотентно создать опубликованную конфигурацию по умолчанию."""
    await _ensure_table(db)
    payload = build_default_diagnostic_menu()
    await db.execute(
        text(
            """
            INSERT INTO diagnostic_menu_config (
                id, draft_payload, published_payload, published_version, updated_at, updated_by
            ) VALUES (
                :id, CAST(:payload AS jsonb), CAST(:payload AS jsonb), 1, NOW(), :by
            )
            ON CONFLICT (id) DO NOTHING
            """
        ),
        {
            "id": MENU_ROW_ID,
            "payload": json.dumps(payload, ensure_ascii=False),
            "by": updated_by,
        },
    )
    await db.commit()


async def _get_row(db: AsyncSession) -> Optional[dict]:
    await _ensure_table(db)
    result = await db.execute(
        text("SELECT * FROM diagnostic_menu_config WHERE id = :id"),
        {"id": MENU_ROW_ID},
    )
    row = result.fetchone()
    if not row:
        return None
    return dict(row._mapping)


def _json_payload(val: Any) -> dict[str, Any]:
    if val is None:
        return dict(DEFAULT_DIAGNOSTIC_MENU)
    if isinstance(val, str):
        return json.loads(val)
    if isinstance(val, dict):
        return val
    return dict(DEFAULT_DIAGNOSTIC_MENU)


@router.get("/api/diagnostic-menu")
async def get_diagnostic_menu(
    draft: bool = False,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Опубликованная структура меню (mobile). draft=true — черновик для редактора."""
    row = await _get_row(db)
    if not row:
        await ensure_default_diagnostic_menu(db)
        row = await _get_row(db)

    if draft:
        user = await _editor_user(db, current_user)
        payload = _json_payload(row.get("draft_payload") or row.get("published_payload"))
    else:
        payload = _json_payload(row.get("published_payload"))

    await db.commit()
    return {
        "id": MENU_ROW_ID,
        "version": row.get("published_version", 1),
        "is_draft": draft,
        "payload": payload,
        "updated_at": row.get("updated_at").isoformat() if row.get("updated_at") else None,
    }


@router.put("/api/diagnostic-menu/draft")
async def save_draft(
    body: DiagnosticMenuPayload,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Сохранить черновик структуры меню."""
    user = await _editor_user(db, current_user)
    await _ensure_table(db)
    data = _validate_menu_payload(body.model_dump())
    row = await _get_row(db)
    if not row:
        await ensure_default_diagnostic_menu(db, updated_by=user.username)
    await db.execute(
        text(
            """
            UPDATE diagnostic_menu_config SET
                draft_payload = CAST(:draft AS jsonb),
                updated_at = NOW(),
                updated_by = :by
            WHERE id = :id
            """
        ),
        {
            "id": MENU_ROW_ID,
            "draft": json.dumps(data, ensure_ascii=False),
            "by": user.username,
        },
    )
    await db.commit()
    return {"ok": True, "message": "Черновик сохранён"}


@router.post("/api/diagnostic-menu/publish")
async def publish_menu(
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Опубликовать черновик (станет доступен мобильным клиентам)."""
    user = await _editor_user(db, current_user)
    row = await _get_row(db)
    if not row:
        raise HTTPException(status_code=404, detail="Конфигурация меню не найдена")
    draft = row.get("draft_payload")
    if not draft:
        raise HTTPException(status_code=400, detail="Нет черновика для публикации")

    payload = _validate_menu_payload(_json_payload(draft))
    new_ver = int(row.get("published_version") or 0) + 1
    await db.execute(
        text(
            """
            UPDATE diagnostic_menu_config SET
                published_payload = CAST(:pub AS jsonb),
                published_version = :ver,
                updated_at = NOW(),
                updated_by = :by
            WHERE id = :id
            """
        ),
        {
            "id": MENU_ROW_ID,
            "pub": json.dumps(payload, ensure_ascii=False),
            "ver": new_ver,
            "by": user.username,
        },
    )
    await db.commit()
    return {"ok": True, "version": new_ver, "message": "Меню опубликовано"}


@router.post("/api/diagnostic-menu/reset-draft")
async def reset_draft_from_published(
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Сбросить черновик к опубликованной версии."""
    await _editor_user(db, current_user)
    row = await _get_row(db)
    if not row:
        raise HTTPException(status_code=404, detail="Конфигурация не найдена")
    pub = row.get("published_payload")
    await db.execute(
        text(
            """
            UPDATE diagnostic_menu_config SET
                draft_payload = published_payload,
                updated_at = NOW()
            WHERE id = :id
            """
        ),
        {"id": MENU_ROW_ID},
    )
    await db.commit()
    return {"ok": True, "payload": _json_payload(pub)}
