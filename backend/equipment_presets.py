"""
Реестр пресетов СРпД: связь type_code → preset → терминология отчёта.

Используется при подборе шаблонов обследования и генерации Word.
"""
from __future__ import annotations

from typing import Any, Dict, Optional

# Код типа оборудования (equipment_types.code) → preset шаблона
TYPE_CODE_TO_PRESET: Dict[str, str] = {
    "VESSEL": "vessel",
    "GAS_SEPARATOR": "gas_separator",
    "GAS_SEP": "gas_separator",
    "UNDERGROUND_TANK": "underground_tank",
    "OIL_SETTLER": "oil_settler",
    "RECEIVER": "receiver",
}

# preset → kind для pressure_device_labels
PRESET_TO_KIND: Dict[str, str] = {
    "vessel": "vessel",
    "gas_separator": "gas_separator",
    "underground_tank": "underground_tank",
    "oil_settler": "oil_settler",
    "receiver": "receiver",
}

PRESET_DEFAULT_PURPOSE: Dict[str, str] = {
    "gas_separator": "сепарация нефти и попутного нефтяного газа",
    "underground_tank": (
        "слив нефти, нефтегазоводяной смеси из технологических трубопроводов и аппаратов"
    ),
    "oil_settler": "трехфазное разделение предварительно подготовленной нефти (нефтегазоводяной смеси)",
    "receiver": "накопление и выравнивание давления рабочей среды",
}

# Низкое давление (РУА-93) vs стандартное (приказ №536)
PRESET_PRESSURE_REGIME: Dict[str, str] = {
    "underground_tank": "low",
    "vessel": "high",
    "gas_separator": "high",
    "oil_settler": "high",
    "receiver": "high",
}


def preset_from_type_code(type_code: Optional[str]) -> Optional[str]:
    if not type_code:
        return None
    return TYPE_CODE_TO_PRESET.get(type_code.strip().upper())


def kind_from_preset(preset: Optional[str]) -> str:
    if not preset:
        return "vessel"
    return PRESET_TO_KIND.get(preset, "vessel")


def preset_from_equipment_data(equipment_data: Dict[str, Any]) -> str:
    """Определить preset по type_code, type_name и attributes."""
    code = (equipment_data.get("type_code") or "").upper()
    preset = preset_from_type_code(code)
    if preset:
        return preset

    name = (equipment_data.get("type_name") or "").upper()
    eq_name = (equipment_data.get("name") or "").upper()
    attrs = equipment_data.get("attributes") or {}
    if not isinstance(attrs, dict):
        attrs = {}
    object_type = str(attrs.get("object_type") or attrs.get("equipment_kind") or "").lower()
    hay = f"{name} {eq_name} {object_type}"

    if "GAS_SEP" in code or "ГАЗОСЕПАРАТОР" in hay or object_type == "gas_separator":
        return "gas_separator"
    if "UNDERGROUND" in code or "ЁМКОСТ" in hay or "ЕМКОСТ" in hay or "ПОДЗЕМН" in hay:
        return "underground_tank"
    if "OIL_SETTLER" in code or "ОТСТОЙНИК" in hay or object_type == "oil_settler":
        return "oil_settler"
    if "РЕСИВЕР" in hay or object_type == "receiver":
        return "receiver"
    return "vessel"


def default_purpose_for_preset(preset: str) -> Optional[str]:
    return PRESET_DEFAULT_PURPOSE.get(preset)


def pressure_regime_for_preset(preset: str) -> str:
    return PRESET_PRESSURE_REGIME.get(preset, "high")
