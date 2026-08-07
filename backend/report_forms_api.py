"""
API каталога форм технического отчёта (Приложение_форма ТО).
"""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from auth import verify_token
from report_forms_registry import get_form, list_forms, suggest_form_id

router = APIRouter(prefix="/api/report-forms", tags=["report-forms"])


@router.get("")
async def get_report_forms(username: str = Depends(verify_token)):
    """Список всех форм ТО из каталога."""
    return list_forms()


@router.get("/suggest")
async def suggest_report_form(
    equipment_type_code: Optional[str] = Query(None),
    equipment_name: Optional[str] = Query(None),
    equipment_type_name: Optional[str] = Query(None),
    username: str = Depends(verify_token),
):
    """Подсказать форму ТО по типу/наименованию оборудования."""
    form_id = suggest_form_id(
        equipment_type_code=equipment_type_code,
        equipment_name=equipment_name,
        equipment_type_name=equipment_type_name,
    )
    form = get_form(form_id)
    return {
        "report_form_id": form_id,
        "form": form,
    }


@router.get("/{form_id}")
async def get_report_form(form_id: str, username: str = Depends(verify_token)):
    """Метаданные одной формы ТО."""
    form = get_form(form_id)
    if not form:
        raise HTTPException(status_code=404, detail="Форма ТО не найдена")
    return form
