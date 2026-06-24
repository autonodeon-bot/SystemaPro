"""
Шаблоны заключений по результатам обследования (пригоден / не пригоден / ограниченно пригоден).
"""
from __future__ import annotations

from typing import Any, Callable, Dict, Optional

SUITABILITY_FIT = "FIT"
SUITABILITY_UNFIT = "UNFIT"
SUITABILITY_LIMITED = "LIMITED_FIT"

SUITABILITY_LABELS = {
    SUITABILITY_FIT: "Пригоден",
    SUITABILITY_UNFIT: "Не пригоден",
    SUITABILITY_LIMITED: "Ограниченно пригоден",
}


def resolve_suitability_status(data: Dict[str, Any]) -> Optional[str]:
    if not isinstance(data, dict):
        return None
    add = data.get("additional_data")
    if isinstance(add, dict):
        st = add.get("suitability_status") or add.get("fitness_status")
        if isinstance(st, str) and st.strip():
            return st.strip().upper()
    st = data.get("suitability_status") or data.get("fitness_status")
    if isinstance(st, str) and st.strip():
        return st.strip().upper()
    return None


def build_suitability_conclusion(
    status: str,
    *,
    device_name: str,
    serial: str = "",
    reg_no: str = "",
    inv_no: str = "",
    residual_years: str = "10",
    restrictions: str = "",
) -> str:
    """Стандартный текст заключения по выбранной оценке пригодности."""
    name = device_name or "оборудование"
    ident = f"{name}"
    if serial:
        ident += f" зав. № {serial}"
    if reg_no:
        ident += f", рег. № {reg_no}"
    if inv_no:
        ident += f", инв. № {inv_no}"

    st = (status or "").upper()
    if st in (SUITABILITY_UNFIT, "NOT_FIT", "UNFIT"):
        return (
            f"На основании результатов выполненного комплекса работ по техническому диагностированию "
            f"{ident} техническое состояние оценивается как неудовлетворительное. "
            f"Дальнейшая эксплуатация оборудования не допускается до устранения выявленных недостатков "
            f"и проведения повторного обследования."
        )
    if st in (SUITABILITY_LIMITED, "LIMITED", "LIMITED_FIT"):
        restr = (restrictions or "").strip()
        restr_text = (
            f" Эксплуатация допускается при соблюдении ограничений: {restr}."
            if restr
            else " Эксплуатация допускается при соблюдении установленных ограничений."
        )
        return (
            f"На основании результатов выполненного комплекса работ по техническому диагностированию "
            f"{ident} техническое состояние оценивается как ограниченно пригодное.{restr_text} "
            f"Рекомендуемый срок безопасной эксплуатации до проведения следующего обследования — "
            f"не более {residual_years} лет при соблюдении режимов эксплуатации."
        )
    return (
        f"На основании результатов выполненного комплекса работ по техническому диагностированию "
        f"{ident}, работающего под давлением, техническое состояние оценивается как работоспособное. "
        f"Оборудование пригодно к дальнейшей эксплуатации при соблюдении проектных параметров. "
        f"Рекомендуемый срок безопасной эксплуатации до проведения следующего обследования — "
        f"не более {residual_years} лет."
    )


def conclusion_from_inspection_data(
    inspection_data: Dict[str, Any],
    equipment_data: Dict[str, Any],
    g: Callable[..., Any],
    explicit_conclusion: Optional[str] = None,
) -> str:
    """Вернуть заключение: явное из обследования или по suitability_status."""
    if explicit_conclusion and str(explicit_conclusion).strip():
        return str(explicit_conclusion).strip()
    data = inspection_data.get("data") if isinstance(inspection_data.get("data"), dict) else {}
    attrs = equipment_data.get("attributes") or {}
    status = resolve_suitability_status(data if isinstance(data, dict) else {})
    if status:
        add = data.get("additional_data") if isinstance(data.get("additional_data"), dict) else {}
        return build_suitability_conclusion(
            status,
            device_name=str(g("vessel_name", "device_name", default=equipment_data.get("name") or "сосуд")),
            serial=str(g("serial_number", default=equipment_data.get("serial_number") or "")),
            reg_no=str(g("reg_number", "registration_number", default=attrs.get("registration_number") or "")),
            inv_no=str(g("inventory_number", default=attrs.get("inventory_number") or "")),
            residual_years=str(g("residual_life_years", default="10")),
            restrictions=str(add.get("suitability_restrictions") or g("suitability_restrictions", default="")),
        )
    custom = g("conclusion", "final_conclusion", default="")
    if custom and str(custom).strip():
        return str(custom).strip()
    return build_suitability_conclusion(SUITABILITY_FIT, device_name=str(equipment_data.get("name") or "сосуд"))
