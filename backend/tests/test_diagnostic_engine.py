"""Тесты доменного движка диагностики: РД 09-539, СА 03-008, norms_map."""
from __future__ import annotations

import pytest

from diagnostic_engine import (
    EPBVesselInput,
    ResidualLifeInput,
    epb_vessel_conclusion,
    residual_life_by_thickness,
    resolve_methods_for_object,
)
from diagnostic_engine.sa_03_008 import MethodFinding


# ─── РД 09-539: остаточный ресурс ─────────────────────────────────────────────
def test_residual_life_ok_with_measured_corrosion():
    """Нормальный случай: измеренная скорость коррозии, большой запас."""
    inp = ResidualLifeInput(
        t_factual=8.0,
        t_nominal=10.0,
        t_allow=5.0,
        corrosion_rate_mm_year=0.1,
        safety_factor=1.0,
    )
    result = residual_life_by_thickness(inp)
    assert result.residual_years == pytest.approx(30.0, rel=0.01)
    assert result.status == "OK"
    assert result.details["corrosion_rate_source"] == "measured"


def test_residual_life_rejected_when_t_factual_below_allow():
    """Если фактическая толщина ≤ отбраковочной — запрет эксплуатации."""
    inp = ResidualLifeInput(
        t_factual=4.0,
        t_nominal=10.0,
        t_allow=5.0,
        corrosion_rate_mm_year=0.1,
    )
    result = residual_life_by_thickness(inp)
    assert result.residual_years == 0.0
    assert result.status == "REJECTED"


def test_residual_life_estimates_corrosion_from_service_years():
    """Если скорость не задана, берём из срока эксплуатации."""
    inp = ResidualLifeInput(
        t_factual=8.0,
        t_nominal=10.0,
        t_allow=5.0,
        service_years=20.0,
    )
    result = residual_life_by_thickness(inp)
    # V_corr = (10-8)/20 = 0.1 → T = (8-5)/0.1 = 30
    assert result.residual_years == pytest.approx(30.0, rel=0.01)
    assert result.details["corrosion_rate_source"] == "estimated_from_service_years"


def test_residual_life_warning_status_when_2_to_8_years():
    inp = ResidualLifeInput(
        t_factual=5.3, t_nominal=10.0, t_allow=5.0, corrosion_rate_mm_year=0.1
    )
    result = residual_life_by_thickness(inp)
    # T = 0.3/0.1 = 3 лет → WARNING
    assert result.status == "WARNING"
    assert 2 <= result.residual_years < 8


def test_safety_factor_from_opo_hazard_class():
    """Класс I ОПО → K_з = 1.5, что снижает остаточный ресурс."""
    inp = ResidualLifeInput(
        t_factual=8.0,
        t_nominal=10.0,
        t_allow=5.0,
        corrosion_rate_mm_year=0.1,
        opo_hazard_class="I",
    )
    result = residual_life_by_thickness(inp)
    # T = 3/(1.5*0.1) = 20
    assert result.residual_years == pytest.approx(20.0, rel=0.01)
    assert result.details["safety_factor_used"] == 1.5


def test_residual_life_requires_corrosion_or_service_years():
    with pytest.raises(ValueError):
        ResidualLifeInput(t_factual=8.0, t_nominal=10.0)


def test_default_t_allow_is_half_of_nominal():
    inp = ResidualLifeInput(t_factual=8.0, t_nominal=10.0, corrosion_rate_mm_year=0.1)
    result = residual_life_by_thickness(inp)
    # t_allow = 5.0 → T = 30
    assert result.details["t_allow_mm"] == 5.0


# ─── СА 03-008: ЭПБ сосуда ────────────────────────────────────────────────────
def _rl_ok() -> "ResidualLifeInput":
    return residual_life_by_thickness(
        ResidualLifeInput(
            t_factual=8.0, t_nominal=10.0, t_allow=5.0, corrosion_rate_mm_year=0.1
        )
    )


def _rl_warning():
    return residual_life_by_thickness(
        ResidualLifeInput(
            t_factual=5.3, t_nominal=10.0, t_allow=5.0, corrosion_rate_mm_year=0.1
        )
    )


def _rl_rejected():
    return residual_life_by_thickness(
        ResidualLifeInput(
            t_factual=4.0, t_nominal=10.0, t_allow=5.0, corrosion_rate_mm_year=0.1
        )
    )


def test_epb_vessel_clear_when_all_ndt_passed_and_rl_ok():
    inp = EPBVesselInput(
        vessel_type="Сепаратор НГС",
        working_pressure_mpa=1.0,
        design_pressure_mpa=1.6,
        working_temperature_c=40,
        findings=[
            MethodFinding(method="VIC", passed=True),
            MethodFinding(method="UT", passed=True),
        ],
        residual_life=_rl_ok(),
        prior_examinations_count=1,
    )
    result = epb_vessel_conclusion(inp)
    assert result.verdict == "CLEAR"
    assert result.recommended_extension_years > 0
    assert not result.conditions


def test_epb_vessel_reject_on_critical_defects():
    inp = EPBVesselInput(
        vessel_type="Ресивер",
        working_pressure_mpa=1.0,
        design_pressure_mpa=1.6,
        working_temperature_c=40,
        findings=[
            MethodFinding(method="UZK", passed=False, critical_defects_count=2),
        ],
        residual_life=_rl_ok(),
    )
    result = epb_vessel_conclusion(inp)
    assert result.verdict == "REJECT"
    assert result.recommended_extension_years == 0.0


def test_epb_vessel_conditional_when_warning_rl():
    inp = EPBVesselInput(
        vessel_type="Сепаратор",
        working_pressure_mpa=1.0,
        design_pressure_mpa=1.6,
        working_temperature_c=40,
        findings=[MethodFinding(method="VIC", passed=True)],
        residual_life=_rl_warning(),
    )
    result = epb_vessel_conclusion(inp)
    assert result.verdict == "CONDITIONAL"
    assert 0 < result.recommended_extension_years <= 4
    assert any("контроль" in c.lower() for c in result.conditions)


def test_epb_vessel_reject_when_rl_rejected():
    inp = EPBVesselInput(
        vessel_type="Сепаратор",
        working_pressure_mpa=1.0,
        design_pressure_mpa=1.6,
        working_temperature_c=40,
        findings=[MethodFinding(method="VIC", passed=True)],
        residual_life=_rl_rejected(),
    )
    result = epb_vessel_conclusion(inp)
    assert result.verdict == "REJECT"


def test_epb_vessel_pressure_reduction_condition():
    """При повторных ЭПБ и давлении близко к расчётному — рекомендуется снижение."""
    inp = EPBVesselInput(
        vessel_type="Сепаратор",
        working_pressure_mpa=1.5,
        design_pressure_mpa=1.6,
        working_temperature_c=40,
        findings=[MethodFinding(method="VIC", passed=True)],
        residual_life=_rl_ok(),
        prior_examinations_count=3,
    )
    result = epb_vessel_conclusion(inp)
    assert any("снизить" in c.lower() for c in result.conditions)


# ─── Norms map ────────────────────────────────────────────────────────────────
def test_norms_map_pressure_vessel_contains_expected_entries():
    methods = resolve_methods_for_object("pressure_vessel")
    assert "UT" in methods
    assert "VIC" in methods
    assert "methodology" in methods
    assert any("РД 09-539" in n for n in methods["methodology"])


def test_norms_map_unknown_object_returns_empty():
    assert resolve_methods_for_object("unknown_type") == {}
