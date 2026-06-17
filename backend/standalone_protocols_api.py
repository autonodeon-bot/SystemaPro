"""
Протоколы, заполненные только в мобильном приложении (без связанного обследования в вебе).

Сохранение JSON на сервер и выгрузка единого DOCX — без генерации полного отчёта.
"""

from __future__ import annotations

import json
import logging
import re
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlalchemy import text, select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from auth import verify_token
from database import get_db
from models import Assignment, User
from standalone_protocol_docx import build_standalone_protocol_docx

logger = logging.getLogger(__name__)
router = APIRouter(tags=["mobile"])


async def _ensure_table(db: AsyncSession) -> None:
    await db.execute(
        text("""
        CREATE TABLE IF NOT EXISTS standalone_protocols (
            id TEXT PRIMARY KEY,
            created_by TEXT NOT NULL,
            title TEXT NOT NULL,
            kind TEXT NOT NULL,
            template_id TEXT,
            template_name TEXT,
            equipment_id TEXT,
            equipment_name TEXT,
            payload JSONB NOT NULL DEFAULT '{}'::jsonb,
            status TEXT NOT NULL DEFAULT 'completed',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)
    )
    await db.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_standalone_protocols_created_by ON standalone_protocols(created_by)"
        )
    )
    await db.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_standalone_protocols_created_at ON standalone_protocols(created_at DESC)"
        )
    )
    await db.execute(
        text(
            """
            ALTER TABLE standalone_protocols
            ADD COLUMN IF NOT EXISTS assignment_id UUID REFERENCES assignments(id) ON DELETE SET NULL
            """
        )
    )
    await db.execute(
        text(
            "CREATE INDEX IF NOT EXISTS idx_standalone_protocols_assignment_id ON standalone_protocols(assignment_id)"
        )
    )


async def assert_mandatory_standalone_protocol_uploaded(
    db: AsyncSession, assignment: Assignment
) -> None:
    """Если у задания назначен шаблон протокола — на сервере должна быть запись standalone_protocols."""
    tpl = getattr(assignment, "protocol_template_id", None)
    if not tpl or not str(tpl).strip():
        return
    await _ensure_table(db)
    tid = str(tpl).strip()
    aid = str(assignment.id)
    r = await db.execute(
        text(
            """
            SELECT 1 FROM standalone_protocols
            WHERE assignment_id = CAST(:aid AS uuid) AND template_id = :tid
            LIMIT 1
            """
        ),
        {"aid": aid, "tid": tid},
    )
    if r.first() is None:
        raise HTTPException(
            status_code=400,
            detail=(
                "Нельзя завершить задание: нет загруженного протокола по назначенному шаблону. "
                "Отправьте протокол из мобильного приложения и выполните синхронизацию."
            ),
        )


def _payload_assignment_id(payload: Any) -> Optional[str]:
    if not isinstance(payload, dict):
        return None
    v = payload.get("assignment_id")
    if v is None:
        return None
    s = str(v).strip()
    return s if s else None


async def _user_can_see_all(db: AsyncSession, username: str) -> bool:
    r = await db.execute(
        text("SELECT role FROM users WHERE username = :u LIMIT 1"),
        {"u": username},
    )
    row = r.first()
    if not row:
        return False
    return str(row[0]) in ("admin", "chief_operator", "operator")


def _safe_filename(s: str) -> str:
    s = re.sub(r'[^\w\s\-]+', '', s, flags=re.UNICODE)
    s = re.sub(r'\s+', '_', s.strip())
    return (s[:80] or "protocol") + ".docx"


class StandaloneProtocolCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=500)
    kind: str = Field(..., description="custom_template | ndk_protocol | quick_control")
    template_id: Optional[str] = None
    template_name: Optional[str] = None
    equipment_id: Optional[str] = None
    equipment_name: Optional[str] = None
    assignment_id: Optional[str] = None
    payload: Dict[str, Any] = Field(default_factory=dict)


@router.post("/api/standalone-protocols", status_code=201)
async def create_standalone_protocol(
    body: StandaloneProtocolCreate,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _ensure_table(db)
    resolved_assignment = (body.assignment_id or "").strip() or _payload_assignment_id(body.payload)
    assignment_uuid = None
    if resolved_assignment:
        try:
            assignment_uuid = uuid.UUID(resolved_assignment)
        except (ValueError, TypeError):
            raise HTTPException(status_code=400, detail="Некорректный assignment_id") from None
        ar = await db.execute(select(Assignment).where(Assignment.id == assignment_uuid))
        asg = ar.scalar_one_or_none()
        if not asg:
            raise HTTPException(status_code=404, detail="Задание не найдено")
        ur = await db.execute(
            select(User).where(or_(User.username == username, User.email == username))
        )
        current_user = ur.scalar_one_or_none()
        if not current_user:
            raise HTTPException(status_code=401, detail="Пользователь не найден")
        if current_user.role not in ("admin", "chief_operator", "operator"):
            if asg.assigned_to != current_user.id:
                raise HTTPException(
                    status_code=403,
                    detail="Протокол с привязкой к заданию может отправить только назначенный исполнитель",
                )
        req_tpl = (asg.protocol_template_id or "").strip()
        if req_tpl:
            got_tpl = (body.template_id or "").strip()
            if got_tpl != req_tpl:
                raise HTTPException(
                    status_code=400,
                    detail="Шаблон протокола должен совпадать с шаблоном, назначенным в задании",
                )
        if body.equipment_id and str(asg.equipment_id) != str(body.equipment_id).strip():
            raise HTTPException(
                status_code=400,
                detail="Оборудование протокола не совпадает с оборудованием в задании",
            )

    pid = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    await db.execute(
        text("""
        INSERT INTO standalone_protocols
          (id, created_by, title, kind, template_id, template_name, equipment_id, equipment_name, assignment_id, payload, status, created_at, updated_at)
        VALUES
          (:id, :created_by, :title, :kind, :template_id, :template_name, :equipment_id, :equipment_name, :assignment_id, CAST(:payload AS jsonb), 'completed', :created_at, :updated_at)
        """),
        {
            "id": pid,
            "created_by": username,
            "title": body.title.strip(),
            "kind": body.kind,
            "template_id": body.template_id,
            "template_name": body.template_name,
            "equipment_id": body.equipment_id,
            "equipment_name": body.equipment_name,
            "assignment_id": str(assignment_uuid) if assignment_uuid else None,
            "payload": json.dumps(body.payload, ensure_ascii=False),
            "created_at": now,
            "updated_at": now,
        },
    )
    await db.commit()
    return {
        "id": pid,
        "title": body.title.strip(),
        "kind": body.kind,
        "created_at": now.isoformat(),
    }


@router.get("/api/standalone-protocols")
async def list_standalone_protocols(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _ensure_table(db)
    broad = await _user_can_see_all(db, username)
    if broad:
        r = await db.execute(
            text("""
            SELECT id, created_by, title, kind, template_id, template_name, equipment_id, equipment_name, assignment_id, status, created_at, updated_at
            FROM standalone_protocols
            ORDER BY created_at DESC
            LIMIT 500
            """)
        )
    else:
        r = await db.execute(
            text("""
            SELECT id, created_by, title, kind, template_id, template_name, equipment_id, equipment_name, assignment_id, status, created_at, updated_at
            FROM standalone_protocols
            WHERE created_by = :u
            ORDER BY created_at DESC
            LIMIT 200
            """),
            {"u": username},
        )
    rows = r.mappings().all()
    return {"items": [dict(x) for x in rows]}


@router.get("/api/standalone-protocols/{protocol_id}/download")
async def download_standalone_protocol(
    protocol_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    await _ensure_table(db)
    r = await db.execute(
        text("SELECT * FROM standalone_protocols WHERE id = :id"),
        {"id": protocol_id},
    )
    row = r.mappings().first()
    if not row:
        raise HTTPException(status_code=404, detail="Протокол не найден")
    row = dict(row)
    if row["created_by"] != username and not await _user_can_see_all(db, username):
        raise HTTPException(status_code=403, detail="Нет доступа к этому протоколу")

    payload = row.get("payload") or {}
    if isinstance(payload, str):
        try:
            payload = json.loads(payload)
        except Exception:
            payload = {}

    title = row.get("title") or "Протокол"
    kind = row.get("kind") or "unknown"
    template_name = row.get("template_name")

    try:
        blob = build_standalone_protocol_docx(
            title=title,
            kind=kind,
            template_name=template_name,
            payload=payload if isinstance(payload, dict) else {},
        )
    except Exception as e:
        logger.exception("standalone protocol docx")
        raise HTTPException(status_code=500, detail=f"Ошибка формирования DOCX: {e}") from e

    fn = _safe_filename(title)
    return Response(
        content=blob,
        media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        headers={"Content-Disposition": f'attachment; filename="{fn}"'},
    )
