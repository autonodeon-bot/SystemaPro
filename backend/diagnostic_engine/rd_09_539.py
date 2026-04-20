"""РД 09-539-03 «Инструкция о порядке продления срока безопасной эксплуатации
технических устройств, оборудования и сооружений на опасных производственных
объектах».

Упрощённая (но корректная с точки зрения методики) реализация расчёта
остаточного ресурса по данным толщинометрии:

    t_factual   — фактическая минимальная толщина стенки (мм)
    t_design    — расчётная (проектная) толщина стенки (мм)
    t_nominal   — номинальная (исходная) толщина (мм)
    t_allow     — отбраковочная толщина (мм); если не задана, берём t_design
    corrosion   — скорость коррозии (мм/год); если не задана, оценивается как
                  (t_nominal - t_factual) / срок эксплуатации

Формула остаточного ресурса:

    T_ост = (t_factual - t_allow) / (K_з * V_корр)

где K_з — коэффициент запаса (по умолчанию 1.0; в методиках РД 09 используется
1.0..1.5 в зависимости от класса ОПО).

Если t_factual ≤ t_allow — остаточный ресурс 0 лет, статус = REJECTED.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from pydantic import BaseModel, Field, model_validator


class ResidualLifeInput(BaseModel):
    t_factual: float = Field(..., gt=0, description="Фактическая минимальная толщина, мм")
    t_nominal: float = Field(..., gt=0, description="Номинальная (проектная) толщина, мм")
    t_allow: Optional[float] = Field(
        None, gt=0, description="Отбраковочная толщина, мм; по умолчанию = 0.5 * t_nominal"
    )
    service_years: Optional[float] = Field(
        None, gt=0, description="Срок эксплуатации на момент диагностики (лет)"
    )
    corrosion_rate_mm_year: Optional[float] = Field(
        None, gt=0, description="Измеренная скорость коррозии, мм/год"
    )
    safety_factor: float = Field(
        1.0,
        ge=1.0,
        le=2.0,
        description="Коэффициент запаса K_з (РД 09-539)",
    )
    opo_hazard_class: Optional[str] = Field(
        None,
        description="Класс опасности ОПО (I..IV). Влияет на рекомендуемый K_з.",
    )

    @model_validator(mode="after")
    def _check(self) -> "ResidualLifeInput":
        if self.t_factual > self.t_nominal:
            # допустим (например, при замене), но корр.скорость расчёту не подлежит.
            pass
        if not self.corrosion_rate_mm_year and not self.service_years:
            raise ValueError(
                "Укажите либо corrosion_rate_mm_year, либо service_years для оценки"
            )
        return self


@dataclass(frozen=True)
class ResidualLifeResult:
    residual_years: float
    status: str  # OK | WARNING | REJECTED
    details: dict
    methodology: str = "РД 09-539-03"


# Рекомендуемые K_з по классу ОПО (РД 09, приложение; упрощение).
_SAFETY_FACTOR_BY_CLASS = {
    "I": 1.5,
    "II": 1.3,
    "III": 1.1,
    "IV": 1.0,
}


def _effective_safety_factor(inp: ResidualLifeInput) -> float:
    if inp.safety_factor and inp.safety_factor > 1.0:
        return inp.safety_factor
    if inp.opo_hazard_class:
        key = inp.opo_hazard_class.strip().upper()
        if key in _SAFETY_FACTOR_BY_CLASS:
            return _SAFETY_FACTOR_BY_CLASS[key]
    return 1.0


def residual_life_by_thickness(inp: ResidualLifeInput) -> ResidualLifeResult:
    """Расчёт остаточного ресурса по толщинометрии (РД 09-539-03)."""
    t_allow = inp.t_allow if inp.t_allow else inp.t_nominal * 0.5

    if inp.t_factual <= t_allow:
        return ResidualLifeResult(
            residual_years=0.0,
            status="REJECTED",
            details={
                "reason": "Фактическая толщина ≤ отбраковочной — эксплуатация запрещена",
                "t_factual_mm": round(inp.t_factual, 3),
                "t_allow_mm": round(t_allow, 3),
            },
        )

    # Скорость коррозии: измеренная или оценённая
    if inp.corrosion_rate_mm_year:
        v_corr = inp.corrosion_rate_mm_year
        v_source = "measured"
    else:
        loss = max(inp.t_nominal - inp.t_factual, 0.001)
        v_corr = loss / inp.service_years  # type: ignore[operator]
        v_source = "estimated_from_service_years"

    k_z = _effective_safety_factor(inp)
    residual = (inp.t_factual - t_allow) / (k_z * v_corr)
    residual = max(residual, 0.0)

    if residual >= 8:
        status = "OK"
    elif residual >= 2:
        status = "WARNING"
    else:
        status = "REJECTED"

    return ResidualLifeResult(
        residual_years=round(residual, 2),
        status=status,
        details={
            "t_factual_mm": round(inp.t_factual, 3),
            "t_nominal_mm": round(inp.t_nominal, 3),
            "t_allow_mm": round(t_allow, 3),
            "corrosion_rate_mm_year": round(v_corr, 4),
            "corrosion_rate_source": v_source,
            "safety_factor_used": k_z,
            "formula": "T = (t_fact - t_allow) / (K_з * V_корр)",
        },
    )
