"""
Общие заполнители протоколов НК для форм to-3 / to-33.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from docx.table import Table

from form_template_filler import (
    MISSING,
    _ensure_rows,
    _fmt_date_ru,
    _set,
    _strip_empty_rows,
)


def _as_list(data: Dict[str, Any], *keys: str) -> List[Dict[str, Any]]:
    for k in keys:
        raw = data.get(k)
        if isinstance(raw, list):
            return [x for x in raw if isinstance(x, dict)]
        ad = data.get("additional_data")
        if isinstance(ad, dict):
            raw2 = ad.get(k)
            if isinstance(raw2, list):
                return [x for x in raw2 if isinstance(x, dict)]
    return []


def _ad(data: Dict[str, Any]) -> Dict[str, Any]:
    v = data.get("additional_data")
    return v if isinstance(v, dict) else {}


def fill_protocol_header_ids(
    table: Table,
    *,
    contractor: str,
    customer: str,
    device: str,
    serial: str,
    reg_no: str,
    inv_no: str,
    location: str,
) -> None:
    """Типовая шапка 8×3 протоколов приложений."""
    if len(table.rows) < 4 or len(table.columns) < 3:
        return
    try:
        _set(table, 0, 0, contractor or MISSING)
        _set(table, 0, 2, customer or MISSING)
        _set(table, 2, 0, location or MISSING)
        ids = f"зав.№ {serial}, рег.№ {reg_no}, инв.№ {inv_no}"
        # часто строка с объектом
        for r in range(min(6, len(table.rows))):
            for c in range(len(table.rows[r].cells)):
                txt = (table.rows[r].cells[c].text or "").lower()
                if "наименован" in txt or "объект" in txt:
                    if c + 1 < len(table.rows[r].cells):
                        _set(table, r, c + 1, device)
                if "зав" in txt or "инв" in txt:
                    if c + 1 < len(table.rows[r].cells):
                        _set(table, r, c + 1, ids)
    except Exception:
        pass


def fill_documents_by_name(
    table: Table,
    data: Dict[str, Any],
    start_row: int = 1,
    num_col: int = 2,
    pages_col: int = 3,
) -> None:
    docs = data.get("documents") if isinstance(data.get("documents"), dict) else {}
    info = data.get("documents_info") if isinstance(data.get("documents_info"), dict) else {}
    # По имени строки
    for r in range(start_row, len(table.rows)):
        name = (table.rows[r].cells[1].text if len(table.rows[r].cells) > 1 else "") or ""
        name_l = name.lower()
        # ищем meta по номеру в col0 или по порядку
        key = (table.rows[r].cells[0].text or "").strip().rstrip(".")
        meta = info.get(key) if key else None
        if not isinstance(meta, dict):
            # fallback: documents_info keys "1".."N" by row order
            meta = info.get(str(r)) if isinstance(info.get(str(r)), dict) else None
        present = docs.get(key)
        if isinstance(meta, dict):
            if num_col < len(table.rows[r].cells) and meta.get("number"):
                _set(table, r, num_col, meta.get("number"))
            pc = pages_col if pages_col < len(table.rows[r].cells) else num_col + 1
            if pc < len(table.rows[r].cells) and (meta.get("pages") or meta.get("date")):
                _set(table, r, pc, meta.get("pages") or _fmt_date_ru(meta.get("date")) or meta.get("date"))
        elif present is False and num_col < len(table.rows[r].cells):
            if not (table.rows[r].cells[num_col].text or "").strip():
                _set(table, r, num_col, "Не предоставлено")
        # эвристика по названию документа в checklist.documents flags
        if present is None and name_l:
            for dk, dv in docs.items():
                if str(dk) in name_l:
                    present = dv
                    break


def fill_vik_element_table(table: Table, data: Dict[str, Any], start_row: int = 1) -> None:
    defects = _as_list(data, "visual_defects", "defects")
    # элементы без номера шва
    rows = [
        d
        for d in defects
        if not (d.get("weld_number") or d.get("joint_number"))
        or (d.get("zone") not in (None, "", "weld"))
    ]
    if not rows:
        rows = [d for d in defects if d.get("location") and not str(d.get("location")).startswith("С")]
    _ensure_rows(table, start_row + max(len(rows), 1))
    for i, d in enumerate(rows):
        r = start_row + i
        if r >= len(table.rows):
            break
        cols = len(table.rows[r].cells)
        vals = [
            d.get("weld_ref") or d.get("binding") or d.get("location") or "",
            d.get("element") or d.get("location") or "",
            d.get("diameter") or d.get("dn") or d.get("outer_diameter") or "",
            d.get("description")
            or d.get("defect_type")
            or ("дефектов не выявлено" if not d.get("size") else f"{d.get('defect_type') or ''} {d.get('size') or ''}".strip()),
            d.get("dist_ring") or d.get("distance_ring_weld") or "",
            d.get("dist_long") or d.get("distance_long_weld") or "",
            d.get("clock") or d.get("orientation") or d.get("clock_position") or "",
            d.get("length") or d.get("length_mm") or d.get("extent") or "",
            d.get("width") or d.get("width_mm") or "",
            d.get("depth") or d.get("depth_mm") or d.get("size") or "",
            d.get("assessment") or d.get("conclusion") or "Годен",
        ]
        for c, v in enumerate(vals):
            if c < cols:
                _set(table, r, c, v)
    _strip_empty_rows(table, start_row, ignore_cols=None)


def fill_vik_weld_table(table: Table, data: Dict[str, Any], start_row: int = 1) -> None:
    defects = _as_list(data, "visual_defects", "defects")
    welds = _as_list(data, "weld_inspections", "weldInspections")
    rows: List[Dict[str, Any]] = []
    for d in defects:
        if d.get("weld_number") or d.get("joint_number") or (d.get("zone") == "weld"):
            rows.append(d)
    if not rows:
        for w in welds:
            if (w.get("control_method") or "").upper() in ("", "VIK", "ВИК"):
                rows.append(
                    {
                        "weld_number": w.get("weld_number"),
                        "description": w.get("defect_description") or "дефектов не выявлено",
                        "clock": "",
                        "length": w.get("length"),
                        "depth": w.get("depth"),
                        "assessment": w.get("conclusion") or "Годен",
                        "diameter": w.get("diameter") or w.get("dn"),
                    }
                )
    _ensure_rows(table, start_row + max(len(rows), 1))
    for i, d in enumerate(rows):
        r = start_row + i
        if r >= len(table.rows):
            break
        vals = [
            d.get("weld_number") or d.get("joint_number") or "",
            d.get("diameter") or d.get("dn") or "",
            d.get("description") or d.get("defect_type") or "дефектов не выявлено",
            d.get("clock") or d.get("orientation") or "",
            d.get("length") or d.get("length_mm") or "",
            d.get("width") or d.get("width_mm") or "",
            d.get("depth") or d.get("depth_mm") or d.get("size") or "",
            d.get("assessment") or d.get("conclusion") or "Годен",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v)


def fill_uzt_wide_table(table: Table, data: Dict[str, Any], data_start_row: int = 2) -> None:
    """T26 to-33: row0 merged header, row1 A1..E4, data from row2."""
    points = _as_list(data, "thickness_measurements", "thicknessMeasurements")
    schemes = data.get("uzt_schemes") or data.get("uztSchemes") or []
    if isinstance(schemes, list):
        for sch in schemes:
            if isinstance(sch, dict):
                pts = sch.get("points") or sch.get("measurements") or []
                if isinstance(pts, list):
                    points = list(points) + [p for p in pts if isinstance(p, dict)]
    if not points:
        return
    # группируем по элементу / шву
    groups: Dict[str, List[Dict[str, Any]]] = {}
    for p in points:
        key = str(
            p.get("weld_number")
            or p.get("section_number")
            or p.get("element")
            or p.get("location")
            or p.get("zone")
            or "Элемент"
        )
        groups.setdefault(key, []).append(p)
    items = list(groups.items())
    _ensure_rows(table, data_start_row + len(items))
    for i, (key, pts) in enumerate(items):
        r = data_start_row + i
        if r >= len(table.rows):
            break
        first = pts[0]
        _set(table, r, 0, key)
        _set(table, r, 1, first.get("element") or first.get("location") or key)
        _set(
            table,
            r,
            2,
            first.get("min_allowed_thickness") or first.get("min_thickness") or "",
        )
        # точки в колонки 3..19
        for j, p in enumerate(pts[:17]):
            col = 3 + j
            if col < len(table.rows[r].cells):
                _set(table, r, col, p.get("thickness") or p.get("value") or p.get("measured") or "")
        if 20 < len(table.rows[r].cells):
            _set(table, r, 20, first.get("note") or "")


def fill_uzt_crane_table(table: Table, data: Dict[str, Any], start_row: int = 1) -> None:
    """T38 to-3: element rows with point pairs."""
    points = _as_list(data, "thickness_measurements", "thicknessMeasurements")
    schemes = data.get("uzt_schemes") or []
    if isinstance(schemes, list):
        for sch in schemes:
            if isinstance(sch, dict):
                pts = sch.get("measurements") or sch.get("points") or []
                if isinstance(pts, list):
                    points = list(points) + [p for p in pts if isinstance(p, dict)]
    if not points:
        return
    groups: Dict[str, List[Dict[str, Any]]] = {}
    for p in points:
        key = str(p.get("element") or p.get("location") or p.get("zone") or "Элемент")
        groups.setdefault(key, []).append(p)
    # заполняем существующие строки сечений или добавляем
    for r in range(start_row, len(table.rows)):
        el_name = (table.rows[r].cells[0].text or "").strip()
        # match group
        matched = None
        for k, pts in groups.items():
            if el_name and (el_name.lower() in k.lower() or k.lower() in el_name.lower()):
                matched = pts
                break
        if matched is None and groups:
            # take next unused
            k, matched = next(iter(groups.items()))
            groups.pop(k, None)
            if el_name == "" or "сечение" in el_name.lower():
                pass
        if not matched:
            continue
        first = matched[0]
        _set(table, r, 1, first.get("nominal_thickness") or first.get("nominal") or "")
        _set(table, r, 2, first.get("min_allowed_thickness") or "")
        # cols 3,4 / 5,6 / 7,8 / 9,10 = № точки, толщина
        for j, p in enumerate(matched[:4]):
            c_num = 3 + j * 2
            c_th = 4 + j * 2
            if c_num < len(table.rows[r].cells):
                _set(table, r, c_num, p.get("point_number") or (j + 1))
            if c_th < len(table.rows[r].cells):
                _set(table, r, c_th, p.get("thickness") or p.get("value") or "")


def fill_mpk_table(table: Table, data: Dict[str, Any], start_row: int = 1) -> None:
    welds = [
        w
        for w in _as_list(data, "weld_inspections", "weldInspections")
        if (w.get("control_method") or "").upper() in ("MPK", "МПК", "MT")
        or w.get("pvk_defect")
        or "МПК" in str(w.get("control_method") or "").upper()
        or "MPK" in str(w.get("control_method") or "").upper()
    ]
    _ensure_rows(table, start_row + max(len(welds), 1))
    for i, w in enumerate(welds):
        r = start_row + i
        if r >= len(table.rows):
            break
        vals = [
            w.get("weld_number") or w.get("joint_number") or "",
            w.get("element") or w.get("location_on_control_map") or "",
            w.get("diameter") or w.get("dn") or "",
            w.get("defect_description") or w.get("pvk_defect") or "дефектов не обнаружено",
            w.get("conclusion") or "Годен",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v)


def fill_vtk_table(table: Table, data: Dict[str, Any], start_row: int = 1) -> None:
    welds = [
        w
        for w in _as_list(data, "weld_inspections")
        if "ВТК" in str(w.get("control_method") or "").upper()
        or "VTK" in str(w.get("control_method") or "").upper()
        or "ET" in str(w.get("control_method") or "").upper()
    ]
    _ensure_rows(table, start_row + max(len(welds), 1))
    for i, w in enumerate(welds):
        r = start_row + i
        if r >= len(table.rows):
            break
        vals = [
            w.get("weld_number") or w.get("binding") or "",
            w.get("element") or w.get("location_on_control_map") or "",
            w.get("diameter") or w.get("dn") or "",
            w.get("defect_description") or "дефектов не обнаружено",
            w.get("conclusion") or "Годен",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v)


def fill_hardness_pipeline_table(table: Table, data: Dict[str, Any], start_row: int = 1) -> None:
    tests = _as_list(data, "hardness_tests", "hardnessTests")
    _ensure_rows(table, start_row + max(len(tests), 1))
    for i, t in enumerate(tests):
        r = start_row + i
        if r >= len(table.rows):
            break
        base = t.get("hardness_base") or t.get("hardnessBase") or t.get("hardness_base_t1") or ""
        weld = t.get("hardness_weld") or t.get("hardnessWeld") or ""
        haz = t.get("hardness_haz") or t.get("hardnessHaz") or t.get("hardness_haz_t2") or ""
        vals = [
            t.get("weld_number") or t.get("binding") or "",
            t.get("element_name") or t.get("element") or t.get("location") or "",
            t.get("dn") or t.get("diameter") or "",
            base,
            weld,
            haz,
            t.get("allowed_hardness_base") or t.get("allowed") or "120-180",
            t.get("conclusion") or "соответствует",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v)


def fill_geometry_table(table: Table, data: Dict[str, Any], start_row: int = 1) -> None:
    pts = _as_list(data, "geometry_points")
    if not pts:
        # deflection as fallback
        for d in _as_list(data, "deflection_measurements"):
            pts.append(
                {
                    "point": d.get("location") or d.get("point"),
                    "height_mm": d.get("deflection") or d.get("value"),
                    "slope": "",
                    "conclusion": d.get("note") or "",
                }
            )
    _ensure_rows(table, start_row + max(len(pts), 1))
    for i, p in enumerate(pts):
        r = start_row + i
        if r >= len(table.rows):
            break
        vals = [
            p.get("point") or p.get("number") or (i + 1),
            p.get("height_mm") or p.get("height") or "",
            p.get("slope") or p.get("slope_mm_per_m") or "",
            p.get("slope2") or p.get("slope_mm_per_m") or "",
            p.get("conclusion") or p.get("note") or "",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v)


def fill_ehz_station(table: Table, data: Dict[str, Any]) -> None:
    st = _ad(data).get("ehz_station") or data.get("ehz_station") or {}
    if not isinstance(st, dict):
        return
    mapping = {
        "тип катодной": st.get("station_type") or st.get("type"),
        "мощность": st.get("power_w") or st.get("power"),
        "напряжение": st.get("voltage_v") or st.get("voltage"),
        "ток": st.get("current_a") or st.get("current"),
        "сопротивление": st.get("resistance") or st.get("ground_resistance"),
    }
    for r in range(1, len(table.rows)):
        label = " ".join((c.text or "") for c in table.rows[r].cells[:2]).lower()
        for key, val in mapping.items():
            if key in label and val not in (None, ""):
                col = 2 if len(table.rows[r].cells) > 2 else 1
                _set(table, r, col, val)
                break


def fill_ehz_points(table: Table, data: Dict[str, Any], start_row: int = 1) -> None:
    pts = _as_list(data, "ehz_points")
    for i, p in enumerate(pts):
        r = start_row + i
        if r >= len(table.rows):
            _ensure_rows(table, r + 1)
        if r >= len(table.rows):
            break
        vals = [
            str(i + 1),
            p.get("point_on_scheme") or p.get("point") or "",
            p.get("object_name") or p.get("object") or "",
            p.get("protective_potential_v") or p.get("potential") or "",
            p.get("coating_state") or p.get("insulation_state") or "",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v)


def fill_pipeline_calc(table: Table, data: Dict[str, Any], data_start: int = 2) -> None:
    rows = _as_list(data, "pipeline_calc_rows")
    calc = data.get("calculation_data") if isinstance(data.get("calculation_data"), dict) else {}
    if not rows and calc:
        rows = [
            {
                "diameter": calc.get("diameter") or data.get("diameter"),
                "pressure": calc.get("pressure") or data.get("working_pressure"),
                "n": calc.get("n") or "1,1",
                "m": calc.get("m") or "0,66",
                "k1": calc.get("k1") or "",
                "kn": calc.get("kn") or "1,1",
                "steel": calc.get("steel") or data.get("pipe_material") or _ad(data).get("pipe_material"),
                "strength": calc.get("strength") or "",
                "min_thickness": calc.get("min_thickness") or "",
            }
        ]
    for i, row in enumerate(rows):
        r = data_start + i
        if r >= len(table.rows):
            _ensure_rows(table, r + 1)
        if r >= len(table.rows):
            break
        vals = [
            str(i + 1),
            row.get("diameter") or "",
            row.get("pressure") or "",
            row.get("n") or "",
            row.get("m") or "",
            row.get("k1") or "",
            row.get("kn") or "",
            row.get("steel") or "",
            row.get("strength") or "",
            row.get("min_thickness") or "",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v)


def fill_pipeline_life(table: Table, data: Dict[str, Any], start_row: int = 1) -> None:
    rows = _as_list(data, "pipeline_life_rows")
    if not rows:
        for p in _as_list(data, "thickness_measurements")[:8]:
            rows.append(
                {
                    "weld_number": p.get("weld_number") or p.get("section_number") or "",
                    "element": p.get("element") or p.get("location") or "",
                    "diameter": p.get("diameter") or data.get("diameter") or "",
                    "year": data.get("commissioning_year") or "",
                    "fact": p.get("thickness") or "",
                    "nominal": p.get("nominal_thickness") or data.get("wall_thickness") or "",
                    "min": p.get("min_allowed_thickness") or "",
                    "corrosion_rate": "",
                    "life": (data.get("calculation_data") or {}).get("residual_life_years")
                    if isinstance(data.get("calculation_data"), dict)
                    else "",
                }
            )
    _ensure_rows(table, start_row + max(len(rows), 1))
    for i, row in enumerate(rows):
        r = start_row + i
        if r >= len(table.rows):
            break
        vals = [
            row.get("weld_number") or "",
            row.get("element") or "",
            row.get("diameter") or "",
            row.get("year") or "",
            row.get("fact") or "",
            row.get("nominal") or "",
            row.get("min") or "",
            row.get("corrosion_rate") or "",
            row.get("life") or "",
        ]
        for c, v in enumerate(vals):
            if c < len(table.rows[r].cells):
                _set(table, r, c, v)


def fill_crane_vik_zones(table: Table, data: Dict[str, Any], start_row: int = 1) -> None:
    """Заполнить результаты в заранее размеченные зоны T34."""
    defects = _as_list(data, "visual_defects")
    results = _ad(data).get("crane_vik_results") or {}
    if not isinstance(results, dict):
        results = {}
    for r in range(start_row, len(table.rows)):
        zone = (table.rows[r].cells[1].text if len(table.rows[r].cells) > 1 else "") or ""
        zone_l = zone.lower()
        # объём
        if len(table.rows[r].cells) > 2 and not (table.rows[r].cells[2].text or "").strip():
            _set(table, r, 2, results.get(f"{r}_scope") or "100%")
        # результат
        matched = None
        for d in defects:
            loc = (d.get("location") or "").lower()
            if loc and (loc in zone_l or zone_l[:20] in loc):
                matched = d
                break
        res = (
            (matched.get("assessment") if matched else None)
            or results.get(str(r))
            or results.get(zone)
            or ("дефектов не выявлено" if not matched else (matched.get("description") or matched.get("defect_type")))
        )
        if len(table.rows[r].cells) > 3:
            _set(table, r, 3, res or "дефектов не выявлено")
        if len(table.rows[r].cells) > 4:
            _set(table, r, 4, (matched.get("assessment") if matched else None) or "Годен")


def fill_crane_uzk_table(table: Table, data: Dict[str, Any], start_row: int = 1) -> None:
    welds = [
        w
        for w in _as_list(data, "weld_inspections")
        if (w.get("control_method") or "").upper() in ("UZK", "УЗК", "")
        or w.get("uzk_defect")
    ]
    # заполняем по существующим строкам объектов
    for r in range(start_row, len(table.rows)):
        obj = (table.rows[r].cells[1].text if len(table.rows[r].cells) > 1 else "") or ""
        matched = None
        for w in welds:
            loc = str(w.get("location_on_control_map") or w.get("weld_number") or "").lower()
            if loc and (obj.lower()[:15] in loc or loc in obj.lower()):
                matched = w
                break
        if matched is None and welds:
            matched = welds.pop(0)
        if not matched:
            if len(table.rows[r].cells) > 3 and not (table.rows[r].cells[3].text or "").strip():
                _set(table, r, 3, "дефектов не обнаружено")
            if len(table.rows[r].cells) > 4:
                _set(table, r, 4, "Годен")
            continue
        if len(table.rows[r].cells) > 2:
            _set(table, r, 2, matched.get("weld_number") or matched.get("location_on_control_map") or "")
        if len(table.rows[r].cells) > 3:
            _set(
                table,
                r,
                3,
                matched.get("defect_description")
                or matched.get("uzk_defect")
                or "дефектов не обнаружено",
            )
        if len(table.rows[r].cells) > 4:
            _set(table, r, 4, matched.get("conclusion") or "Годен")


def fill_crane_safety_checklists(tables: List[Table], data: Dict[str, Any]) -> None:
    """T48–T52: колонка результата (обычно 3)."""
    results = _ad(data).get("crane_safety_checks") or data.get("crane_safety_checks") or {}
    if not isinstance(results, dict):
        results = {}
    for table in tables:
        for r in range(1, len(table.rows)):
            name = (table.rows[r].cells[0].text or "").strip()
            if not name or name == (table.rows[r].cells[1].text or "").strip():
                # section header row
                continue
            key = name
            val = results.get(key) or results.get(name.split()[0] if name else "")
            if val in (None, "") and len(table.rows[r].cells) > 3:
                # default OK if empty template
                if not (table.rows[r].cells[3].text or "").strip():
                    _set(table, r, 3, results.get("_default") or "соответствует")
            elif val not in (None, "") and len(table.rows[r].cells) > 3:
                _set(table, r, 3, val)


def fill_crane_safety_devices(table: Table, data: Dict[str, Any], start_row: int = 1) -> None:
    devices = _ad(data).get("crane_safety_devices") or data.get("crane_safety_devices") or {}
    if not isinstance(devices, dict):
        devices = {}
    for r in range(start_row, len(table.rows)):
        name = (table.rows[r].cells[1].text if len(table.rows[r].cells) > 1 else "") or ""
        val = devices.get(name) or devices.get(str(r))
        if len(table.rows[r].cells) > 2:
            _set(table, r, 2, val if val not in (None, "") else "имеется")
        if len(table.rows[r].cells) > 3 and val not in (None, ""):
            # actual state col if empty header means state
            if not (table.rows[0].cells[3].text or "").strip() or "состоян" in (
                table.rows[0].cells[3].text or ""
            ).lower():
                _set(table, r, 3, devices.get(f"{name}_state") or "исправно")
