# -*- coding: utf-8 -*-
"""Проверка рендера слоёв схем по замечаниям 20.08.2026."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from vessel_scheme_renderer import normalize_geometry, render_vessel_scheme
from scheme_ndt_overlays import collect_scheme_overlays, layer_title, render_all_layer_pngs, render_hardness_detail_t

geo = {
    "orientation": "horizontal",
    "shell_count": 3,
    "weld_preset": "multi_shell",
    "nozzles": [
        {"label": "Пт1", "dn": 80, "position": 0.2, "circ": 0.3, "place": "body", "purpose": "вход нефти"},
        {"label": "Пт2", "dn": 50, "position": 0.5, "place": "head_left", "purpose": "выход газа"},
        {"label": "Пт3", "dn": 450, "position": 0.4, "circ": 0.7, "place": "body", "purpose": "люк-лаз"},
        {"label": "Пт4", "dn": 50, "position": 0.65, "circ": 0.25, "place": "body", "purpose": "дренаж"},
        {"label": "Пт5", "dn": 80, "position": 0.8, "circ": 0.6, "place": "body", "purpose": "КИП"},
    ],
    "dimensions": {"shell_lengths_mm": [1200, 1800, 1500], "body_length_mm": 4500, "head_diameter_mm": 2200},
}

ng = normalize_geometry(geo)
assert ng["orientation"] == "horizontal"
assert ng["heads"][0]["label"] == "Левое днище"
assert all(n.get("purpose") for n in ng["nozzles"]), ng["nozzles"]
assert len(ng["nozzles"]) == 5

png, g2, pts = render_vessel_scheme(geo, scheme_layer="vik", width=1400, height=1050)
assert png[:8] == b"\x89PNG\r\n\x1a\n", "not png"
assert "Левое" in (g2["heads"][0]["label"] or "")
assert "Карта проведения визуального" in (g2.get("title") or "")

data = {
    "orientation": "horizontal",
    "base_vessel_scheme": {"geometry": geo, "orientation": "horizontal"},
    "thickness_measurements": [
        {"section_number": i + 1, "thickness": 8.2, "element": "Обечайка"} for i in range(12)
    ],
    "hardness_tests": [
        {"point_number": "1", "hardness_base": 140},
        {"area_number": "Т1", "hardness_weld": 150},
        {"area_number": "У1", "hardness_weld": 155},
    ],
    "weld_inspections": [{"weld_number": "К1", "control_method": "UZK", "uzk_defect": "дефект"}],
    "vessel_elements": [
        {"name": "Обечайка 1", "length_mm": 1200, "diameter_mm": 2200, "material": "09Г2С"},
    ],
}
ov = collect_scheme_overlays(data)
assert ov["uzt_points"], ov
assert any(z.get("weld_label") == "К1" for z in ov["uzk_zones"])

layers = render_all_layer_pngs(data)
assert len(layers) == 5, [x["layer"] for x in layers]
assert "толщинометрии" in layers[1]["title"]
assert layers[2]["extra"]
tpng = render_hardness_detail_t("Т12")
assert tpng[:8] == b"\x89PNG\r\n\x1a\n"
print("ok layers", [x["layer"] for x in layers], "title", layer_title("vik"))
print("png vik bytes", len(png), "nozzles", [n["label"] for n in ng["nozzles"]])
