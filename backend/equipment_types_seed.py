"""
Идемпотентное наполнение справочника типов оборудования.
Коды синхронизированы с 44 формами ТО (scheme_equipment_catalog).
"""
from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models import EquipmentType

# Основные типы + покрытие форм to-1…to-44
DEFAULT_EQUIPMENT_TYPES = [
    {"code": "VESSEL", "name": "Сосуд под давлением", "description": "Сосуды и аппараты (ТО to-1)"},
    {"code": "GAS_SEPARATOR", "name": "Газосепаратор", "description": "Газосепаратор (ТО to-1)"},
    {"code": "CRANE_RUNWAY", "name": "Подкрановые пути", "description": "ТО to-2"},
    {"code": "CRANE", "name": "Грузоподъемный механизм", "description": "ГПМ (ТО to-3)"},
    {"code": "GAS_COLLECTOR", "name": "Газосборные шлейфы и коллекторы", "description": "ТО to-4"},
    {"code": "TRANSFORMER", "name": "Силовой трансформатор", "description": "ТО to-5"},
    {"code": "LIGHTNING_PROTECTION", "name": "Молниезащита и заземление", "description": "ТО to-6"},
    {"code": "DC_SYSTEM", "name": "Система постоянного тока", "description": "ТО to-7"},
    {"code": "ELECTRIC_MOTOR", "name": "Электродвигатель", "description": "ТО to-8"},
    {"code": "GRS", "name": "Газораспределительная станция", "description": "ГРС (ТО to-9)"},
    {"code": "COMPLEX_PERIODIC", "name": "Комплексное периодическое обследование", "description": "ТО to-10"},
    {"code": "GPA", "name": "Газоперекачивающий агрегат", "description": "ГПА (ТО to-11)"},
    {"code": "COMPRESSOR", "name": "Компрессор / нагнетатель", "description": "ТО to-12"},
    {"code": "PIPELINE", "name": "Трубопровод", "description": "Технологические трубопроводы (ТО to-13)"},
    {"code": "ACCEPTANCE", "name": "Приёмочное обследование", "description": "ТО to-14"},
    {"code": "DIESEL_STATION", "name": "Аварийная дизельная электростанция", "description": "ТО to-15"},
    {"code": "CABLE_LINE", "name": "Кабельная линия 6–10 кВ", "description": "ТО to-16"},
    {"code": "GPA_DRIVE", "name": "Электропривод ГПА", "description": "ТО to-17"},
    {"code": "RIVERBED", "name": "Мониторинг русловых процессов", "description": "ТО to-18"},
    {"code": "DIVER_SURVEY", "name": "Приборно-водолазное обследование", "description": "ТО to-19"},
    {"code": "PIG_TRAP", "name": "Камера запуска-приёма ВТУ", "description": "ТО to-20"},
    {"code": "PIPELINE_CROSSING", "name": "Переход под авто-/ж.д. дорогой", "description": "ТО to-21"},
    {"code": "MAIN_PIPELINE", "name": "Магистральный газопровод (ЛЧ)", "description": "ТО to-22"},
    {"code": "AIR_COOLER", "name": "Аппарат воздушного охлаждения", "description": "АВО (ТО to-23)"},
    {"code": "PIPELINE_VALVE", "name": "Трубопроводная арматура", "description": "ТО to-24"},
    {"code": "TANK", "name": "Резервуар (ёмкость)", "description": "ТО to-25"},
    {"code": "UNDERGROUND_TANK", "name": "Ёмкость подземная", "description": "ТО to-25"},
    {"code": "OIL_SETTLER", "name": "Отстойник нефти", "description": "ТО to-1 (сосуды/аппараты)"},
    {"code": "WELLHEAD_PIPING", "name": "Обвязка устья скважин", "description": "ТО to-26"},
    {"code": "WELLHEAD_TREE", "name": "Фонтанная арматура", "description": "ТО to-27"},
    {"code": "BOILER", "name": "Паровой / водогрейный котёл", "description": "ТО to-28"},
    {"code": "PU_UNIT", "name": "ПУ", "description": "ТО to-29"},
    {"code": "BOILER_AUX", "name": "Вспомогательное котельное оборудование", "description": "ТО to-30"},
    {"code": "GAS_PIPELINE_GX", "name": "Газопровод ГХ", "description": "ТО to-31"},
    {"code": "ABOVEGROUND_PIPELINE", "name": "Надземный газопровод", "description": "ТО to-32"},
    {"code": "UNDERGROUND_PIPELINE", "name": "Подземный трубопровод", "description": "ТО to-33"},
    {"code": "VENTILATION", "name": "Вентиляция и кондиционирование", "description": "ТО to-34"},
    {"code": "PRG", "name": "ПРГ", "description": "ТО to-35"},
    {"code": "POWER_STATION", "name": "Электростанция собственных нужд", "description": "ТО to-36"},
    {"code": "GIS_STATION", "name": "ГИС, ПЗРГ, УИРГ", "description": "ТО to-37"},
    {"code": "AUX_EQUIPMENT", "name": "Вспомогательное оборудование (УСБ, ВЭИ)", "description": "ТО to-38"},
    {"code": "CHIMNEY", "name": "Дымовая труба", "description": "ТО to-39"},
    {"code": "METERING", "name": "Замерное устройство", "description": "ТО to-40"},
    {"code": "BUILDINGS", "name": "Здания и сооружения", "description": "ЗиС (ТО to-41)"},
    {"code": "SWITCHGEAR", "name": "Распределительное устройство", "description": "ТО to-42"},
    {"code": "WATER_TANK", "name": "Резервуар воды", "description": "ТО to-43"},
    {"code": "FLARE", "name": "Факельное оборудование", "description": "ТО to-44"},
]


async def ensure_default_equipment_types(db: AsyncSession) -> int:
    """Создать или обновить базовые типы оборудования по коду."""
    count = 0
    for item in DEFAULT_EQUIPMENT_TYPES:
        result = await db.execute(
            select(EquipmentType).where(EquipmentType.code == item["code"])
        )
        existing = result.scalar_one_or_none()
        if existing:
            existing.name = item["name"]
            existing.description = item["description"]
            existing.is_active = True
        else:
            db.add(
                EquipmentType(
                    id=uuid.uuid4(),
                    code=item["code"],
                    name=item["name"],
                    description=item["description"],
                    is_active=True,
                )
            )
        count += 1
    await db.commit()
    return count
