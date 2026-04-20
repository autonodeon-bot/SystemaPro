"""СА 03-008-08 «Сосуды и аппараты, работающие под давлением. Нормы и методы
расчёта на прочность. Экспертиза промышленной безопасности».

Упрощённый конструктор заключения ЭПБ: агрегирует результаты отдельных
методов НК (ВИК, УЗТ, УЗК, МПД, ЦД) и выдаёт общий вердикт:
  - CLEAR           — ОК, продлить срок
  - CONDITIONAL     — продление с условиями (доп.контроль, снижение параметров)
  - REJECT          — отказ в продлении

Это НЕ автогенерация официального заключения (оно подписывается экспертом),
а доменный помощник, снимающий рутину.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Optional

from pydantic import BaseModel, Field

from .rd_09_539 import ResidualLifeResult

MethodCode = Literal[
    "VIC",  # визуально-измерительный контроль
    "UT",   # ультразвуковая толщинометрия
    "UZK",  # ультразвуковой контроль сварных швов
    "MPD",  # магнитопорошковый
    "PT",   # капиллярный (цветная дефектоскопия)
    "HT",   # гидравлические испытания
]


class MethodFinding(BaseModel):
    method: MethodCode
    passed: bool
    defects_count: int = 0
    critical_defects_count: int = 0
    notes: Optional[str] = None


class EPBVesselInput(BaseModel):
    vessel_type: str = Field(..., description="Тип сосуда (например, 'Сепаратор нефтегазовый')")
    working_pressure_mpa: float = Field(..., gt=0)
    design_pressure_mpa: float = Field(..., gt=0)
    working_temperature_c: float
    findings: list[MethodFinding]
    residual_life: ResidualLifeResult
    prior_examinations_count: int = Field(
        0, ge=0, description="Число предыдущих ЭПБ, включая первичную"
    )


@dataclass(frozen=True)
class EPBVesselResult:
    verdict: str  # CLEAR | CONDITIONAL | REJECT
    recommended_extension_years: float
    conditions: list[str]
    rationale: list[str]
    methodology: str = "СА 03-008-08"


def epb_vessel_conclusion(inp: EPBVesselInput) -> EPBVesselResult:
    rationale: list[str] = []
    conditions: list[str] = []

    # 1) Критические дефекты — безусловный отказ
    critical_total = sum(f.critical_defects_count for f in inp.findings)
    if critical_total > 0:
        rationale.append(
            f"Обнаружено {critical_total} критических дефектов по данным НК."
        )
        return EPBVesselResult(
            verdict="REJECT",
            recommended_extension_years=0.0,
            conditions=[],
            rationale=rationale,
        )

    # 2) Остаточный ресурс
    rl = inp.residual_life
    rationale.append(
        f"Остаточный ресурс по РД 09-539: {rl.residual_years} лет (статус {rl.status})."
    )
    if rl.status == "REJECTED":
        return EPBVesselResult(
            verdict="REJECT",
            recommended_extension_years=0.0,
            conditions=[],
            rationale=rationale,
        )

    # 3) Провал одного из НК
    failed_methods = [f.method for f in inp.findings if not f.passed]
    if failed_methods:
        rationale.append(f"Не пройден контроль: {', '.join(failed_methods)}.")
        conditions.append(
            "Устранить выявленные дефекты и провести повторный НК до ввода в эксплуатацию."
        )
        # Если RL < 4 лет И есть провалы — отказ
        if rl.residual_years < 4:
            return EPBVesselResult(
                verdict="REJECT",
                recommended_extension_years=0.0,
                conditions=conditions,
                rationale=rationale,
            )

    # 4) Высокое давление → снижение параметров при повторных ЭПБ
    if inp.prior_examinations_count >= 2 and inp.working_pressure_mpa > 0.9 * inp.design_pressure_mpa:
        conditions.append(
            "Снизить рабочее давление до 0.9 * P_расч на период следующего межконтрольного интервала."
        )

    # 5) Итоговая рекомендация по сроку продления
    if rl.status == "OK" and not failed_methods:
        extension = min(rl.residual_years, 8.0)
        verdict = "CLEAR" if not conditions else "CONDITIONAL"
    elif rl.status == "WARNING" or failed_methods:
        extension = min(rl.residual_years, 4.0)
        verdict = "CONDITIONAL"
        conditions.append(
            "Организовать промежуточный контроль (УЗТ + ВИК) не реже 1 раза в год."
        )
    else:
        extension = 0.0
        verdict = "REJECT"

    rationale.append(
        f"Рекомендуемый срок продления: {extension:g} лет; вердикт {verdict}."
    )
    return EPBVesselResult(
        verdict=verdict,
        recommended_extension_years=round(extension, 1),
        conditions=conditions,
        rationale=rationale,
    )
