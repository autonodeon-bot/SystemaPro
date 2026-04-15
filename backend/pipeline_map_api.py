"""Геоданные трубопроводов для карты: сегменты из БД + координаты в attributes оборудования."""

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from auth import verify_token
from database import get_db
from models import PipelineSegment, Equipment, User

router = APIRouter(tags=["pipeline-map"])


def _coords_from_attributes(attrs: Any) -> Optional[List[Dict[str, float]]]:
    if not attrs or not isinstance(attrs, dict):
        return None
    for key in ("pipeline_map", "map", "geo"):
        block = attrs.get(key)
        if isinstance(block, dict):
            raw = block.get("coordinates") or block.get("path")
            parsed = _parse_coord_list(raw)
            if parsed:
                return parsed
    parsed = _parse_coord_list(attrs.get("coordinates"))
    if parsed:
        return parsed
    return None


def _parse_coord_list(raw: Any) -> Optional[List[Dict[str, float]]]:
    if not isinstance(raw, list) or len(raw) < 2:
        return None
    out: List[Dict[str, float]] = []
    for p in raw:
        if not isinstance(p, dict):
            continue
        try:
            lat = float(p.get("lat"))
            lng = float(p.get("lng"))
            out.append({"lat": lat, "lng": lng})
        except (TypeError, ValueError):
            continue
    return out if len(out) >= 2 else None


def _segment_type(raw: Optional[str]) -> str:
    if not raw:
        return "ABOVE_GROUND"
    u = str(raw).upper()
    if u in ("UNDERGROUND", "CROSSING", "ABOVE_GROUND"):
        return u
    if "ПОДЗЕМ" in u or "UNDER" in u:
        return "UNDERGROUND"
    if "ПЕРЕХОД" in u or "CROSS" in u:
        return "CROSSING"
    return "ABOVE_GROUND"


@router.get("/api/pipeline-map/segments")
async def get_pipeline_map_segments(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Сегменты трубопроводов с геометрией из equipment.attributes (JSON)."""
    user_result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
    if not user_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    result = await db.execute(select(PipelineSegment))
    rows = result.scalars().all()

    segments: List[dict] = []
    for seg in rows:
        coords: Optional[List[Dict[str, float]]] = None
        equipment_name = None
        if seg.equipment_id:
            eq_r = await db.execute(select(Equipment).where(Equipment.id == seg.equipment_id))
            eq = eq_r.scalar_one_or_none()
            if eq:
                equipment_name = eq.name
                coords = _coords_from_attributes(eq.attributes)

        if not coords:
            continue

        thickness = float(seg.thickness) if seg.thickness is not None else 0.0
        corrosion = float(seg.corrosion_rate) if seg.corrosion_rate is not None else 0.0
        remaining = float(seg.remaining_life) if seg.remaining_life is not None else 0.0
        last_insp = seg.last_inspection_date.isoformat() if seg.last_inspection_date else ""

        segments.append(
            {
                "id": str(seg.id),
                "name": seg.name or equipment_name or f"Сегмент {seg.id}",
                "type": _segment_type(seg.segment_type),
                "coordinates": coords,
                "thickness": thickness,
                "lastInspectionDate": last_insp,
                "corrosionRate": corrosion,
                "remainingLife": remaining,
                "equipment_id": str(seg.equipment_id) if seg.equipment_id else None,
            }
        )

    return {"segments": segments, "source": "database" if segments else "empty"}
