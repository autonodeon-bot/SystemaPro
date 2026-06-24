"""
API профилей оборудования — единый реестр для web/mobile/backend.
"""
from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Query

from equipment_profiles import (
    build_inspection_default_data,
    list_profiles,
    profile_by_code,
    profile_by_preset,
    profile_to_api_dict,
)

router = APIRouter(prefix="/api/equipment-profiles", tags=["equipment-profiles"])


@router.get("")
async def get_equipment_profiles() -> list[dict[str, Any]]:
    """Список всех профилей оборудования."""
    return [profile_to_api_dict(p) for p in list_profiles()]


@router.get("/resolve")
async def resolve_equipment_profile(
    type_code: Optional[str] = Query(None),
    preset: Optional[str] = Query(None),
    inspection_direction: str = Query("technical"),
    include_uzt_template: bool = Query(True),
) -> dict[str, Any]:
    """
    Профиль + default_data для чек-листа обследования.
    Используется web/mobile при создании обследования.
    """
    profile = None
    if type_code:
        profile = profile_by_code(type_code)
    if not profile and preset:
        profile = profile_by_preset(preset)
    if not profile:
        raise HTTPException(status_code=404, detail="Профиль оборудования не найден")

    return {
        "profile": profile_to_api_dict(profile),
        "default_data": build_inspection_default_data(
            profile.preset,
            inspection_direction,
            include_uzt_template=include_uzt_template,
        ),
    }


@router.get("/{code}")
async def get_equipment_profile(code: str) -> dict[str, Any]:
    profile = profile_by_code(code)
    if not profile:
        raise HTTPException(status_code=404, detail="Профиль не найден")
    return profile_to_api_dict(profile)
