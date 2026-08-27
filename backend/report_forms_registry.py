"""
Реестр форм технического отчёта (каталог «Приложение_форма ТО»).

Формы хранятся в backend/report_forms/*.docx|.doc
Метаданные — technical_report_forms.json
"""
from __future__ import annotations

import json
import logging
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

FORMS_DIR = Path(__file__).resolve().parent / "report_forms"
FORMS_JSON = FORMS_DIR / "technical_report_forms.json"

# Тип оборудования (code) → id формы ТО (Приложение_форма ТО, 44 формы)
EQUIPMENT_TYPE_TO_FORM: Dict[str, str] = {
    "VESSEL": "to-1",
    "GAS_SEPARATOR": "to-1",
    "OIL_SETTLER": "to-1",
    "CRANE_RUNWAY": "to-2",
    "CRANE": "to-3",
    "GPM": "to-3",
    "LIFTING": "to-3",
    "GAS_COLLECTOR": "to-4",
    "TRANSFORMER": "to-5",
    "LIGHTNING_PROTECTION": "to-6",
    "DC_SYSTEM": "to-7",
    "ELECTRIC_MOTOR": "to-8",
    "GRS": "to-9",
    "COMPLEX_PERIODIC": "to-10",
    "GPA": "to-11",
    "COMPRESSOR": "to-12",
    "PIPELINE": "to-13",
    "ACCEPTANCE": "to-14",
    "DIESEL_STATION": "to-15",
    "CABLE_LINE": "to-16",
    "GPA_DRIVE": "to-17",
    "RIVERBED": "to-18",
    "DIVER_SURVEY": "to-19",
    "PIG_TRAP": "to-20",
    "PIPELINE_CROSSING": "to-21",
    "MAIN_PIPELINE": "to-22",
    "AIR_COOLER": "to-23",
    "PIPELINE_VALVE": "to-24",
    "TANK": "to-25",
    "UNDERGROUND_TANK": "to-25",
    "WELLHEAD_PIPING": "to-26",
    "WELLHEAD_TREE": "to-27",
    "BOILER": "to-28",
    "PU_UNIT": "to-29",
    "BOILER_AUX": "to-30",
    "GAS_PIPELINE_GX": "to-31",
    "ABOVEGROUND_PIPELINE": "to-32",
    "UNDERGROUND_PIPELINE": "to-33",
    "VENTILATION": "to-34",
    "PRG": "to-35",
    "POWER_STATION": "to-36",
    "GIS_STATION": "to-37",
    "AUX_EQUIPMENT": "to-38",
    "CHIMNEY": "to-39",
    "METERING": "to-40",
    "BUILDINGS": "to-41",
    "SWITCHGEAR": "to-42",
    "WATER_TANK": "to-43",
    "FLARE": "to-44",
}

# Все 44 официальные формы ТО заполняются (специализированные + generic filler)
FILLABLE_FORM_IDS = frozenset({f"to-{i}" for i in range(1, 45)})

# Специализированные fillers (остальные — form_template_filler_generic)
SPECIALIZED_FILLABLE_FORM_IDS = frozenset({"to-1", "to-3", "to-13", "to-25", "to-33"})


@lru_cache(maxsize=1)
def load_forms_catalog() -> List[Dict[str, Any]]:
    """Загрузить каталог форм из JSON."""
    if not FORMS_JSON.exists():
        logger.warning("Каталог форм не найден: %s", FORMS_JSON)
        return []
    try:
        with open(FORMS_JSON, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            return data
    except Exception as exc:
        logger.error("Ошибка чтения каталога форм: %s", exc)
    return []


def list_forms() -> List[Dict[str, Any]]:
    """Список форм с флагом наличия файла и поддержки заполнения."""
    result: List[Dict[str, Any]] = []
    for item in load_forms_catalog():
        form_id = str(item.get("id") or "")
        filename = str(item.get("file") or "")
        path = resolve_form_path(form_id)
        result.append(
            {
                "id": form_id,
                "number": item.get("number"),
                "title": _clean_title(str(item.get("title") or "")),
                "file": filename,
                "file_exists": path is not None and path.exists(),
                "fillable": form_id in FILLABLE_FORM_IDS,
            }
        )
    result.sort(key=lambda x: int(x.get("number") or 0))
    return result


def get_form(form_id: str) -> Optional[Dict[str, Any]]:
    """Метаданные формы по id (to-1, to-13, …)."""
    fid = (form_id or "").strip().lower()
    for item in load_forms_catalog():
        if str(item.get("id") or "").lower() == fid:
            path = resolve_form_path(fid)
            return {
                "id": str(item.get("id")),
                "number": item.get("number"),
                "title": _clean_title(str(item.get("title") or "")),
                "file": item.get("file"),
                "file_exists": path is not None and path.exists(),
                "fillable": fid in FILLABLE_FORM_IDS,
                "path": str(path) if path else None,
            }
    return None


def resolve_form_path(form_id: str) -> Optional[Path]:
    """Путь к файлу шаблона Word по id формы.

    Предпочтительно ASCII-имя ``to-N.docx`` (устойчиво к SCP/кодировкам).
    """
    fid = (form_id or "").strip().lower()
    if not fid or not FORMS_DIR.is_dir():
        return None

    # 1) Прямой ASCII-алиас to-1.docx / to-1.doc
    for ext in (".docx", ".doc", ".DOCX", ".DOC"):
        alias = FORMS_DIR / f"{fid}{ext}"
        if alias.exists():
            return alias

    meta = None
    for item in load_forms_catalog():
        if str(item.get("id") or "").lower() == fid:
            meta = item
            break
    if not meta:
        return None

    # 2) Имя из каталога (может быть кириллическим)
    for key in ("file", "original_file"):
        filename = str(meta.get(key) or "").strip()
        if not filename:
            continue
        candidate = FORMS_DIR / filename
        if candidate.exists():
            return candidate
        stem = Path(filename).stem
        for p in FORMS_DIR.iterdir():
            if p.is_file() and p.stem.lower() == stem.lower():
                return p

    # 3) Поиск по номеру «№ N.» в имени файла (если кириллица битая — не сработает)
    try:
        num = int(str(meta.get("number") or "").strip())
    except ValueError:
        num = None
    if num is not None:
        import re

        pat = re.compile(rf"(?:№|N[oо]?)\s*{num}\.", re.IGNORECASE)
        for p in FORMS_DIR.iterdir():
            if p.is_file() and p.suffix.lower() in (".docx", ".doc") and pat.search(p.name):
                return p
    return None


def suggest_form_id(
    equipment_type_code: Optional[str] = None,
    equipment_name: Optional[str] = None,
    equipment_type_name: Optional[str] = None,
) -> str:
    """Подбор формы ТО по типу/наименованию оборудования."""
    code = (equipment_type_code or "").strip().upper()
    name = (equipment_name or "").lower()
    type_name = (equipment_type_name or "").lower()
    blob = f"{name} {type_name} {code.lower()}"

    # Специализации до общей карты (PIPELINE+подземн → to-33, а не to-13)
    if code == "UNDERGROUND_PIPELINE" or (
        ("трубопровод" in blob or "pipeline" in blob or code == "PIPELINE")
        and "подземн" in blob
    ):
        return "to-33"
    if code in ("CRANE", "GPM", "LIFTING") or (
        "кран" in blob
        or "грузоподъем" in blob
        or "грузоподъём" in blob
        or "гпм" in blob
        or "подъемн" in blob
        or "подъёмн" in blob
    ):
        return "to-3"

    if code in EQUIPMENT_TYPE_TO_FORM:
        return EQUIPMENT_TYPE_TO_FORM[code]

    if "трубопровод" in blob or "pipeline" in blob:
        if "надземн" in blob or "газопровод" in blob:
            return "to-32"
        if "обвязк" in blob and "скважин" in blob:
            return "to-26"
        return "to-13"
    if "котел" in blob or "котёл" in blob or "boiler" in blob:
        return "to-28"
    if "резервуар" in blob or "ёмкост" in blob or "емкост" in blob or "tank" in blob:
        return "to-25"
    if "компрессор" in blob or "compressor" in blob:
        return "to-12"
    if "трансформатор" in blob:
        return "to-5"
    if "электродвигател" in blob:
        return "to-8"
    if "арматур" in blob and "фонтан" not in blob:
        return "to-24"
    return "to-1"


def _clean_title(raw: str) -> str:
    import re

    return re.sub(r"[_\s]*корр$", "", raw, flags=re.IGNORECASE).strip()
