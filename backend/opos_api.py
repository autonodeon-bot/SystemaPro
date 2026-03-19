"""CRUD operations for OPO (Опасные производственные объекты)."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
import uuid as uuid_lib

from database import get_db
from auth import verify_token
from models import Opo, User, Branch, Workshop
from shared import cache_get, cache_set, cache_invalidate

router = APIRouter(tags=["opos"])


@router.get("/api/opos")
async def list_opos(
    workshop_id: Optional[str] = None,
    enterprise_id: Optional[str] = None,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    cache_key = f"opos:{workshop_id}:{enterprise_id}"
    cached = cache_get(cache_key)
    if cached is not None:
        return cached
    try:
        query = select(Opo).where(Opo.is_active == 1)
        if workshop_id:
            try:
                query = query.where(Opo.workshop_id == uuid_lib.UUID(workshop_id))
            except ValueError:
                raise HTTPException(status_code=400, detail="Invalid workshop_id format")
        elif enterprise_id:
            try:
                enterprise_uuid = uuid_lib.UUID(enterprise_id)
                branches_result = await db.execute(
                    select(Branch).where(Branch.enterprise_id == enterprise_uuid)
                )
                branches = branches_result.scalars().all()
                branch_ids = [b.id for b in branches]
                if branch_ids:
                    workshops_result = await db.execute(
                        select(Workshop).where(Workshop.branch_id.in_(branch_ids))
                    )
                    ws_ids = [w.id for w in workshops_result.scalars().all()]
                    if ws_ids:
                        query = query.where(Opo.workshop_id.in_(ws_ids))
                    else:
                        return {"items": []}
                else:
                    return {"items": []}
            except ValueError:
                raise HTTPException(status_code=400, detail="Invalid enterprise_id format")

        result = await db.execute(query.order_by(Opo.name))
        items = result.scalars().all()
        response = {
            "items": [
                {
                    "id": str(o.id),
                    "workshop_id": str(o.workshop_id) if o.workshop_id else None,
                    "name": o.name,
                    "code": o.code,
                    "description": o.description,
                    "survey_data": o.survey_data or None,
                    "is_active": o.is_active,
                    "created_at": str(o.created_at) if o.created_at else None,
                    "updated_at": str(o.updated_at) if o.updated_at else None,
                }
                for o in items
            ]
        }
        cache_set(cache_key, response)
        return response
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/opos")
async def create_opo(
    payload: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    try:
        user_result = await db.execute(select(User).where(User.username == username))
        user = user_result.scalar_one_or_none()
        if not user or user.role not in {"admin", "chief_operator", "operator"}:
            raise HTTPException(status_code=403, detail="Forbidden")

        name = (payload.get("name") or "").strip()
        if not name:
            raise HTTPException(status_code=400, detail="name is required")

        workshop_id = None
        if payload.get("workshop_id"):
            try:
                workshop_id = uuid_lib.UUID(payload["workshop_id"])
            except Exception:
                raise HTTPException(status_code=400, detail="Invalid workshop_id")

        opo = Opo(
            name=name,
            code=payload.get("code"),
            description=payload.get("description"),
            workshop_id=workshop_id,
            survey_data=payload.get("survey_data"),
            is_active=1,
        )
        db.add(opo)
        await db.commit()
        await db.refresh(opo)
        cache_invalidate("opos:")
        return {"id": str(opo.id), "status": "created"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/api/opos/{opo_id}")
async def update_opo(
    opo_id: str,
    payload: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    try:
        user_result = await db.execute(select(User).where(User.username == username))
        user = user_result.scalar_one_or_none()
        if not user or user.role not in {"admin", "chief_operator", "operator"}:
            raise HTTPException(status_code=403, detail="Forbidden")

        try:
            opo_uuid = uuid_lib.UUID(opo_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid opo_id format")

        result = await db.execute(select(Opo).where(Opo.id == opo_uuid))
        opo = result.scalar_one_or_none()
        if not opo:
            raise HTTPException(status_code=404, detail="OPO not found")

        if "name" in payload and payload["name"] is not None:
            opo.name = str(payload["name"]).strip()
        if "code" in payload:
            opo.code = payload.get("code")
        if "description" in payload:
            opo.description = payload.get("description")
        if "survey_data" in payload:
            opo.survey_data = payload.get("survey_data")
        if "is_active" in payload and payload["is_active"] is not None:
            opo.is_active = int(payload["is_active"])
        if "workshop_id" in payload:
            if payload.get("workshop_id"):
                try:
                    opo.workshop_id = uuid_lib.UUID(payload["workshop_id"])
                except Exception:
                    raise HTTPException(status_code=400, detail="Invalid workshop_id")
            else:
                opo.workshop_id = None

        await db.commit()
        cache_invalidate("opos:")
        return {"id": str(opo.id), "status": "updated"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/opos/{opo_id}/survey")
async def get_opo_survey(
    opo_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    try:
        opo_uuid = uuid_lib.UUID(opo_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid opo_id format")
    result = await db.execute(select(Opo).where(Opo.id == opo_uuid))
    opo = result.scalar_one_or_none()
    if not opo:
        raise HTTPException(status_code=404, detail="OPO not found")
    return {
        "opo_id": str(opo.id),
        "survey_data": opo.survey_data or {},
        "updated_at": str(opo.updated_at) if opo.updated_at else None,
    }


@router.put("/api/opos/{opo_id}/survey")
async def update_opo_survey(
    opo_id: str,
    payload: dict,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    try:
        opo_uuid = uuid_lib.UUID(opo_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid opo_id format")

    user_result = await db.execute(select(User).where(User.username == username))
    user = user_result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user.role not in {"admin", "chief_operator", "operator", "engineer"}:
        raise HTTPException(status_code=403, detail="Forbidden")

    result = await db.execute(select(Opo).where(Opo.id == opo_uuid))
    opo = result.scalar_one_or_none()
    if not opo:
        raise HTTPException(status_code=404, detail="OPO not found")

    if "survey_data" not in payload:
        raise HTTPException(
            status_code=400,
            detail=[{"field": "survey_data", "message": "survey_data обязателен"}],
        )
    sd = payload.get("survey_data")
    if sd is not None and not isinstance(sd, dict):
        raise HTTPException(
            status_code=400,
            detail=[{"field": "survey_data", "message": "survey_data должен быть объектом"}],
        )

    opo.survey_data = sd or {}
    await db.commit()
    cache_invalidate("opos:")
    return {"opo_id": str(opo.id), "status": "updated"}


@router.get("/api/opos/{opo_id}")
async def get_opo(
    opo_id: str,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    try:
        opo_uuid = uuid_lib.UUID(opo_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid opo_id format")
    result = await db.execute(select(Opo).where(Opo.id == opo_uuid))
    opo = result.scalar_one_or_none()
    if not opo:
        raise HTTPException(status_code=404, detail="OPO not found")
    return {
        "id": str(opo.id),
        "workshop_id": str(opo.workshop_id) if opo.workshop_id else None,
        "name": opo.name,
        "code": opo.code,
        "description": opo.description,
        "survey_data": opo.survey_data or None,
        "is_active": opo.is_active,
        "created_at": str(opo.created_at) if opo.created_at else None,
        "updated_at": str(opo.updated_at) if opo.updated_at else None,
    }
