"""
Идемпотентное наполнение report_templates.json — макеты Word по типу оборудования.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List

TEMPLATES_FILE = Path("/app/reports/report_templates.json")

DEFAULT_REPORT_TEMPLATES: List[Dict[str, Any]] = [
    {
        "id": "rt-srpd-vessel-epb-docx",
        "name": "СРпД · Сосуд · ЭПБ (Word)",
        "report_type": "EXPERTISE",
        "format": "docx",
        "equipment_type_code": "VESSEL",
        "is_active": True,
        "definition": {
            "logo_path": "/app/reports/assets/yutar_logo.png",
            "pressure_regime": "high",
            "normative_basis": "order_536",
        },
    },
    {
        "id": "rt-srpd-gas-separator-epb-docx",
        "name": "СРпД · Газосепаратор · ЭПБ (Word)",
        "report_type": "EXPERTISE",
        "format": "docx",
        "equipment_type_code": "GAS_SEPARATOR",
        "is_active": True,
        "definition": {
            "logo_path": "/app/reports/assets/yutar_logo.png",
            "pressure_regime": "high",
            "normative_basis": "order_536",
        },
    },
    {
        "id": "rt-srpd-underground-tank-epb-docx",
        "name": "СРпД · Ёмкость подземная · ЭПБ (Word)",
        "report_type": "EXPERTISE",
        "format": "docx",
        "equipment_type_code": "UNDERGROUND_TANK",
        "is_active": True,
        "definition": {
            "logo_path": "/app/reports/assets/yutar_logo.png",
            "pressure_regime": "low",
            "normative_basis": "rua_93",
        },
    },
    {
        "id": "rt-srpd-oil-settler-epb-docx",
        "name": "СРпД · Отстойник нефти · ЭПБ (Word)",
        "report_type": "EXPERTISE",
        "format": "docx",
        "equipment_type_code": "OIL_SETTLER",
        "is_active": True,
        "definition": {
            "logo_path": "/app/reports/assets/yutar_logo.png",
            "pressure_regime": "high",
            "normative_basis": "order_536",
        },
    },
    {
        "id": "rt-srpd-default-epb-docx",
        "name": "СРпД · Общий · ЭПБ (Word)",
        "report_type": "EXPERTISE",
        "format": "docx",
        "equipment_type_code": None,
        "is_active": True,
        "definition": {
            "logo_path": "/app/reports/assets/yutar_logo.png",
            "pressure_regime": "high",
            "normative_basis": "order_536",
        },
    },
]


def ensure_report_templates_seed() -> int:
    """Добавить или обновить шаблоны отчётов по id."""
    TEMPLATES_FILE.parent.mkdir(parents=True, exist_ok=True)
    existing: List[Dict[str, Any]] = []
    if TEMPLATES_FILE.exists():
        try:
            existing = json.loads(TEMPLATES_FILE.read_text(encoding="utf-8") or "[]")
        except Exception:
            existing = []

    by_id = {str(t.get("id")): t for t in existing if isinstance(t, dict) and t.get("id")}
    for item in DEFAULT_REPORT_TEMPLATES:
        by_id[item["id"]] = {**by_id.get(item["id"], {}), **item}

    merged = list(by_id.values())
    TEMPLATES_FILE.write_text(
        json.dumps(merged, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return len(DEFAULT_REPORT_TEMPLATES)
