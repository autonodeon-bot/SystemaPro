"""
Опубликованная по умолчанию структура меню «Протокол → создать» (xlsx «структура диагностических данных»).
Сериализуется в JSON для mobile/web.
"""

from __future__ import annotations

from typing import Any


def _qc(
    nid: str,
    title: str,
    *,
    subtitle: str | None = None,
    protocol_hint: str | None = None,
    action: str | None = None,
    icon: str = "description_outlined",
    children: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    node: dict[str, Any] = {
        "id": nid,
        "title": title,
        "icon": icon,
        "children": children or [],
    }
    if subtitle:
        node["subtitle"] = subtitle
    if protocol_hint:
        node["protocol_hint"] = protocol_hint
    if action:
        node["action"] = action
    return node


def _archetype(kind: str, mark: str = "") -> dict[str, str]:
    return {"kind": kind, "example_mark": mark}


def _category(
    cid: str,
    title: str,
    icon: str,
    preset: str,
    labels: list[str],
    archetypes: list[dict[str, str]],
) -> dict[str, Any]:
    return {
        "id": cid,
        "title": title,
        "icon": icon,
        "equipment_preset": preset,
        "inspection_type_labels": labels,
        "archetypes": archetypes,
    }


def build_default_diagnostic_menu() -> dict[str, Any]:
    quick_control = [
        _qc(
            "emergency",
            "Аварийный, внеплановый контроль (осмотр)",
            subtitle="Минимум полей, фиксация аварийной ситуации",
            protocol_hint="Протокол аварийной ситуации",
            action="emergencyInspection",
            icon="emergency_share_outlined",
        ),
        _qc(
            "express_ndt",
            "Экспресс-диагностика НК",
            subtitle="ВИК, УЗТ, УЗК, ПВК",
            protocol_hint="Протоколы НК (шаблоны по методам)",
            icon="speed_outlined",
            children=[
                _qc("vik", "ВИК", action="expressNdtVik", icon="visibility_outlined"),
                _qc("uzt", "УЗТ", action="expressNdtUzt", icon="straighten_outlined"),
                _qc("uzk", "УЗК", action="expressNdtUzk", icon="graphic_eq"),
                _qc("pvk", "ПВК", action="expressNdtPvk", icon="blur_circular_outlined"),
            ],
        ),
        _qc(
            "pressure",
            "Опрессовка",
            subtitle="ГИ, ПИ, испытания ПС и ГПМ",
            protocol_hint="Протоколы опрессовки / испытаний",
            icon="plumbing_outlined",
            children=[
                _qc(
                    "gi",
                    "ГИ",
                    subtitle="Гидравлические испытания",
                    action="pressureGi",
                    icon="water_drop_outlined",
                ),
                _qc(
                    "pi",
                    "ПИ",
                    subtitle="Пневматические испытания",
                    action="pressurePi",
                    icon="compress_outlined",
                ),
                _qc(
                    "ps_gpm",
                    "Испытание ПС и ГПМ",
                    subtitle="Статика и динамика",
                    action="pressurePsGpm",
                    icon="precision_manufacturing_outlined",
                ),
            ],
        ),
    ]

    categories = [
        _category(
            "srpd",
            "СРпД (сосуды, аппараты, ёмкости)",
            "propane_tank_outlined",
            "vessel",
            ["НиВО", "ГИ (ПИ + АЭ)", "ТД", "ЭПБ"],
            [
                _archetype("Сепаратор", "М-103А"),
                _archetype("Ресивер"),
                _archetype("Ёмкость подземная", "ЕП-12,5-2000-1300-2"),
                _archetype("Газосепаратор", "ГС 1.1"),
                _archetype("Нефтегазосепаратор", "НГС1-1,0-3000-2"),
                _archetype("Нефтегазосепаратор", "НГС-1-10-2600-0,9Г2С"),
                _archetype("Сепаратор факельный", "СФ"),
                _archetype("Отстойник", "ОГ-200"),
                _archetype("Воздухосборник", "V-2,7 м³"),
            ],
        ),
        _category(
            "bu",
            "БУ (буровая установка)",
            "architecture",
            "drilling",
            ["ТД (ЭПБ)"],
            [
                _archetype("Буровая установка", "БУ 3000 ЭУК-1М"),
                _archetype("Буровая установка", "БУ 3900/225 ЭК-БМ"),
                _archetype("Буровая установка", "БУ 2900/175 ДЭП-11"),
                _archetype("Буровая установка", "БУ 2900/175 ЭПК БМ"),
            ],
        ),
        _category(
            "boiler",
            "Котёл",
            "local_fire_department_outlined",
            "boiler",
            ["НиВО", "ГИ (ПИ + АЭ)", "ТД", "ЭПБ"],
            [
                _archetype("Котёл паровой", "Е 1,0-0,9М"),
                _archetype("Котёл паровой", "КПН-1,0-9М"),
                _archetype("Котёл паровой", "ПКН-2М"),
                _archetype("Горелка", "PN-65"),
                _archetype("Горелка", "PN-70"),
            ],
        ),
        _category(
            "bo",
            "БО (буровое оборудование)",
            "build_circle_outlined",
            "other",
            ["ТД (ЭПБ)"],
            [
                _archetype("Насос буровой трехпоршневой", "УНБ-600"),
                _archetype("Насос буровой трехпоршневой", "УНБТ-1180"),
                _archetype("Ротор буровой", "Р-700"),
                _archetype("Лебедка буровая", "ЛБУ-750Э-СНГ"),
                _archetype("Лебедка вспомогательная", "ЛВ-44-1"),
            ],
        ),
        _category(
            "valve_ps",
            "Клапан предохранительный",
            "air_outlined",
            "valve_ps",
            ["ТД (ЭПБ)", "Испытания (тарировка, опрессовка и т.д.)"],
            [
                _archetype("СППК", "4P 80-40"),
                _archetype("СППК", "4 50х16 УХЛ1"),
                _archetype("Клапан предохранительно-сбросной", "ПСК 535 DN20 PN40"),
                _archetype("СППК", "5 100х16 УХЛ1"),
            ],
        ),
    ]

    return {
        "version": 1,
        "new_protocol_description": (
            "Протоколы на все типы обследования; пополняемая опытная база по маркам и модификациям "
            "оборудования. Данные привязываются к паре «Задание» — «Объект»."
        ),
        "quick_control_tree": quick_control,
        "object_categories": categories,
        "create_menu_actions": [
            {
                "id": "new_protocol",
                "action": "newProtocolWizard",
                "title": "Новый протокол",
                "subtitle": "Тип объекта → направление / тип обследования",
                "icon": "account_tree_outlined",
                "color": "#B388FF",
            },
            {
                "id": "experience_base",
                "action": "experienceBase",
                "title": "Опытная база",
                "subtitle": "Справочник марок и записи сообщества",
                "icon": "menu_book_outlined",
                "color": "#4FC3F7",
            },
            {
                "id": "custom_template",
                "action": "customTemplate",
                "title": "Конструктор протокола",
                "subtitle": "Протокол из пользовательского шаблона",
                "icon": "layers_outlined",
                "color": "#4DB6AC",
            },
        ],
    }


DEFAULT_DIAGNOSTIC_MENU: dict[str, Any] = build_default_diagnostic_menu()
