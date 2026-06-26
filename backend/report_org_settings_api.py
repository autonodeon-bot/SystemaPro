"""
API справочных данных для формирования отчётов (заказчик, организация ТД, основания, НД).
"""
from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict

from auth import verify_token
from report_org_settings import (
    DEFAULT_REPORT_ORG_SETTINGS,
    load_report_org_settings,
    save_report_org_settings,
)

router = APIRouter(prefix="/api/report-org-settings", tags=["report-org-settings"])


class ReportOrgSettingsPayload(BaseModel):
    model_config = ConfigDict(extra="allow")

    work_basis: str | None = None
    normative_documents: list[str] | None = None
    report_city: str | None = None
    epb_registry_date: str | None = None
    customer: Dict[str, Any] | None = None
    contractor: Dict[str, Any] | None = None
    appendix_protocol_header: Dict[str, str] | None = None
    conclusion_templates: Dict[str, str] | None = None


def _require_admin(user: dict) -> None:
    if user.get("role") not in ("admin", "chief_operator", "operator"):
        raise HTTPException(status_code=403, detail="Недостаточно прав")


@router.get("")
async def get_report_org_settings(user=Depends(verify_token)):
    _require_admin(user)
    return load_report_org_settings()


@router.put("")
async def update_report_org_settings(
    payload: ReportOrgSettingsPayload,
    user=Depends(verify_token),
):
    _require_admin(user)
    current = load_report_org_settings()
    data = payload.model_dump(exclude_unset=True)
    for key, value in data.items():
        if value is None:
            continue
        if isinstance(value, dict) and isinstance(current.get(key), dict):
            current[key] = {**current[key], **value}
        else:
            current[key] = value
    saved = save_report_org_settings(current)
    return saved


@router.post("/reset")
async def reset_report_org_settings(user=Depends(verify_token)):
    _require_admin(user)
    return save_report_org_settings(DEFAULT_REPORT_ORG_SETTINGS)
