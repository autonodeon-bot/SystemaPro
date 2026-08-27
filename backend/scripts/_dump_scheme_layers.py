# -*- coding: utf-8 -*-
"""Выгрузить PNG слоёв схем НК для визуальной сверки с эталонами заказчика."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scheme_ndt_overlays import render_all_layer_pngs

OUT = Path(__file__).resolve().parents[2] / "docs" / "_scheme_preview"

GEO_VERTICAL = {
    "orientation": "vertical",
    "shell_count": 5,
    "weld_preset": "multi_shell",
    "nozzles": [
        {"label": "Пт1", "dn": 450, "position": 0.10, "circ": 0.15, "place": "body", "purpose": "вход газа"},
        {"label": "Пт2", "dn": 700, "position": 0.5, "place": "head_left", "purpose": "выход газа"},
        {"label": "Пт3", "dn": 50, "position": 0.30, "circ": 0.10, "place": "body", "purpose": "люк-лаз"},
        {"label": "Пт4", "dn": 450, "position": 0.32, "circ": 0.22, "place": "body", "purpose": "люк-лаз"},
        {"label": "Пт5", "dn": 450, "position": 0.12, "circ": 0.22, "place": "body", "purpose": "люк-лаз"},
        {"label": "Пт6", "dn": 50, "position": 0.55, "circ": 0.12, "place": "body", "purpose": "дифманометр"},
        {"label": "Пт7", "dn": 50, "position": 0.30, "circ": 0.18, "place": "body", "purpose": "дифманометр"},
        {"label": "Пт8", "dn": 50, "position": 0.12, "circ": 0.10, "place": "body", "purpose": "дифманометр"},
        {"label": "Пт9", "dn": 80, "position": 0.42, "circ": 0.25, "place": "body", "purpose": "вход РДЭГа"},
        {"label": "Пт10", "dn": 80, "position": 0.70, "circ": 0.30, "place": "body", "purpose": "выход НДЭГа"},
        {"label": "Пт11", "dn": 80, "position": 0.30, "circ": 0.35, "place": "body", "purpose": "переток ДЭГа"},
        {"label": "Пт12", "dn": 80, "position": 0.5, "place": "head_right", "purpose": "дренаж"},
    ],
    "dimensions": {
        "shell_lengths_mm": [1000, 2150, 1900, 2260, 2400],
        "body_length_mm": 13930,
        "head_diameter_mm": 3110,
    },
}

GEO_HORIZONTAL = dict(GEO_VERTICAL, orientation="horizontal", shell_count=3)
GEO_HORIZONTAL["dimensions"] = {
    "shell_lengths_mm": [1200, 1800, 1500],
    "body_length_mm": 4500,
    "head_diameter_mm": 2200,
}

_UZT = [
    {"section_number": i + 1, "thickness": 8.0 + (i % 7) * 0.1, "element": "Обечайка"}
    for i in range(60)
]
_HARD = (
    [{"point_number": str(i + 1), "hardness_base": 140 + i} for i in range(25)]
    + [{"area_number": f"Т{i + 1}", "hardness_weld": 150} for i in range(6)]
    + [{"area_number": f"У{i + 1}", "hardness_weld": 155} for i in range(8)]
)
_WELDS = [
    {"weld_number": f"К{i + 1}", "control_method": "UZK", "uzk_defect": ""} for i in range(6)
] + [
    {"weld_number": f"П{i + 1}", "control_method": "MPK", "mpk_defect": ""} for i in range(7)
]


def dump(tag: str, geo: dict) -> None:
    data = {
        "orientation": geo["orientation"],
        "base_vessel_scheme": {"geometry": geo, "orientation": geo["orientation"]},
        "thickness_measurements": _UZT,
        "hardness_tests": _HARD,
        "weld_inspections": _WELDS,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    for item in render_all_layer_pngs(data):
        path = OUT / f"{tag}_{item['layer']}.png"
        path.write_bytes(item["png"])
        print(f"{path}  ({len(item['png'])} B)  {item['title'][:70]}")
        for i, (cap, png) in enumerate(item.get("extra") or []):
            extra = OUT / f"{tag}_{item['layer']}_extra{i + 1}.png"
            extra.write_bytes(png)
            print(f"{extra}  ({len(png)} B)  {cap[:70]}")


if __name__ == "__main__":
    dump("vert", GEO_VERTICAL)
    dump("horiz", GEO_HORIZONTAL)
