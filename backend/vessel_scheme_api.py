"""API конструктора схем оборудования: render PNG + сохранение в DrawingTemplates.

Поддержка всех 44 форм ТО (Приложение_форма ТО) через scheme_equipment_catalog.
"""
from __future__ import annotations

import logging
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from auth import verify_token
from scheme_equipment_catalog import (
    GROUP_ORDER,
    defaults_for_kind,
    get_kind,
    list_scheme_kinds,
)
from vessel_scheme_renderer import (
    KIND_CATEGORIES,
    KIND_TITLES,
    normalize_equipment_kind,
    normalize_geometry,
    render_vessel_scheme,
)

logger = logging.getLogger(__name__)
router = APIRouter()

UPLOAD_DIR = Path("/app/uploads/equipment_drawings")
FALLBACK_UPLOAD_DIR = Path.cwd() / "uploads" / "equipment_drawings"


def _ensure_upload_dir() -> Path:
    try:
        UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
        return UPLOAD_DIR
    except Exception:
        FALLBACK_UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
        return FALLBACK_UPLOAD_DIR


class NozzleIn(BaseModel):
    id: Optional[str] = None
    dn: Optional[Any] = 50
    position: float = Field(default=0.5, ge=0, le=1)
    axial: Optional[float] = None
    circ: Optional[float] = None
    side: str = "top"
    place: Optional[str] = None
    label: Optional[str] = None
    purpose: Optional[str] = None


class WeldIn(BaseModel):
    id: Optional[str] = None
    kind: str = "circumferential"
    position: float = Field(default=0.5, ge=0, le=1)
    span_start: Optional[float] = None
    span_end: Optional[float] = None
    label: Optional[str] = None


class VesselSchemeRenderRequest(BaseModel):
    equipment_kind: str = "vessel"
    form_id: Optional[str] = None
    orientation: Optional[str] = None
    shell_length: float = 1.0
    shell_diameter: float = 0.5
    shell_count: Optional[int] = None
    segment_count: Optional[int] = None
    head_type: str = "elliptical"
    weld_preset: Optional[str] = None
    nozzles: List[NozzleIn] = Field(default_factory=list)
    welds: List[WeldIn] = Field(default_factory=list)
    title: Optional[str] = None
    scheme_layer: Optional[str] = None
    width: int = Field(default=1200, ge=400, le=2400)
    height: int = Field(default=1050, ge=300, le=1800)
    geometry: Optional[Dict[str, Any]] = None


class VesselSchemeSaveRequest(VesselSchemeRenderRequest):
    name: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    equipment_id: Optional[str] = None
    equipment_type_id: Optional[str] = None
    create_points: bool = True
    category: Optional[str] = None


def _to_geometry(req: VesselSchemeRenderRequest) -> Dict[str, Any]:
    if req.geometry and isinstance(req.geometry, dict):
        geo = dict(req.geometry)
        if "equipment_kind" not in geo:
            geo["equipment_kind"] = req.equipment_kind or req.form_id
        return geo
    kind_raw = req.equipment_kind or req.form_id or "vessel"
    kind = normalize_equipment_kind(kind_raw)
    defs = defaults_for_kind(kind)
    count = req.segment_count if req.segment_count is not None else req.shell_count
    if count is None:
        count = int(defs.get("shell_count") or 3)
    return {
        "equipment_kind": kind,
        "form_id": req.form_id,
        "orientation": req.orientation or defs.get("orientation") or "vertical",
        "shell": {
            "length": req.shell_length,
            "diameter": req.shell_diameter,
            "count": count,
        },
        "shell_count": count,
        "segment_count": count,
        "head_type": req.head_type,
        "weld_preset": req.weld_preset or defs.get("weld_preset") or "long_plus_rings",
        "nozzles": [n.model_dump(exclude_none=True) for n in req.nozzles],
        "welds": [w.model_dump(exclude_none=True) for w in req.welds],
        "title": req.title or KIND_TITLES.get(kind),
        "scheme_layer": req.scheme_layer or "vik",
    }


@router.get("/api/vessel-scheme/kinds")
async def list_scheme_kinds_endpoint(current_user: str = Depends(verify_token)):
    """Список видов оборудования конструктора (= 44 формы ТО + алиасы)."""
    items = list_scheme_kinds(include_aliases=True)
    return {
        "items": items,
        "groups": GROUP_ORDER,
        "count": len(items),
        "forms_count": len({i["form_id"] for i in items}),
    }


@router.post("/api/vessel-scheme/normalize")
async def normalize_vessel_scheme(
    req: VesselSchemeRenderRequest,
    current_user: str = Depends(verify_token),
):
    geo = normalize_geometry(_to_geometry(req))
    return {"geometry": geo}


@router.post("/api/vessel-scheme/render")
async def render_vessel_scheme_endpoint(
    req: VesselSchemeRenderRequest,
    as_json: bool = Query(False, description="Вернуть JSON с base64 вместо raw PNG"),
    current_user: str = Depends(verify_token),
):
    """Рендер схемы. По умолчанию — image/png. ?as_json=1 — geometry + base64."""
    import base64

    try:
        png, geo, points = render_vessel_scheme(
            _to_geometry(req),
            width=req.width,
            height=req.height,
            scheme_layer=getattr(req, "scheme_layer", None),
        )
    except Exception as e:
        logger.exception("vessel-scheme render failed")
        raise HTTPException(status_code=400, detail=f"Ошибка рендера: {e}") from e

    if as_json:
        return {
            "geometry": geo,
            "suggested_points": points,
            "png_base64": base64.b64encode(png).decode("ascii"),
            "content_type": "image/png",
        }
    return Response(
        content=png,
        media_type="image/png",
        headers={
            "X-Vessel-Orientation": geo.get("orientation") or "",
            "X-Equipment-Kind": geo.get("equipment_kind") or "",
            "X-Scheme-Family": geo.get("scheme_family") or "",
            "X-Form-Id": geo.get("form_id") or "",
        },
    )


@router.post("/api/vessel-scheme/save-template")
async def save_vessel_scheme_as_template(
    req: VesselSchemeSaveRequest,
    db: AsyncSession = Depends(get_db),
    current_user: str = Depends(verify_token),
):
    """Сохранить отрендеренную схему как DrawingTemplate."""
    import json

    try:
        png, geo, points = render_vessel_scheme(
            _to_geometry(req),
            width=req.width,
            height=req.height,
            scheme_layer=getattr(req, "scheme_layer", None),
        )
    except Exception as e:
        logger.exception("vessel-scheme save render failed")
        raise HTTPException(status_code=400, detail=f"Ошибка рендера: {e}") from e

    upload_dir = _ensure_upload_dir()
    file_id = str(uuid.uuid4())
    out_path = upload_dir / f"{file_id}.png"
    out_path.write_bytes(png)

    stored_path = str(out_path)
    meta_desc = req.description or ""
    meta_blob = json.dumps({"constructor_geometry": geo}, ensure_ascii=False)
    description = (meta_desc + "\n" if meta_desc else "") + f"<!--vessel_geometry:{meta_blob}-->"
    category = (
        req.category
        or geo.get("category")
        or KIND_CATEGORIES.get(geo.get("equipment_kind") or "vessel", "other")
    )[:50]

    template_id = str(uuid.uuid4())
    try:
        await db.execute(
            text(
                """
                INSERT INTO drawing_templates (
                    id, name, description, category,
                    equipment_type_id, equipment_id,
                    image_file_path, image_width, image_height, mime_type, file_size,
                    version, is_active, created_at, updated_at
                ) VALUES (
                    :id, :name, :description, :category,
                    :equipment_type_id, :equipment_id,
                    :path, :w, :h, 'image/png', :file_size,
                    1, TRUE, NOW(), NOW()
                )
                """
            ),
            {
                "id": template_id,
                "name": req.name,
                "description": description[:4000],
                "category": category,
                "path": stored_path,
                "w": req.width,
                "h": req.height,
                "file_size": len(png),
                "equipment_id": req.equipment_id,
                "equipment_type_id": req.equipment_type_id,
            },
        )
        if req.create_points:
            for i, p in enumerate(points):
                await db.execute(
                    text(
                        """
                        INSERT INTO drawing_template_points (
                            id, template_id, label, point_type,
                            x_percent, y_percent, notes, sort_order
                        ) VALUES (
                            :id, :tid, :label, :ptype,
                            :xp, :yp, :notes, :ord
                        )
                        """
                    ),
                    {
                        "id": str(uuid.uuid4()),
                        "tid": template_id,
                        "label": str(p.get("label") or f"P{i+1}")[:50],
                        "ptype": str(p.get("point_type") or "custom")[:30],
                        "xp": float(p.get("x_percent") or 0),
                        "yp": float(p.get("y_percent") or 0),
                        "notes": str(p.get("notes") or "")[:500],
                        "ord": i,
                    },
                )
        await db.commit()
    except Exception as e:
        await db.rollback()
        logger.exception("save vessel scheme template failed")
        raise HTTPException(status_code=500, detail=str(e)) from e

    return {
        "id": template_id,
        "name": req.name,
        "geometry": geo,
        "category": category,
        "file_path": stored_path,
        "points_count": len(points) if req.create_points else 0,
    }
