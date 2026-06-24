"""
Единый реестр профилей оборудования — источник правды для шаблонов обследования и ЭПБ.

Добавление нового типа:
1. Запись в EQUIPMENT_PROFILES
2. Тип в equipment_types_seed.py (если новый code)
3. Seed шаблона обследования подтянется автоматически через build_inspection_default_data()
"""
from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from equipment_presets import (
    PRESET_DEFAULT_PURPOSE,
    PRESET_PRESSURE_REGIME,
    PRESET_TO_KIND,
    TYPE_CODE_TO_PRESET,
    pressure_regime_for_preset,
)

WELD_DATA_DEFAULT = "Сварка авто\nСВ08ГА\nГОСТ 2246-70\nУОНИ 13/55"
MISSING = "Данные в паспорте отсутствуют"


@dataclass
class EquipmentProfile:
    """Профиль типа оборудования для отчётов и чек-листов."""

    code: str
    preset: str
    display_name: str
    category: str = "srpd"
    equipment_kind: str = ""
    equipment_mark: Optional[str] = None
    normative_basis: str = "order_536"
    report_template_id: str = ""
    inspection_template_epb_id: str = ""
    inspection_template_nivo_id: str = ""
    # Поля чек-листа / карты обследования (ЭПБ)
    epb_fields: Dict[str, Any] = field(default_factory=dict)
    # Данные приложения Б (таблицы Б1–Б6) — подставляются в default_data шаблона
    passport_defaults: Dict[str, Any] = field(default_factory=dict)
    # Шаблон точек УЗТ: список {location, count, nominal_thickness}
    uzt_sections: List[Dict[str, Any]] = field(default_factory=list)

    @property
    def pressure_regime(self) -> str:
        return pressure_regime_for_preset(self.preset)

    @property
    def terminology_kind(self) -> str:
        return PRESET_TO_KIND.get(self.preset, "vessel")

    @property
    def default_purpose(self) -> str:
        return PRESET_DEFAULT_PURPOSE.get(self.preset, "")


def _oil_settler_elements() -> List[Dict[str, Any]]:
    return [
        {
            "name": "Обечайка",
            "diameter_mm": "3400",
            "length_mm": "21000",
            "wall_thickness_mm": "18,0",
            "material": "09Г2С-7",
            "gost": "5520-79",
            "weld_data": WELD_DATA_DEFAULT,
        },
        {
            "name": "Днище\nправое",
            "diameter_mm": "3400",
            "length_mm": "826",
            "wall_thickness_mm": "18,0",
            "material": "09Г2С-7",
            "gost": "5520-79",
            "weld_data": WELD_DATA_DEFAULT,
        },
        {
            "name": "Днище\nнижнее",
            "diameter_mm": "3400",
            "length_mm": "826",
            "wall_thickness_mm": "18,0",
            "material": "09Г2С-7",
            "gost": "5520-79",
            "weld_data": WELD_DATA_DEFAULT,
        },
    ]


def _default_fittings() -> List[Dict[str, str]]:
    return [
        {"name": "Датчик уровня ДУУ4", "quantity": "1", "dn": "-", "pressure": "-"},
        {"name": "Манометр", "quantity": "1", "dn": "-", "pressure": "-"},
        {"name": "Переключающее устройство", "quantity": "1", "dn": "100", "pressure": "1,6 (16,0)"},
        {"name": "Предохранительный клапан", "quantity": "2", "dn": "100", "pressure": "1,6 (16,0)"},
    ]


def _uzt_points(sections: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Сгенерировать пустые точки УЗТ по секциям профиля."""
    points: List[Dict[str, Any]] = []
    for sec in sections:
        loc = sec["location"]
        count = int(sec.get("count", 36))
        nominal = sec.get("nominal_thickness", "18,0")
        for i in range(1, count + 1):
            points.append(
                {
                    "location": loc,
                    "section_number": i,
                    "nominal_thickness": nominal,
                    "thickness": None,
                    "min_allowed_thickness": sec.get("min_allowed_thickness"),
                }
            )
    return points


EQUIPMENT_PROFILES: Dict[str, EquipmentProfile] = {
    "OIL_SETTLER": EquipmentProfile(
        code="OIL_SETTLER",
        preset="oil_settler",
        display_name="Отстойник нефти",
        equipment_kind="Отстойник нефти",
        equipment_mark="ОГ",
        report_template_id="rt-srpd-oil-settler-epb-docx",
        inspection_template_epb_id="iot-srpd-oil-settler-epb",
        inspection_template_nivo_id="iot-srpd-oil-settler-nivo",
        epb_fields={
            "scheme_index": "ОГ-13",
            "construction_type": "горизонтальный с эллиптическими днищами",
            "working_pressure": 1.0,
            "design_pressure": 1.0,
            "test_pressure": 1.3,
            "working_temperature": "плюс 100",
            "design_temperature": "минус 45",
            "working_medium": "нефть, попутный нефтяной газ, попутная вода",
            "volume": 200,
            "wall_thickness": "18,0",
            "diameter": "3400",
            "corrosion_allowance": "3,0",
            "min_allowed_thickness": "15,0",
            "residual_life_text": "более 10 лет",
        },
        passport_defaults={
            "vessel_elements": _oil_settler_elements(),
            "heat_treatment_records": [
                {
                    "element": "Сварные соединения",
                    "type": "Отпуск",
                    "temperature": "620-640",
                    "duration": "2",
                    "cooling": "на воздухе",
                }
            ],
            "hydraulic_test_history": [
                {
                    "date": "1998",
                    "test_type": "гидравлическое",
                    "pressure": "1,3 (13,0)",
                    "medium": "вода",
                    "note": "Эксплуатирующая организация",
                }
            ],
            "ndt_control_history": [
                {
                    "date": "1998",
                    "scope": "Рентген, АУЗК, УЗК-100%",
                    "result": "Дефектов не обнаружено",
                    "organization": "Завод-изготовитель",
                },
                {
                    "date": "2014",
                    "scope": "ЭПБ",
                    "result": "Дефектов не обнаружено. Ресурс — более 10 лет",
                    "organization": "ООО «Диатэкс»",
                },
            ],
            "repair_history": [
                {
                    "year": MISSING,
                    "description": MISSING,
                    "ndt_result": MISSING,
                }
            ],
            "fittings_and_instruments": _default_fittings(),
        },
        uzt_sections=[
            {"location": "Обечайка", "count": 36, "nominal_thickness": "18,0", "min_allowed_thickness": "15,0"},
            {"location": "Днище правое", "count": 36, "nominal_thickness": "18,0", "min_allowed_thickness": "15,0"},
            {"location": "Днище нижнее", "count": 36, "nominal_thickness": "18,0", "min_allowed_thickness": "15,0"},
        ],
    ),
    "GAS_SEPARATOR": EquipmentProfile(
        code="GAS_SEPARATOR",
        preset="gas_separator",
        display_name="Газосепаратор",
        equipment_kind="Газосепаратор",
        report_template_id="rt-srpd-gas-separator-epb-docx",
        inspection_template_epb_id="iot-srpd-gas-separator-epb",
        inspection_template_nivo_id="iot-srpd-gas-separator-nivo",
        epb_fields={
            "construction_type": "горизонтальный",
            "working_pressure": 1.6,
            "working_medium": "нефть, попутный нефтяной газ",
            "wall_thickness": "14,0",
            "corrosion_allowance": "2,0",
        },
        passport_defaults={
            "vessel_elements": [
                {
                    "name": "Обечайка",
                    "diameter_mm": "1600",
                    "length_mm": "6000",
                    "wall_thickness_mm": "14,0",
                    "material": "09Г2С-12",
                    "gost": "5520-79",
                    "weld_data": WELD_DATA_DEFAULT,
                },
                {
                    "name": "Днище\nлевое",
                    "diameter_mm": "1600",
                    "length_mm": "400",
                    "wall_thickness_mm": "14,0",
                    "material": "09Г2С-12",
                    "gost": "5520-79",
                    "weld_data": WELD_DATA_DEFAULT,
                },
                {
                    "name": "Днище\nправое",
                    "diameter_mm": "1600",
                    "length_mm": "400",
                    "wall_thickness_mm": "14,0",
                    "material": "09Г2С-12",
                    "gost": "5520-79",
                    "weld_data": WELD_DATA_DEFAULT,
                },
            ],
            "hydraulic_test_history": [
                {
                    "date": MISSING,
                    "test_type": "гидравлическое",
                    "pressure": MISSING,
                    "medium": "вода",
                    "note": "",
                }
            ],
            "ndt_control_history": [
                {
                    "date": MISSING,
                    "scope": "Рентген, УЗК",
                    "result": "Дефектов не обнаружено",
                    "organization": MISSING,
                }
            ],
            "repair_history": [{"year": MISSING, "description": MISSING, "ndt_result": MISSING}],
            "fittings_and_instruments": _default_fittings(),
        },
        uzt_sections=[
            {"location": "Обечайка", "count": 24, "nominal_thickness": "14,0"},
            {"location": "Днище левое", "count": 12, "nominal_thickness": "14,0"},
            {"location": "Днище правое", "count": 12, "nominal_thickness": "14,0"},
        ],
    ),
    "UNDERGROUND_TANK": EquipmentProfile(
        code="UNDERGROUND_TANK",
        preset="underground_tank",
        display_name="Ёмкость подземная",
        equipment_kind="Ёмкость подземная",
        equipment_mark="ЕПП",
        normative_basis="rua_93",
        report_template_id="rt-srpd-underground-tank-epb-docx",
        inspection_template_epb_id="iot-srpd-underground-tank-epb",
        inspection_template_nivo_id="iot-srpd-underground-tank-nivo",
        epb_fields={
            "construction_type": "горизонтальный с коническими днищами",
            "working_pressure": 0.07,
            "pressure_category": "low",
            "working_medium": "нефть, нефтегазоводяная смесь",
            "wall_thickness": "6,0",
        },
        passport_defaults={
            "vessel_elements": [
                {
                    "name": "Обечайка",
                    "diameter_mm": "2600",
                    "length_mm": "12000",
                    "wall_thickness_mm": "6,0",
                    "material": "09Г2С-12",
                    "gost": "5520-79",
                    "weld_data": WELD_DATA_DEFAULT,
                },
            ],
            "hydraulic_test_history": [
                {
                    "date": MISSING,
                    "test_type": "гидравлическое",
                    "pressure": "0,1 (1,0)",
                    "medium": "вода",
                    "note": "",
                }
            ],
            "ndt_control_history": [
                {
                    "date": MISSING,
                    "scope": "ВИК, УЗК",
                    "result": "Дефектов не обнаружено",
                    "organization": MISSING,
                }
            ],
            "repair_history": [{"year": MISSING, "description": MISSING, "ndt_result": MISSING}],
            "fittings_and_instruments": _default_fittings(),
        },
        uzt_sections=[
            {"location": "Обечайка", "count": 24, "nominal_thickness": "6,0"},
        ],
    ),
    "VESSEL": EquipmentProfile(
        code="VESSEL",
        preset="vessel",
        display_name="Сосуд",
        equipment_kind="Сосуд",
        report_template_id="rt-srpd-vessel-epb-docx",
        epb_fields={
            "construction_type": "горизонтальный",
            "working_pressure": 1.6,
            "wall_thickness": "10,0",
        },
        passport_defaults={
            "vessel_elements": [
                {
                    "name": "Обечайка",
                    "diameter_mm": "1000",
                    "length_mm": "3000",
                    "wall_thickness_mm": "10,0",
                    "material": "09Г2С-12",
                    "gost": "5520-79",
                    "weld_data": WELD_DATA_DEFAULT,
                },
            ],
            "repair_history": [{"year": MISSING, "description": MISSING, "ndt_result": MISSING}],
            "fittings_and_instruments": _default_fittings(),
        },
        uzt_sections=[
            {"location": "Обечайка", "count": 16, "nominal_thickness": "10,0"},
        ],
    ),
}


def profile_by_code(type_code: Optional[str]) -> Optional[EquipmentProfile]:
    if not type_code:
        return None
    return EQUIPMENT_PROFILES.get(type_code.strip().upper())


def profile_by_preset(preset: Optional[str]) -> Optional[EquipmentProfile]:
    if not preset:
        return None
    for p in EQUIPMENT_PROFILES.values():
        if p.preset == preset:
            return p
    return None


def list_profiles() -> List[EquipmentProfile]:
    return list(EQUIPMENT_PROFILES.values())


def profile_to_api_dict(profile: EquipmentProfile) -> Dict[str, Any]:
    return {
        "code": profile.code,
        "preset": profile.preset,
        "display_name": profile.display_name,
        "category": profile.category,
        "equipment_kind": profile.equipment_kind,
        "equipment_mark": profile.equipment_mark,
        "pressure_regime": profile.pressure_regime,
        "normative_basis": profile.normative_basis,
        "terminology_kind": profile.terminology_kind,
        "default_purpose": profile.default_purpose,
        "report_template_id": profile.report_template_id,
        "inspection_template_epb_id": profile.inspection_template_epb_id,
        "inspection_template_nivo_id": profile.inspection_template_nivo_id,
        "epb_fields": deepcopy(profile.epb_fields),
        "passport_defaults": deepcopy(profile.passport_defaults),
        "uzt_sections": deepcopy(profile.uzt_sections),
    }


def build_inspection_default_data(
    preset: str,
    inspection_direction: str = "technical",
    *,
    include_uzt_template: bool = True,
) -> Dict[str, Any]:
    """
    Собрать default_data шаблона обследования из профиля оборудования.
    """
    profile = profile_by_preset(preset)
    if not profile:
        return {}

    is_epb = inspection_direction == "technical"
    data: Dict[str, Any] = {
        "equipment_type": profile.code,
        "purpose": profile.default_purpose,
        "pressure_category": profile.pressure_regime,
    }
    if is_epb:
        data["inspection_type"] = "EXPERTISE"
        data["include_opo_data"] = True
        data.update(deepcopy(profile.epb_fields))
        data.update(deepcopy(profile.passport_defaults))
        if include_uzt_template and profile.uzt_sections:
            data["thickness_measurements"] = _uzt_points(profile.uzt_sections)
        data["hardness_tests"] = data.get("hardness_tests") or [
            {
                "location": "К1+П1",
                "weld_number": "К1+П1",
                "allowed_hardness_base": "120-180",
                "allowed_hardness_weld": "225",
            }
        ]
        data["weld_inspections"] = data.get("weld_inspections") or [
            {
                "weld_number": "К1+П1*",
                "control_method": "MPK",
                "defect_description": "дефектов не обнаружено",
                "conclusion": "годен",
            },
            {
                "weld_number": "К1+П1*",
                "control_method": "UZK",
                "defect_description": "дефектов не обнаружено",
                "conclusion": "годен",
            },
        ]
        data["calculation_data"] = {"residual_life_years": 10}
    else:
        data["inspection_type"] = "VISUAL"

    return data


def passport_elements_for_equipment(equipment_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Элементы корпуса для таблицы Б1 — из профиля по type_code/preset."""
    from equipment_presets import preset_from_equipment_data

    code = (equipment_data.get("type_code") or "").upper()
    profile = profile_by_code(code) or profile_by_preset(preset_from_equipment_data(equipment_data))
    if profile and profile.passport_defaults.get("vessel_elements"):
        return deepcopy(profile.passport_defaults["vessel_elements"])
    if profile and profile.preset == "oil_settler":
        return _oil_settler_elements()
    return _oil_settler_elements()


def preset_from_type_code_extended(type_code: Optional[str]) -> Optional[str]:
    """Обратная совместимость: code → preset."""
    return TYPE_CODE_TO_PRESET.get((type_code or "").strip().upper())
