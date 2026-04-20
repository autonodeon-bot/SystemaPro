"""Доменный движок диагностики (РД/СА/ГОСТ).

Здесь лежит бизнес-логика расчётов, а не транспорт.
Транспорт (HTTP) — в `diagnostic_engine.api`.

Принцип: каждая НТД — отдельный модуль. Общий контракт на вход/выход —
pydantic-модели из `schemas`.
"""
from .rd_09_539 import residual_life_by_thickness, ResidualLifeInput, ResidualLifeResult
from .sa_03_008 import epb_vessel_conclusion, EPBVesselInput, EPBVesselResult
from .norms_map import resolve_methods_for_object, NORMS_MAP

__all__ = [
    "residual_life_by_thickness",
    "ResidualLifeInput",
    "ResidualLifeResult",
    "epb_vessel_conclusion",
    "EPBVesselInput",
    "EPBVesselResult",
    "resolve_methods_for_object",
    "NORMS_MAP",
]
