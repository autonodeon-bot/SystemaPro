#!/usr/bin/env python3
"""Dump section 15 paragraphs from filled and raw template."""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

from docx import Document
from docx.oxml.ns import qn

sys.path.insert(0, "/app")
from form_template_filler import (
    fill_vessel_form_to1,
    _build_context,
    _fill_main_report,
    _fill_paragraph_blanks,
    _iter_all_paragraphs,
    _norm_ws,
    MISSING,
)
from report_forms_registry import resolve_form_path
from docx import Document as Doc


def dump_matches(doc, label):
    print("===", label, "===")
    n = 0
    for p in _iter_all_paragraphs(doc):
        t = p.text or ""
        if not t.strip():
            continue
        low = t.lower()
        if (
            "фактическое" in low
            or "техническое состояние объекта" in low
            or ("зав" in low and "инв" in low and "____" in t)
        ):
            n += 1
            print(f"[{n}] repr={t[:200]!r}")
            print(f"    norm={_norm_ws(t)[:200]!r}")
            print(f"    runs={len(p.runs)}")
    print("total matches", n)


def main():
    path = resolve_form_path("to-1")
    print("template", path)
    raw = Doc(str(path))
    dump_matches(raw, "RAW TEMPLATE")

    data = {
        "report_form_id": "to-1",
        "vessel_name": "Аппарат тестовый А-1",
        "serial_number": "SN-100",
        "reg_number": "Р-55",
        "inventory_number": "ИНВ-9",
        "orientation": "vertical",
        "shell_count": 2,
        "geometry": {"kind": "vessel", "orientation": "vertical", "shell_count": 2},
    }
    inspection = {"data": data, "date_performed": "2026-08-28"}
    equipment = {
        "name": "Аппарат тестовый А-1",
        "serial_number": "SN-100",
        "attributes": {"registration_number": "Р-55", "inventory_number": "ИНВ-9"},
    }
    ctx = _build_context(inspection, equipment, [], {}, [], {})
    print("CTX", ctx["device_name"], ctx["serial"], ctx["reg_no"], ctx["inv_no"])

    # Only main report fill on a fresh copy
    out1 = Path(tempfile.gettempdir()) / "_dbg_main_only.docx"
    import shutil
    shutil.copy(path, out1)
    d1 = Doc(str(out1))
    _fill_main_report(d1, ctx)
    dump_matches(d1, "AFTER _fill_main_report")
    d1.save(str(out1))

    out2 = Path(tempfile.gettempdir()) / "_dbg_blanks.docx"
    shutil.copy(out1, out2)
    d2 = Doc(str(out2))
    _fill_paragraph_blanks(d2, ctx)
    dump_matches(d2, "AFTER _fill_paragraph_blanks")

    # Full fill
    out = Path(tempfile.gettempdir()) / "_dbg_full.docx"
    fill_vessel_form_to1(
        inspection_data=inspection,
        equipment_data=equipment,
        output_path=str(out),
        verification_equipment=[],
        org_settings={},
        specialist_docs=[],
        document_files=[],
        ndt_methods=[],
    )
    dump_matches(Doc(str(out)), "AFTER FULL FILL")


if __name__ == "__main__":
    main()
