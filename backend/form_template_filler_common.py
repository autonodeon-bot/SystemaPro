"""
Общие хелперы заполнения форм ТО (to-3, to-13, to-33, …).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from docx.table import Table

from form_template_filler import (
    MISSING,
    _ensure_rows,
    _extract_specialists,
    _fmt_date_ru,
    _instrument_full_name,
    _merge_report_instruments,
    _renumber_table_column,
    _set,
    _strip_empty_rows,
)


def fill_customer_table(table: Table, org_settings: Dict[str, Any], location: str = "") -> None:
    customer = org_settings.get("customer") or {}
    rows = [
        customer.get("legal_name") or customer.get("name") or MISSING,
        customer.get("director") or customer.get("director_name") or MISSING,
        customer.get("address") or customer.get("legal_address") or MISSING,
        location or customer.get("location") or MISSING,
        customer.get("phone") or MISSING,
        customer.get("email") or MISSING,
    ]
    for i, val in enumerate(rows):
        if i < len(table.rows) and len(table.rows[i].cells) > 1:
            _set(table, i, 1, val)


def fill_contractor_table(table: Table, org_settings: Dict[str, Any]) -> None:
    contractor = org_settings.get("contractor") or {}
    lab = org_settings.get("ndt_lab") or {}
    rows = [
        contractor.get("legal_name") or contractor.get("name") or MISSING,
        contractor.get("director_name") or contractor.get("director") or MISSING,
        contractor.get("address") or contractor.get("postal_address") or MISSING,
        contractor.get("location") or MISSING,
        contractor.get("phone") or MISSING,
        contractor.get("email") or MISSING,
        lab.get("certificate") or lab.get("name") or MISSING,
    ]
    for i, val in enumerate(rows):
        if i < len(table.rows) and len(table.rows[i].cells) > 1:
            _set(table, i, 1, val)


def fill_specialists_table(
    table: Table,
    data: Dict[str, Any],
    specialist_docs: Optional[List[Dict[str, Any]]] = None,
    start_row: int = 1,
) -> None:
    specs = _extract_specialists(data, specialist_docs or [])
    _ensure_rows(table, start_row + max(len(specs), 1))
    for r in range(start_row, len(table.rows)):
        for c in range(len(table.rows[r].cells)):
            _set(table, r, c, "")
    for i, s in enumerate(specs):
        r = start_row + i
        if r >= len(table.rows):
            _ensure_rows(table, r + 1)
        cols = len(table.rows[r].cells)
        _set(table, r, 0, f"{i + 1}.")
        if cols > 1:
            _set(table, r, 1, s.get("name") or "")
        if cols > 2:
            _set(table, r, 2, s.get("cert") or MISSING, nowrap=True)
        if cols > 3:
            _set(table, r, 3, s.get("role") or s.get("area") or MISSING)
        if cols > 4:
            _set(
                table,
                r,
                4,
                _fmt_date_ru(s.get("valid_until") or s.get("expiry"))
                or (s.get("valid_until") or s.get("expiry"))
                or MISSING,
            )
    _strip_empty_rows(table, start_row, ignore_cols=(0,))
    _renumber_table_column(table, start_row, 0)


def fill_instruments_table(
    table: Table,
    verification_equipment: Optional[List[Dict[str, Any]]],
    data: Dict[str, Any],
    ndt_methods: Optional[List[Dict[str, Any]]] = None,
    start_row: int = 1,
) -> None:
    ve = _merge_report_instruments(verification_equipment, data, ndt_methods)
    _ensure_rows(table, start_row + max(len(ve), 1))
    for r in range(start_row, len(table.rows)):
        for c in range(len(table.rows[r].cells)):
            _set(table, r, c, "")
    for i, eq in enumerate(ve):
        r = start_row + i
        if r >= len(table.rows):
            _ensure_rows(table, r + 1)
        cols = len(table.rows[r].cells)
        _set(table, r, 0, f"{i + 1}.")
        if cols > 1:
            _set(table, r, 1, _instrument_full_name(eq))
        if cols > 2:
            _set(
                table,
                r,
                2,
                eq.get("serial_number") or eq.get("factory_number") or MISSING,
                nowrap=True,
            )
        if cols > 3:
            _set(
                table,
                r,
                3,
                eq.get("verification_certificate_number")
                or eq.get("certificate")
                or MISSING,
                nowrap=True,
            )
        if cols > 4:
            _set(
                table,
                r,
                4,
                _fmt_date_ru(
                    eq.get("next_verification_date")
                    or eq.get("valid_until")
                    or eq.get("verification_until")
                )
                or eq.get("next_verification_date")
                or MISSING,
                nowrap=True,
            )
    _strip_empty_rows(table, start_row, ignore_cols=(0,))
    _renumber_table_column(table, start_row, 0)


def fill_kv_table(table: Table, pairs: List[tuple], value_col: int = 1) -> None:
    """Заполнить пары (метка уже в col0) → значение в value_col."""
    for i, val in enumerate(pairs):
        if i >= len(table.rows):
            break
        if len(table.rows[i].cells) > value_col:
            _set(table, i, value_col, val if val not in (None, "") else MISSING)


def g_data(
    data: Dict[str, Any],
    attrs: Dict[str, Any],
    *keys: str,
    default: Any = MISSING,
) -> Any:
    ad = data.get("additional_data") if isinstance(data.get("additional_data"), dict) else {}
    for k in keys:
        if k in data and data.get(k) not in (None, ""):
            return data.get(k)
        if k in ad and ad.get(k) not in (None, ""):
            return ad.get(k)
        if k in attrs and attrs.get(k) not in (None, ""):
            return attrs.get(k)
    return default
