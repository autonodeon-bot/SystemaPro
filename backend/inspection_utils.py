# Утилиты для создания обследований (используются в main и inspection_archive_api)

# Поля технической характеристики для обновления equipment.attributes при утверждении
_TECH_ATTR_KEYS = (
    "purpose", "commissioning_year", "design_pressure", "test_pressure",
    "working_temperature", "design_temperature", "working_medium",
    "medium_characteristics", "vessel_group", "medium_group",
    "corrosion_allowance", "previous_inspection_result",
)


async def update_equipment_attributes_from_inspection(db, equipment_id, inspection_data_dict: dict):
    """Обновляет attributes оборудования данными из обследования при утверждении (SIGNED)."""
    if not equipment_id or not inspection_data_dict or not isinstance(inspection_data_dict, dict):
        return
    from models import Equipment
    from sqlalchemy import select
    data = inspection_data_dict
    updates = {}
    for k in _TECH_ATTR_KEYS:
        v = data.get(k)
        if v is not None and str(v).strip():
            updates[k] = str(v).strip()
    # camelCase варианты (мобильное иногда присылает)
    camel_map = {
        "commissioningYear": "commissioning_year",
        "designPressure": "design_pressure",
        "testPressure": "test_pressure",
        "workingTemperature": "working_temperature",
        "designTemperature": "design_temperature",
        "workingMedium": "working_medium",
        "mediumCharacteristics": "medium_characteristics",
        "vesselGroup": "vessel_group",
        "mediumGroup": "medium_group",
        "corrosionAllowance": "corrosion_allowance",
        "previousInspectionResult": "previous_inspection_result",
    }
    for camel, snake in camel_map.items():
        if snake not in updates and data.get(camel) not in (None, ""):
            updates[snake] = str(data.get(camel)).strip()
    if not updates:
        return
    # Обновляем equipment.attributes (merge с существующими)
    eq_result = await db.execute(select(Equipment).where(Equipment.id == equipment_id))
    equipment = eq_result.scalar_one_or_none()
    if not equipment:
        return
    attrs = dict(equipment.attributes or {})
    attrs.update(updates)
    equipment.attributes = attrs


def create_ndt_methods_from_mobile(db, inspection, questionnaire, equipment_id, inspection_data_dict: dict):
    """Создаёт записи NDTMethod из inspection_engineers/ndt_methods (мобильное приложение)."""
    if not inspection or not questionnaire or not equipment_id:
        return
    from models import NDTMethod
    _method_names = {
        "VIK": "ВИК", "ВИК": "Визуальный и измерительный контроль",
        "UZK": "УЗК", "УЗК": "Ультразвуковой контроль сварных соединений",
        "UZT": "УЗТ", "УЗТ": "Ультразвуковая толщинометрия",
        "PVK": "ПВК", "ПВК": "Пневматические испытания",
        "MK": "МК", "МК": "Магнитный контроль", "RK": "РК", "РК": "Радиографический контроль",
    }
    _full_names = {
        "VIK": "Визуальный и измерительный контроль",
        "UZK": "Ультразвуковой контроль сварных соединений",
        "UZT": "Ультразвуковая толщинометрия",
        "PVK": "Пневматические испытания",
        "MK": "Магнитный контроль",
        "RK": "Радиографический контроль",
    }
    engineers = inspection_data_dict.get("inspection_engineers") or []
    ndt_codes = set(str(c).strip().upper() for c in (inspection_data_dict.get("ndt_methods") or []))
    seen = set()
    for ie in engineers if isinstance(engineers, list) else []:
        if not isinstance(ie, dict):
            continue
        m_code = (ie.get("method") or "").strip().upper()
        if not m_code:
            continue
        m_ru = _method_names.get(m_code) or m_code
        name_full = _full_names.get(m_code) or m_ru
        cert_num = ie.get("certificate_number")
        ad = {"certificate_number": cert_num} if cert_num else {}
        if ie.get("valid_until"):
            ad["valid_until"] = ie.get("valid_until")
        ndt = NDTMethod(
            inspection_id=inspection.id,
            questionnaire_id=questionnaire.id,
            equipment_id=equipment_id,
            method_code=m_ru,
            method_name=name_full,
            is_performed=1,
            inspector_name=ie.get("full_name"),
            inspector_level=ie.get("level"),
            standard="приказ Ростехнадзора от 15.12.2020 №536",
            equipment=ie.get("equipment"),
            additional_data=ad if ad else None,
        )
        db.add(ndt)
        seen.add(m_code)
    for code in ndt_codes:
        if code in seen:
            continue
        m_ru = _method_names.get(code) or code
        name_full = _full_names.get(code) or m_ru
        ndt = NDTMethod(
            inspection_id=inspection.id,
            questionnaire_id=questionnaire.id,
            equipment_id=equipment_id,
            method_code=m_ru,
            method_name=name_full,
            is_performed=1,
            standard="приказ Ростехнадзора от 15.12.2020 №536",
        )
        db.add(ndt)
