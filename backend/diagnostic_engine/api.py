"""HTTP-роутер диагностического движка: расчёты по НТД."""
from fastapi import APIRouter, Depends, HTTPException

from auth import verify_token

from .norms_map import NORMS_MAP, applicable_methods, resolve_methods_for_object
from .rd_09_539 import ResidualLifeInput, residual_life_by_thickness
from .sa_03_008 import EPBVesselInput, epb_vessel_conclusion

router = APIRouter(prefix="/api/diagnostic", tags=["diagnostic"])


@router.get("/norms")
async def get_norms_map(_: str = Depends(verify_token)):
    """Вся карта object_type × method → нормы."""
    return {"norms": NORMS_MAP}


@router.get("/norms/{object_type}")
async def get_norms_for_object(object_type: str, _: str = Depends(verify_token)):
    methods = resolve_methods_for_object(object_type)
    if not methods:
        raise HTTPException(status_code=404, detail=f"Неизвестный тип объекта: {object_type}")
    return {
        "object_type": object_type,
        "methods": methods,
        "applicable_method_codes": applicable_methods(object_type),
    }


@router.post("/residual-life")
async def calc_residual_life(payload: ResidualLifeInput, _: str = Depends(verify_token)):
    """Расчёт остаточного ресурса по РД 09-539-03."""
    result = residual_life_by_thickness(payload)
    return {
        "methodology": result.methodology,
        "residual_years": result.residual_years,
        "status": result.status,
        "details": result.details,
    }


@router.post("/epb-vessel")
async def calc_epb_vessel(payload: EPBVesselInput, _: str = Depends(verify_token)):
    """Помощник ЭПБ сосуда под давлением (СА 03-008-08).

    Возвращает вердикт, срок продления и условия. Является рекомендательным:
    официальное заключение готовит и подписывает эксперт.
    """
    result = epb_vessel_conclusion(payload)
    return {
        "methodology": result.methodology,
        "verdict": result.verdict,
        "recommended_extension_years": result.recommended_extension_years,
        "conditions": result.conditions,
        "rationale": result.rationale,
    }
