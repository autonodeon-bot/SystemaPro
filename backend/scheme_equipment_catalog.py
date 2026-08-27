"""Каталог видов оборудования конструктора схем = 44 формы ТО (Приложение_форма ТО).

Каждый вид привязан к форме to-N и к семейству отрисовки (scheme_family),
чтобы карты контроля строились по одной системе (развёртка / линия / план / …).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

# Семейства отрисовки
FAMILY_VESSEL_DEV = "vessel_development"  # развёртка + круги днищ
FAMILY_TANK = "tank"  # резервуар: план + стенка
FAMILY_PIPELINE = "pipeline"  # трубопровод / коллектор
FAMILY_CRANE = "crane"  # ГПМ / подкрановые
FAMILY_BOILER = "boiler"  # котлы
FAMILY_MACHINERY = "machinery"  # нагнетатели, ГПА, двигатели
FAMILY_ELECTRICAL = "electrical"  # трансформаторы, кабели, щиты
FAMILY_VALVE = "valve"  # арматура, фонтанная ёлка
FAMILY_TOWER = "tower"  # дымовые трубы, факел
FAMILY_STATION = "station"  # ГРС, ПРГ, ГИС, станции
FAMILY_GENERIC = "generic"  # прочие карты контроля

SCHEME_FAMILIES: Dict[str, str] = {
    FAMILY_VESSEL_DEV: "Развёртка сосуда/аппарата",
    FAMILY_TANK: "Резервуар (план + стенка)",
    FAMILY_PIPELINE: "Трубопровод / коллектор",
    FAMILY_CRANE: "ГПМ / подкрановые пути",
    FAMILY_BOILER: "Котёл / котельное",
    FAMILY_MACHINERY: "Машины / агрегаты",
    FAMILY_ELECTRICAL: "Электрооборудование",
    FAMILY_VALVE: "Арматура / обвязка",
    FAMILY_TOWER: "Башня / труба / факел",
    FAMILY_STATION: "Станция / узел",
    FAMILY_GENERIC: "Карта контроля (общая)",
}

# code → метаданные. form_id соответствует technical_report_forms.json
EQUIPMENT_SCHEME_KINDS: List[Dict[str, Any]] = [
    {
        "code": "vessel",
        "form_id": "to-1",
        "title": "Сосуды и аппараты",
        "group": "емкостное",
        "family": FAMILY_VESSEL_DEV,
        "category": "vessel",
        "defaults": {"orientation": "vertical", "shell_count": 3, "weld_preset": "multi_shell"},
    },
    {
        "code": "crane_runway",
        "form_id": "to-2",
        "title": "Подкрановые пути",
        "group": "грузоподъёмное",
        "family": FAMILY_CRANE,
        "category": "other",
        "defaults": {"shell_count": 4},
    },
    {
        "code": "crane",
        "form_id": "to-3",
        "title": "Грузоподъёмные механизмы",
        "group": "грузоподъёмное",
        "family": FAMILY_CRANE,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "gas_collector",
        "form_id": "to-4",
        "title": "Газосборные шлейфы и коллекторы",
        "group": "трубопроводы",
        "family": FAMILY_PIPELINE,
        "category": "pipeline",
        "defaults": {"shell_count": 5, "weld_preset": "ring_only"},
    },
    {
        "code": "transformer",
        "form_id": "to-5",
        "title": "Силовые трансформаторы",
        "group": "электрооборудование",
        "family": FAMILY_ELECTRICAL,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "lightning_protection",
        "form_id": "to-6",
        "title": "Молниезащита и заземление",
        "group": "электрооборудование",
        "family": FAMILY_ELECTRICAL,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "dc_system",
        "form_id": "to-7",
        "title": "Система постоянного тока",
        "group": "электрооборудование",
        "family": FAMILY_ELECTRICAL,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "electric_motor",
        "form_id": "to-8",
        "title": "Электродвигатели",
        "group": "машины",
        "family": FAMILY_MACHINERY,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "grs",
        "form_id": "to-9",
        "title": "Газораспределительные станции (ГРС)",
        "group": "станции",
        "family": FAMILY_STATION,
        "category": "other",
        "defaults": {"shell_count": 4},
    },
    {
        "code": "complex_periodic",
        "form_id": "to-10",
        "title": "Комплексное периодическое обследование",
        "group": "прочее",
        "family": FAMILY_GENERIC,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "gpa",
        "form_id": "to-11",
        "title": "Газоперекачивающие агрегаты (ГПА)",
        "group": "машины",
        "family": FAMILY_MACHINERY,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "compressor",
        "form_id": "to-12",
        "title": "Центробежные нагнетатели (корпус и ротор)",
        "group": "машины",
        "family": FAMILY_MACHINERY,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "pipeline",
        "form_id": "to-13",
        "title": "Технологические трубопроводы",
        "group": "трубопроводы",
        "family": FAMILY_PIPELINE,
        "category": "pipeline",
        "defaults": {"shell_count": 4, "weld_preset": "ring_only"},
    },
    {
        "code": "acceptance",
        "form_id": "to-14",
        "title": "Приёмочное (первичное) обследование",
        "group": "прочее",
        "family": FAMILY_GENERIC,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "diesel_station",
        "form_id": "to-15",
        "title": "Аварийные дизельные электростанции",
        "group": "электрооборудование",
        "family": FAMILY_ELECTRICAL,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "cable_line",
        "form_id": "to-16",
        "title": "Кабельные линии 6–10 кВ",
        "group": "электрооборудование",
        "family": FAMILY_ELECTRICAL,
        "category": "other",
        "defaults": {"shell_count": 6},
    },
    {
        "code": "gpa_drive",
        "form_id": "to-17",
        "title": "Электроприводы ГПА",
        "group": "машины",
        "family": FAMILY_MACHINERY,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "riverbed",
        "form_id": "to-18",
        "title": "Мониторинг русловых процессов",
        "group": "прочее",
        "family": FAMILY_GENERIC,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "diver_survey",
        "form_id": "to-19",
        "title": "Приборно-водолазное обследование",
        "group": "прочее",
        "family": FAMILY_GENERIC,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "pig_trap",
        "form_id": "to-20",
        "title": "Камеры запуска-приёма ВТУ",
        "group": "емкостное",
        "family": FAMILY_VESSEL_DEV,
        "category": "vessel",
        "defaults": {"orientation": "horizontal", "shell_count": 2, "weld_preset": "long_plus_rings"},
    },
    {
        "code": "pipeline_crossing",
        "form_id": "to-21",
        "title": "Переходы под авто- и ж/д дорогами",
        "group": "трубопроводы",
        "family": FAMILY_PIPELINE,
        "category": "pipeline",
        "defaults": {"shell_count": 3, "weld_preset": "ring_only"},
    },
    {
        "code": "main_pipeline",
        "form_id": "to-22",
        "title": "Линейная часть магистральных газопроводов",
        "group": "трубопроводы",
        "family": FAMILY_PIPELINE,
        "category": "pipeline",
        "defaults": {"shell_count": 8, "weld_preset": "ring_only"},
    },
    {
        "code": "air_cooler",
        "form_id": "to-23",
        "title": "Аппараты воздушного охлаждения газа (АВО)",
        "group": "емкостное",
        "family": FAMILY_VESSEL_DEV,
        "category": "vessel",
        "defaults": {"orientation": "horizontal", "shell_count": 2, "weld_preset": "long_plus_rings"},
    },
    {
        "code": "pipeline_valve",
        "form_id": "to-24",
        "title": "Трубопроводная арматура",
        "group": "арматура",
        "family": FAMILY_VALVE,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "tank",
        "form_id": "to-25",
        "title": "Резервуары (ёмкости)",
        "group": "емкостное",
        "family": FAMILY_TANK,
        "category": "underground_tank",
        "defaults": {"shell_count": 4, "weld_preset": "multi_shell"},
    },
    {
        "code": "wellhead_piping",
        "form_id": "to-26",
        "title": "Трубопроводы обвязки устья скважин",
        "group": "трубопроводы",
        "family": FAMILY_PIPELINE,
        "category": "pipeline",
        "defaults": {"shell_count": 4, "weld_preset": "ring_only"},
    },
    {
        "code": "wellhead_tree",
        "form_id": "to-27",
        "title": "Фонтанная арматура и колонная головка",
        "group": "арматура",
        "family": FAMILY_VALVE,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "boiler",
        "form_id": "to-28",
        "title": "Паровые и водогрейные котлы",
        "group": "котлы",
        "family": FAMILY_BOILER,
        "category": "other",
        "defaults": {"shell_count": 2, "weld_preset": "long_plus_rings"},
    },
    {
        "code": "pu_unit",
        "form_id": "to-29",
        "title": "Комплексное обследование ПУ",
        "group": "станции",
        "family": FAMILY_STATION,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "boiler_aux",
        "form_id": "to-30",
        "title": "Вспомогательное котельное оборудование",
        "group": "котлы",
        "family": FAMILY_BOILER,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "gas_pipeline_gx",
        "form_id": "to-31",
        "title": "Газопроводы ГХ",
        "group": "трубопроводы",
        "family": FAMILY_PIPELINE,
        "category": "pipeline",
        "defaults": {"shell_count": 5, "weld_preset": "ring_only"},
    },
    {
        "code": "aboveground_pipeline",
        "form_id": "to-32",
        "title": "Надземные газопроводы",
        "group": "трубопроводы",
        "family": FAMILY_PIPELINE,
        "category": "pipeline",
        "defaults": {"shell_count": 5, "weld_preset": "ring_only"},
    },
    {
        "code": "underground_pipeline",
        "form_id": "to-33",
        "title": "Подземные трубопроводы",
        "group": "трубопроводы",
        "family": FAMILY_PIPELINE,
        "category": "pipeline",
        "defaults": {"shell_count": 5, "weld_preset": "ring_only"},
    },
    {
        "code": "ventilation",
        "form_id": "to-34",
        "title": "Системы вентиляции и кондиционирования",
        "group": "прочее",
        "family": FAMILY_GENERIC,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "prg",
        "form_id": "to-35",
        "title": "ПРГ",
        "group": "станции",
        "family": FAMILY_STATION,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "power_station",
        "form_id": "to-36",
        "title": "Электростанции собственных нужд",
        "group": "электрооборудование",
        "family": FAMILY_ELECTRICAL,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "gis_station",
        "form_id": "to-37",
        "title": "ГИС, ПЗРГ, УИРГ",
        "group": "станции",
        "family": FAMILY_STATION,
        "category": "other",
        "defaults": {"shell_count": 3},
    },
    {
        "code": "aux_equipment",
        "form_id": "to-38",
        "title": "Вспомогательное оборудование (УСБ, ВЭИ)",
        "group": "прочее",
        "family": FAMILY_GENERIC,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "chimney",
        "form_id": "to-39",
        "title": "Дымовые трубы",
        "group": "башни",
        "family": FAMILY_TOWER,
        "category": "other",
        "defaults": {"shell_count": 4, "weld_preset": "long_plus_rings"},
    },
    {
        "code": "metering",
        "form_id": "to-40",
        "title": "Замерные устройства",
        "group": "арматура",
        "family": FAMILY_VALVE,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "buildings",
        "form_id": "to-41",
        "title": "Здания и сооружения (ЗиС)",
        "group": "прочее",
        "family": FAMILY_GENERIC,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "switchgear",
        "form_id": "to-42",
        "title": "Распределительные устройства",
        "group": "электрооборудование",
        "family": FAMILY_ELECTRICAL,
        "category": "other",
        "defaults": {},
    },
    {
        "code": "water_tank",
        "form_id": "to-43",
        "title": "Резервуары воды",
        "group": "емкостное",
        "family": FAMILY_TANK,
        "category": "underground_tank",
        "defaults": {"shell_count": 3, "weld_preset": "multi_shell"},
    },
    {
        "code": "flare",
        "form_id": "to-44",
        "title": "Факельное оборудование",
        "group": "башни",
        "family": FAMILY_TOWER,
        "category": "other",
        "defaults": {"shell_count": 3, "weld_preset": "long_plus_rings"},
    },
    # Доп. алиасы сосудоподобных (уже в системе, форма to-1 / to-25)
    {
        "code": "gas_separator",
        "form_id": "to-1",
        "title": "Газосепаратор",
        "group": "емкостное",
        "family": FAMILY_VESSEL_DEV,
        "category": "gas_separator",
        "defaults": {"orientation": "vertical", "shell_count": 5, "weld_preset": "multi_shell"},
        "alias_of": "vessel",
    },
    {
        "code": "underground_tank",
        "form_id": "to-25",
        "title": "Ёмкость подземная",
        "group": "емкостное",
        "family": FAMILY_TANK,
        "category": "underground_tank",
        "defaults": {"shell_count": 3, "weld_preset": "multi_shell"},
        "alias_of": "tank",
    },
    {
        "code": "oil_settler",
        "form_id": "to-1",
        "title": "Отстойник нефти",
        "group": "емкостное",
        "family": FAMILY_VESSEL_DEV,
        "category": "oil_settler",
        "defaults": {"orientation": "horizontal", "shell_count": 3, "weld_preset": "multi_shell"},
        "alias_of": "vessel",
    },
]

_BY_CODE: Dict[str, Dict[str, Any]] = {k["code"]: k for k in EQUIPMENT_SCHEME_KINDS}
_BY_FORM: Dict[str, List[Dict[str, Any]]] = {}
for _item in EQUIPMENT_SCHEME_KINDS:
    _BY_FORM.setdefault(str(_item["form_id"]), []).append(_item)

# Группы для UI (порядок)
GROUP_ORDER = [
    "емкостное",
    "трубопроводы",
    "грузоподъёмное",
    "машины",
    "котлы",
    "арматура",
    "электрооборудование",
    "станции",
    "башни",
    "прочее",
]


def list_scheme_kinds(*, include_aliases: bool = True) -> List[Dict[str, Any]]:
    """Список видов для API / UI."""
    items = []
    for k in EQUIPMENT_SCHEME_KINDS:
        if not include_aliases and k.get("alias_of"):
            continue
        items.append(
            {
                "code": k["code"],
                "form_id": k["form_id"],
                "title": k["title"],
                "group": k["group"],
                "family": k["family"],
                "family_title": SCHEME_FAMILIES.get(k["family"], k["family"]),
                "category": k.get("category") or "other",
                "defaults": dict(k.get("defaults") or {}),
            }
        )
    # Сортировка: по номеру формы, затем по title
    def _key(it: Dict[str, Any]):
        fid = str(it.get("form_id") or "to-99")
        try:
            num = int(fid.replace("to-", ""))
        except ValueError:
            num = 99
        return (num, it.get("title") or "")

    items.sort(key=_key)
    return items


def get_kind(code: Optional[str]) -> Optional[Dict[str, Any]]:
    if not code:
        return None
    c = str(code).lower().strip().replace("-", "_").replace(" ", "_")
    # to-12 → compressor
    if c.startswith("to_") or c.startswith("to"):
        fid = c.replace("_", "-")
        if not fid.startswith("to-"):
            fid = "to-" + fid.replace("to", "")
        arr = _BY_FORM.get(fid) or []
        if arr:
            return arr[0]
    return _BY_CODE.get(c)


def resolve_family(code: Optional[str]) -> str:
    meta = get_kind(code)
    if meta:
        return str(meta.get("family") or FAMILY_GENERIC)
    return FAMILY_GENERIC


def family_for_form_id(form_id: Optional[str]) -> str:
    """Семейство схемы/обследования по id формы ТО (to-N)."""
    fid = (form_id or "").strip().lower()
    if not fid:
        return FAMILY_GENERIC
    arr = _BY_FORM.get(fid) or []
    # предпочитаем primary (без alias_of)
    for item in arr:
        if not item.get("alias_of"):
            return str(item.get("family") or FAMILY_GENERIC)
    if arr:
        return str(arr[0].get("family") or FAMILY_GENERIC)
    return FAMILY_GENERIC


def kind_title(code: Optional[str]) -> str:
    meta = get_kind(code)
    if meta:
        return str(meta.get("title") or code or "Схема")
    return "Карта контроля"


def form_id_for_kind(code: Optional[str]) -> Optional[str]:
    meta = get_kind(code)
    return str(meta["form_id"]) if meta else None


def defaults_for_kind(code: Optional[str]) -> Dict[str, Any]:
    meta = get_kind(code)
    return dict((meta or {}).get("defaults") or {})
