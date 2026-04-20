"""Карта «тип объекта + метод НК → применимая НТД».

Используется UI/backend для подсказок инженеру и для валидации протоколов.
Данные — упрощённая таблица; в реальном проекте лучше вынести в БД.
"""
from __future__ import annotations

from typing import Iterable

NORMS_MAP: dict[str, dict[str, list[str]]] = {
    # Сосуды и аппараты под давлением
    "pressure_vessel": {
        "VIC": ["РД 03-606-03", "ГОСТ Р 55724-2013"],
        "UT": ["ГОСТ Р ИСО 16809-2015", "РД 09-539-03"],
        "UZK": ["ГОСТ Р 55724-2013", "СА 03-008-08"],
        "MPD": ["ГОСТ Р 56512-2015"],
        "PT": ["ГОСТ Р 56511-2015"],
        "HT": ["ПБ 03-576-03", "СА 03-008-08"],
        "methodology": ["СА 03-008-08", "РД 09-539-03"],
    },
    # Резервуары вертикальные стальные
    "rvs": {
        "VIC": ["ПБ 03-605-03", "РД 153-39.4-078-01"],
        "UT": ["ПБ 03-605-03", "РД 153-39.4-078-01"],
        "UZK": ["ГОСТ Р 55724-2013"],
        "methodology": ["РД 153-39.4-078-01", "СА 03-002-05"],
    },
    # Трубопроводы
    "pipeline": {
        "VIC": ["РД 03-606-03"],
        "UT": ["ГОСТ Р ИСО 16809-2015"],
        "UZK": ["ГОСТ Р 55724-2013"],
        "methodology": ["РД 39-132-94", "СА 03-003-07"],
    },
    # ГПМ (грузоподъёмные механизмы)
    "lifting_mechanism": {
        "VIC": ["РД 10-112-96"],
        "methodology": ["РД 10-112-1-04", "ФНП «Подъёмные сооружения»"],
    },
}


def resolve_methods_for_object(object_type: str) -> dict[str, list[str]]:
    """Возвращает карту method→[нормы]. Пустой dict если тип неизвестен."""
    return dict(NORMS_MAP.get(object_type, {}))


def list_object_types() -> Iterable[str]:
    return NORMS_MAP.keys()


def applicable_methods(object_type: str) -> list[str]:
    """Список кодов методов НК, применимых к типу объекта (без methodology)."""
    methods = NORMS_MAP.get(object_type, {})
    return [m for m in methods.keys() if m != "methodology"]
