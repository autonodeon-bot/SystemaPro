"""Параметрический рендер схем оборудования (44 формы ТО).

Сосуды/аппараты — карта-развёртка (днища-круги, швы вразбежку).
Остальные виды — семейства из scheme_family_renderers + каталог
scheme_equipment_catalog (to-1 … to-44).
"""
from __future__ import annotations

import io
import math
from typing import Any, Dict, List, Optional, Tuple

from PIL import Image, ImageDraw, ImageFont

from scheme_equipment_catalog import (
    FAMILY_BOILER,
    FAMILY_CRANE,
    FAMILY_ELECTRICAL,
    FAMILY_GENERIC,
    FAMILY_MACHINERY,
    FAMILY_PIPELINE,
    FAMILY_STATION,
    FAMILY_TANK,
    FAMILY_TOWER,
    FAMILY_VALVE,
    FAMILY_VESSEL_DEV,
    defaults_for_kind,
    get_kind,
    kind_title,
    resolve_family,
)
from scheme_family_renderers import (
    draw_boiler_family,
    draw_crane_family,
    draw_electrical_family,
    draw_generic_family,
    draw_machinery_family,
    draw_pipeline_family,
    draw_station_family,
    draw_tank_family,
    draw_tower_family,
    draw_valve_family,
)

# Легенда: 3 колонки позволяют уместить все патрубки крупного сосуда,
# не съедая поле чертежа.
_LEGEND_COLUMNS = 3
_LEGEND_LINE_H = 14
_LEGEND_MAX_H = 190

WELD_PRESETS = (
    "ring_only",
    "long_plus_rings",
    "multi_shell",
    "custom",
    "single_longitudinal",
    "two_circumferential",
)

# Совместимость со старым кодом
VESSEL_LIKE_KINDS = frozenset(
    {
        "vessel",
        "gas_separator",
        "oil_settler",
        "receiver",
        "pig_trap",
        "air_cooler",
    }
)

EQUIPMENT_KINDS = frozenset()  # заполняется лениво через каталог
KIND_TITLES: Dict[str, str] = {}
KIND_CATEGORIES: Dict[str, str] = {}


def _rebuild_kind_maps() -> None:
    global EQUIPMENT_KINDS, KIND_TITLES, KIND_CATEGORIES
    from scheme_equipment_catalog import EQUIPMENT_SCHEME_KINDS

    KIND_TITLES = {k["code"]: f"Карта контроля: {k['title']}" for k in EQUIPMENT_SCHEME_KINDS}
    KIND_CATEGORIES = {k["code"]: k.get("category") or "other" for k in EQUIPMENT_SCHEME_KINDS}
    EQUIPMENT_KINDS = frozenset(KIND_TITLES.keys())


_rebuild_kind_maps()


def _f(v: Any, default: float = 0.0) -> float:
    try:
        if v is None or v == "":
            return default
        return float(str(v).replace(",", "."))
    except (TypeError, ValueError):
        return default


def _font(size: int = 14):
    for name in (
        "C:/Windows/Fonts/times.ttf",
        "C:/Windows/Fonts/arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ):
        try:
            return ImageFont.truetype(name, size)
        except Exception:
            continue
    return ImageFont.load_default()


def normalize_equipment_kind(raw: Any) -> str:
    kind = str(raw or "vessel").lower().strip().replace("-", "_").replace(" ", "_")
    aliases = {
        "сосуд": "vessel",
        "vessel_pressure": "vessel",
        "gasseparator": "gas_separator",
        "separator": "gas_separator",
        "undergroundtank": "underground_tank",
        "емкость": "underground_tank",
        "tank_underground": "underground_tank",
        "oilsettler": "oil_settler",
        "settler": "oil_settler",
        "pipe": "pipeline",
        "трубопровод": "pipeline",
        "underground_pipe": "underground_pipeline",
        "gpm": "crane",
        "lifting": "crane",
        "кран": "crane",
        "компрессор": "compressor",
        "котёл": "boiler",
        "котел": "boiler",
        "факел": "flare",
    }
    kind = aliases.get(kind, kind)
    meta = get_kind(kind) or get_kind(raw)
    if meta:
        return str(meta["code"])
    if kind in EQUIPMENT_KINDS:
        return kind
    return "vessel"


def _clamp01(v: float, lo: float = 0.06, hi: float = 0.94) -> float:
    return min(hi, max(lo, v))


def _longitudinal_positions_for_shell(
    shell_index: int,
    *,
    dual_plates: bool,
) -> List[float]:
    """Позиции продольных швов на обечайке (доля развёртки 0..1 по окружности).

    Соседняя обечайка смещена примерно на половину шага листа:
    шов попадает в середину листа соседней обечайки (не стык встык).
    """
    if dual_plates:
        # Два листа: швы через ~½; соседняя dual-обечайка сдвинута на ~¼
        # (шов попадает в середину листа соседа).
        phase = ((shell_index // 2) % 2) * 0.25
        a = _clamp01(0.18 + phase)
        b = _clamp01(0.68 + phase)
        return sorted({round(a, 4), round(b, 4)})

    # Один продольный: чередование ~0.30 / ~0.70 (смещение на половину)
    pos = 0.30 if (shell_index % 2) == 0 else 0.70
    # лёгкий дополнительный сдвиг каждые 2 обечайки
    pos = _clamp01(pos + (shell_index // 2) * 0.05 * (1 if shell_index % 2 == 0 else -1))
    return [pos]


def _build_vessel_welds(
    preset: str,
    shell_count: int,
    raw_welds: List[Any],
) -> Tuple[List[Dict[str, Any]], int]:
    """Кольцевые К + продольные П со смещением на половину соседней обечайки."""
    welds: List[Dict[str, Any]] = []

    if preset == "custom" and raw_welds:
        for i, w in enumerate(raw_welds):
            if not isinstance(w, dict):
                continue
            kind = str(w.get("kind") or "circumferential")
            item: Dict[str, Any] = {
                "id": str(w.get("id") or f"W{i + 1}"),
                "kind": kind,
                "position": min(0.95, max(0.05, _f(w.get("position"), 0.5))),
                "label": str(w.get("label") or w.get("id") or (f"К{i + 1}" if kind != "longitudinal" else f"П{i + 1}")),
                "shell_index": int(_f(w.get("shell_index"), -1)),
            }
            if kind == "longitudinal":
                item["span_start"] = min(0.99, max(0.0, _f(w.get("span_start"), 0.0)))
                item["span_end"] = min(1.0, max(item["span_start"] + 0.01, _f(w.get("span_end"), 1.0)))
            welds.append(item)
        return welds, shell_count

    if preset == "multi_shell" and shell_count < 2:
        shell_count = 2

    # Кольцевые: только между обечайками + стыки с днищами (как К1..Кn на карте)
    # На карте ВИК кольцевые — внутренние стыки; торцы корпуса тоже стык с днищем
    ring_count = shell_count + 1  # верхний стык + между + нижний
    for i in range(ring_count):
        # равномерно по высоте корпуса: 0, 1/n, 2/n, ..., 1
        pos = i / shell_count if shell_count else 0.0
        pos = 0.0 if i == 0 else (1.0 if i == ring_count - 1 else i / shell_count)
        welds.append(
            {
                "id": f"K{i + 1}",
                "kind": "circumferential",
                "position": pos,
                "label": f"К{i + 1}",
            }
        )

    if preset in ("long_plus_rings", "multi_shell"):
        # dual_plates: часть обечаек из двух листов (два продольных) — как на карте ВИК
        p_idx = 1
        for s in range(shell_count):
            span_start = s / shell_count
            span_end = (s + 1) / shell_count
            if preset == "multi_shell":
                # крайние — часто 1 шов, средние — чаще 2 (смещение вразбежку)
                dual = shell_count >= 3 and 0 < s < shell_count - 1 and (s % 2 == 1)
            elif shell_count >= 4:
                dual = s % 2 == 1
            else:
                dual = False
            for circ in _longitudinal_positions_for_shell(s, dual_plates=dual):
                welds.append(
                    {
                        "id": f"P{p_idx}",
                        "kind": "longitudinal",
                        "position": circ,
                        "span_start": span_start,
                        "span_end": span_end,
                        "shell_index": s,
                        "label": f"П{p_idx}",
                    }
                )
                p_idx += 1

    return welds, shell_count


def _build_pipeline_welds(segment_count: int, raw_welds: List[Any], preset: str) -> List[Dict[str, Any]]:
    if preset == "custom" and raw_welds:
        welds: List[Dict[str, Any]] = []
        for i, w in enumerate(raw_welds):
            if not isinstance(w, dict):
                continue
            welds.append(
                {
                    "id": str(w.get("id") or f"W{i + 1}"),
                    "kind": str(w.get("kind") or "circumferential"),
                    "position": min(0.95, max(0.05, _f(w.get("position"), 0.5))),
                    "label": str(w.get("label") or w.get("id") or f"К{i + 1}"),
                }
            )
        return welds

    n = max(1, segment_count)
    welds = []
    positions = [0.05]
    if n > 1:
        for k in range(1, n):
            positions.append(k / n)
    positions.append(0.95)
    for i, p in enumerate(positions):
        welds.append(
            {
                "id": f"K{i + 1}",
                "kind": "circumferential",
                "position": p,
                "label": f"К{i + 1}",
            }
        )
    return welds


def normalize_geometry(raw: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Привести вход к каноническому виду и развернуть пресет швов."""
    data = dict(raw or {})
    kind = normalize_equipment_kind(data.get("equipment_kind") or data.get("kind") or data.get("type") or data.get("form_id"))
    family = resolve_family(kind)
    defs = defaults_for_kind(kind)

    orientation = str(data.get("orientation") or defs.get("orientation") or "vertical").lower().strip()
    if orientation not in ("horizontal", "vertical"):
        orientation = "vertical"
    if family in (FAMILY_PIPELINE, FAMILY_CRANE, FAMILY_MACHINERY) and not data.get("orientation"):
        orientation = "horizontal"
    if family == FAMILY_VESSEL_DEV and not data.get("orientation"):
        orientation = str(defs.get("orientation") or "vertical")

    shell_in = data.get("shell") if isinstance(data.get("shell"), dict) else {}
    length = max(0.2, _f(shell_in.get("length"), _f(data.get("shell_length"), 1.0)))
    diameter = max(0.15, _f(shell_in.get("diameter"), _f(data.get("shell_diameter"), 0.5)))
    default_count = int(_f(defs.get("shell_count"), 3 if family == FAMILY_VESSEL_DEV else 4))
    shell_count = max(1, int(_f(data.get("shell_count"), _f(shell_in.get("count"), default_count))))
    if family == FAMILY_PIPELINE:
        shell_count = max(1, int(_f(data.get("segment_count"), shell_count)))

    head_type = str(data.get("head_type") or "elliptical").lower()
    if head_type not in ("elliptical", "flat", "hemispherical"):
        head_type = "elliptical"

    if orientation == "horizontal":
        heads = [
            {"side": "left", "type": head_type, "label": "Левое днище"},
            {"side": "right", "type": head_type, "label": "Правое днище"},
        ]
    else:
        heads = [
            {"side": "top", "type": head_type, "label": "Верхнее днище"},
            {"side": "bottom", "type": head_type, "label": "Нижнее днище"},
        ]
    if isinstance(data.get("heads"), list) and data["heads"]:
        heads = []
        for h in data["heads"]:
            if isinstance(h, dict):
                heads.append(
                    {
                        "side": str(h.get("side") or ""),
                        "type": str(h.get("type") or head_type),
                        "label": str(h.get("label") or ""),
                    }
                )

    nozzles: List[Dict[str, Any]] = []
    for i, n in enumerate(data.get("nozzles") or []):
        if not isinstance(n, dict):
            continue
        side = str(n.get("side") or "body")
        circ = n.get("circ")
        if circ in (None, ""):
            circ_map = {"left": 0.2, "right": 0.8, "top": 0.5, "bottom": 0.5, "body": 0.55}
            circ = circ_map.get(side, 0.5)
        axial = n.get("axial")
        if axial in (None, ""):
            axial = n.get("position", 0.5)
        place = str(n.get("place") or "body")
        circ_explicit = n.get("circ") not in (None, "")
        axial_explicit = n.get("axial") not in (None, "") or n.get("position") not in (None, "")
        if side in ("top",) and orientation == "vertical":
            place = "head_top"
        elif side in ("bottom",) and orientation == "vertical":
            place = "head_bottom"
        elif side in ("left", "top") and orientation == "horizontal" and place == "body":
            if side == "left":
                place = "head_left"
        elif side in ("right", "bottom") and orientation == "horizontal" and place == "body":
            if side == "right":
                place = "head_right"
        if place in ("head_top",) and orientation == "horizontal":
            place = "head_left"
        elif place in ("head_bottom",) and orientation == "horizontal":
            place = "head_right"
        nozzles.append(
            {
                "id": str(n.get("id") or f"Пт{i + 1}"),
                "dn": n.get("dn") if n.get("dn") not in (None, "") else 50,
                "position": min(0.95, max(0.05, _f(axial, 0.5))),
                "axial": min(0.95, max(0.05, _f(axial, 0.5))),
                "circ": min(0.95, max(0.05, _f(circ, 0.5))),
                "side": side,
                "place": place,
                "label": str(n.get("label") or n.get("id") or f"Пт{i + 1}"),
                "purpose": str(n.get("purpose") or n.get("assignment") or n.get("role") or ""),
                "_circ_default": not circ_explicit,
                "_axial_default": not axial_explicit,
            }
        )
    # Если несколько патрубков на корпусе без явных координат — разнести, чтобы не слипались
    body_nozzles = [n for n in nozzles if str(n.get("place") or "body") == "body"]
    if len(body_nozzles) > 1:
        n_def = sum(1 for n in body_nozzles if n.get("_circ_default") and n.get("_axial_default"))
        if n_def == len(body_nozzles):
            for i, n in enumerate(body_nozzles):
                n["axial"] = min(0.92, max(0.08, 0.12 + 0.76 * (i / max(len(body_nozzles) - 1, 1))))
                n["position"] = n["axial"]
                n["circ"] = 0.18 + 0.64 * ((i * 3) % 5) / 4
    for n in nozzles:
        n.pop("_circ_default", None)
        n.pop("_axial_default", None)

    preset = str(data.get("weld_preset") or defs.get("weld_preset") or "long_plus_rings").strip()
    if preset in ("single_longitudinal",):
        preset = "long_plus_rings"
    if preset in ("two_circumferential",):
        preset = "ring_only"
    if preset not in WELD_PRESETS:
        preset = "long_plus_rings"
    if family == FAMILY_PIPELINE and preset == "long_plus_rings":
        preset = "ring_only"

    raw_welds = data.get("welds") if isinstance(data.get("welds"), list) else []
    if family == FAMILY_VESSEL_DEV:
        welds, shell_count = _build_vessel_welds(preset, shell_count, raw_welds)
    elif family in (FAMILY_PIPELINE, FAMILY_TANK, FAMILY_TOWER, FAMILY_BOILER):
        welds = _build_pipeline_welds(shell_count, raw_welds, preset)
        if family == FAMILY_VESSEL_DEV:
            pass
    else:
        welds = []

    meta = get_kind(kind) or {}
    default_title = str(data.get("title") or kind_title(kind) or KIND_TITLES.get(kind, "Карта контроля"))
    dims = data.get("dimensions") if isinstance(data.get("dimensions"), dict) else {}
    return {
        "equipment_kind": kind,
        "form_id": meta.get("form_id"),
        "scheme_family": family,
        "category": meta.get("category") or KIND_CATEGORIES.get(kind, "other"),
        "view": "development" if family == FAMILY_VESSEL_DEV else "schematic",
        "orientation": orientation,
        "shell": {"length": length, "diameter": diameter, "count": shell_count},
        "shell_count": shell_count,
        "segment_count": shell_count,
        "head_type": head_type,
        "heads": heads,
        "nozzles": nozzles,
        "welds": welds,
        "weld_preset": preset,
        "title": default_title,
        "scheme_layer": str(data.get("scheme_layer") or "vik"),
        "dimensions": dims,
    }


def _layout_development(
    geo: Dict[str, Any], width: int, height: int, margin_bottom: int = 120
) -> Dict[str, Any]:
    """Развёртка: прямоугольник корпуса + круги днищ.

    vertical: верхнее днище / корпус / нижнее днище
    horizontal: левое днище | корпус | правое днище
    """
    orient = str(geo.get("orientation") or "vertical")
    margin_x = 70
    margin_top = 56
    usable_w = width - 2 * margin_x
    usable_h = height - margin_top - margin_bottom
    cx = width / 2
    cy = margin_top + usable_h / 2

    if orient == "horizontal":
        # Днища и корпус должны занимать поле чертежа, иначе развёртка
        # висит узкой полосой посреди пустого листа.
        head_d = min(usable_h * 0.55, usable_w * 0.24)
        gap = 22
        body_w = max(280, usable_w - 2 * head_d - 2 * gap)
        body_h = min(usable_h * 0.9, head_d * 1.9)
        body_x0 = margin_x + head_d + gap
        body_x1 = body_x0 + body_w
        body_y0 = cy - body_h / 2
        body_y1 = cy + body_h / 2
        left_cx = margin_x + head_d / 2
        right_cx = body_x1 + gap + head_d / 2
        return {
            "view": "development",
            "orient": "horizontal",
            "body": (body_x0, body_y0, body_x1, body_y1),
            "head_top": (left_cx, cy, head_d / 2),
            "head_bottom": (right_cx, cy, head_d / 2),
            "head_left": (left_cx, cy, head_d / 2),
            "head_right": (right_cx, cy, head_d / 2),
            "cx": cx,
            "kind": geo.get("equipment_kind") or "vessel",
            "shell_count": int(geo.get("shell_count") or 1),
        }

    body_w = min(usable_w * 0.72, 760)
    head_d = min(body_w * 0.42, usable_h * 0.20)
    gap = 18
    body_h = max(180, usable_h - 2 * head_d - 2 * gap)
    top_cy = margin_top + head_d / 2
    body_y0 = margin_top + head_d + gap
    body_y1 = body_y0 + body_h
    body_x0 = cx - body_w / 2
    body_x1 = cx + body_w / 2
    bot_cy = body_y1 + gap + head_d / 2
    return {
        "view": "development",
        "orient": "vertical",
        "body": (body_x0, body_y0, body_x1, body_y1),
        "head_top": (cx, top_cy, head_d / 2),
        "head_bottom": (cx, bot_cy, head_d / 2),
        "cx": cx,
        "kind": geo.get("equipment_kind") or "vessel",
        "shell_count": int(geo.get("shell_count") or 1),
    }


def _layout_schematic(geo: Dict[str, Any], width: int, height: int) -> Dict[str, Any]:
    """Упрощённая схема для трубопровода / компрессора / ГПМ."""
    orient = geo["orientation"]
    margin = 70
    usable_w = width - 2 * margin
    usable_h = height - 2 * margin - 40
    L = geo["shell"]["length"]
    D = geo["shell"]["diameter"]
    aspect = L / max(D, 0.01)
    kind = geo.get("equipment_kind") or "vessel"

    if kind in ("pipeline", "underground_pipeline"):
        body_h = min(usable_h * 0.28, 120)
        body_w = usable_w * 0.85
        cx = width / 2
        cy = height / 2 + 10
        x0 = cx - body_w / 2
        y0 = cy - body_h / 2
        return {
            "view": "schematic",
            "orient": "horizontal",
            "body": (x0, y0, x0 + body_w, y0 + body_h),
            "cx": cx,
            "cy": cy,
            "kind": kind,
        }

    if orient == "horizontal":
        body_h = min(usable_h * 0.55, usable_w / max(aspect, 0.5) * 0.45)
        body_w = min(usable_w * 0.78, body_h * aspect)
    else:
        body_w = min(usable_w * 0.45, usable_h / max(aspect, 0.5) * 0.4)
        body_h = min(usable_h * 0.7, body_w * aspect)
    cx = width / 2
    cy = height / 2 + 10
    x0 = cx - body_w / 2
    y0 = cy - body_h / 2
    return {
        "view": "schematic",
        "orient": orient,
        "body": (x0, y0, x0 + body_w, y0 + body_h),
        "cx": cx,
        "cy": cy,
        "kind": kind,
    }


def _draw_full_head_circle(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    r: float,
    ink: Tuple[int, int, int],
    label: str,
    font,
    *,
    weld_color: Tuple[int, int, int],
    draw_radial_weld: bool = True,
) -> None:
    """Днище — полный круг (вид с торца), не полуокружность."""
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=ink, width=3)
    # небольшой радиальный шов на днище (как П на эталоне)
    if draw_radial_weld:
        draw.line([(cx, cy - r + 4), (cx, cy + r - 4)], fill=weld_color, width=2)
    # внутренний кружок (люк / патрубок условно)
    ir = r * 0.22
    draw.ellipse([cx - ir, cy - ir, cx + ir, cy + ir], outline=ink, width=2)
    # Подпись сбоку от круга с выноской: над кругом она наезжает на кромку
    # корпуса развёртки, а снизу — на размер диаметра днища.
    try:
        tb = draw.textbbox((0, 0), label, font=font)
        tw, th = tb[2] - tb[0], tb[3] - tb[1]
    except Exception:
        tw, th = len(label) * 6.0, 11.0
    if cx - r - tw - 14 >= 12:
        lx, leader_x = cx - r - tw - 14, cx - r - 10
    else:
        lx, leader_x = cx + r + 14, cx + r + 10
    ly = cy - r * 0.55 - th / 2
    draw.text((lx, ly), label, fill=ink, font=font)
    draw.line([(leader_x, ly + th / 2), (cx + (r * 0.28 if leader_x < cx else -r * 0.28), cy - r * 0.35)], fill=ink, width=1)


def _boxes_overlap(a: Tuple[float, float, float, float], b: Tuple[float, float, float, float]) -> bool:
    return not (a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1])


def _place_label(
    draw: ImageDraw.ImageDraw,
    anchor_x: float,
    anchor_y: float,
    r: float,
    caption: str,
    font,
    taken: List[Tuple[float, float, float, float]],
) -> Tuple[float, float]:
    """Подобрать позицию подписи так, чтобы она не наезжала на уже размещённые."""
    try:
        tb = draw.textbbox((0, 0), caption, font=font)
        tw, th = tb[2] - tb[0], tb[3] - tb[1]
    except Exception:
        tw, th = len(caption) * 6.0, 11.0

    # справа, слева, снизу, сверху — и те же варианты с увеличенным отступом
    candidates: List[Tuple[float, float]] = []
    for step in (0, 1, 2):
        pad = r + 4 + step * (th + 3)
        candidates.extend(
            [
                (anchor_x + pad, anchor_y - th / 2),
                (anchor_x - pad - tw, anchor_y - th / 2),
                (anchor_x - tw / 2, anchor_y + pad),
                (anchor_x - tw / 2, anchor_y - pad - th),
            ]
        )

    for lx, ly in candidates:
        box = (lx - 1, ly - 1, lx + tw + 1, ly + th + 1)
        if not any(_boxes_overlap(box, t) for t in taken):
            taken.append(box)
            return lx, ly

    lx, ly = candidates[0]
    taken.append((lx - 1, ly - 1, lx + tw + 1, ly + th + 1))
    return lx, ly


def _draw_nozzle_on_dev(
    draw: ImageDraw.ImageDraw,
    x: float,
    y: float,
    dn: Any,
    label: str,
    accent: Tuple[int, int, int],
    font,
    taken: Optional[List[Tuple[float, float, float, float]]] = None,
) -> Tuple[float, float]:
    try:
        dn_f = float(str(dn).replace(",", "."))
    except (TypeError, ValueError):
        dn_f = 50.0
    r = max(8, min(28, 6 + dn_f / 20))
    draw.ellipse([x - r, y - r, x + r, y + r], outline=accent, width=2)
    # крест
    draw.line([(x - r * 0.55, y), (x + r * 0.55, y)], fill=accent, width=1)
    draw.line([(x, y - r * 0.55), (x, y + r * 0.55)], fill=accent, width=1)
    caption = f"{label}" + (f" Ø{dn}" if dn not in (None, "") else "")
    if taken is None:
        draw.text((x + r + 4, y - 8), caption, fill=accent, font=font)
    else:
        # сам кружок патрубка тоже занимает место — подписи его обходят
        taken.append((x - r, y - r, x + r, y + r))
        lx, ly = _place_label(draw, x, y, r, caption, font, taken)
        draw.text((lx, ly), caption, fill=accent, font=font)
    return x, y


def _draw_layer_overlays(
    draw: ImageDraw.ImageDraw,
    overlays: Dict[str, Any],
    layer: str,
    *,
    width: int,
    height: int,
    weld_segs: Dict[str, Tuple[float, float, float, float]],
    nozzle_xy: Dict[str, Tuple[float, float]],
    font_tiny,
    taken: Optional[List[Tuple[float, float, float, float]]] = None,
    body: Optional[Tuple[float, float, float, float]] = None,
) -> None:
    """Точки УЗТ/ТК и зоны УЗК/МПК поверх развёртки."""
    boxes = taken if taken is not None else []

    def _xy(p: Dict[str, Any]) -> Optional[Tuple[float, float]]:
        if body is not None and p.get("auto_placed"):
            # Расчётные точки раскладываем сеткой по реальному корпусу —
            # иначе они уезжают за развёртку или слипаются у кромок.
            bx0, by0, bx1, by1 = body
            cols = max(1, int(p.get("auto_cols") or 1))
            rows = max(1, int(p.get("auto_rows") or 1))
            pad_x = min(30.0, (bx1 - bx0) * 0.06)
            pad_y = min(30.0, (by1 - by0) * 0.08)
            ix0, ix1 = bx0 + pad_x, bx1 - pad_x
            iy0, iy1 = by0 + pad_y, by1 - pad_y
            col = int(p.get("auto_col") or 0)
            row = int(p.get("auto_row") or 0)
            x = ix0 + (ix1 - ix0) * ((col + 0.5) / cols)
            y = iy0 + (iy1 - iy0) * ((row + 0.5) / rows)
            return x, y

        xp, yp = p.get("x_percent"), p.get("y_percent")
        if xp in (None, "") or yp in (None, ""):
            return None
        x = width * _f(xp) / 100.0
        y = height * _f(yp) / 100.0
        if body is not None:
            bx0, by0, bx1, by1 = body
            inset = 14
            x = min(max(x, bx0 + inset), bx1 - inset)
            y = min(max(y, by0 + inset), by1 - inset)
        return x, y

    def _point(x: float, y: float, r: float, caption: str, fill, outline, text_color) -> None:
        if fill is None:
            draw.ellipse([x - r, y - r, x + r, y + r], outline=outline, width=2)
        else:
            draw.ellipse([x - r, y - r, x + r, y + r], fill=fill, outline=outline, width=1)
        if not caption:
            return
        boxes.append((x - r, y - r, x + r, y + r))
        lx, ly = _place_label(draw, x, y, r, caption, font_tiny, boxes)
        draw.text((lx, ly), caption, fill=text_color, font=font_tiny)

    if layer == "uzt":
        color = (40, 160, 70)
        for p in overlays.get("uzt_points") or []:
            pos = _xy(p)
            if pos is None:
                continue
            _point(pos[0], pos[1], 5, str(p.get("n") or ""), color, (20, 90, 40), (20, 80, 30))
        return
    if layer == "hardness":
        color = (40, 160, 70)
        for p in overlays.get("hardness_points") or []:
            pos = _xy(p)
            if pos is None:
                continue
            _point(
                pos[0],
                pos[1],
                5,
                str(p.get("n") or p.get("label") or ""),
                color,
                (20, 90, 40),
                (20, 80, 30),
            )
        for p in (overlays.get("hardness_T") or []) + (overlays.get("hardness_U") or []):
            pos = _xy(p)
            if pos is None:
                continue
            _point(pos[0], pos[1], 7, str(p.get("label") or ""), None, color, color)
        return
    if layer in ("uzk", "mpk"):
        zone_color = (0, 190, 210) if layer == "uzk" else (50, 190, 70)
        zones = overlays.get("uzk_zones" if layer == "uzk" else "mpk_zones") or []
        highlight_all_w = any(str(z.get("kind")) == "all_welds" for z in zones)
        highlight_all_n = any(str(z.get("kind")) == "all_nozzles" for z in zones)
        labels = {str(z.get("weld_label") or "") for z in zones if z.get("weld_label")}
        nzz_labs = {str(z.get("nozzle_label") or "") for z in zones if z.get("nozzle_label")}
        for lab, (xa, ya, xb, yb) in weld_segs.items():
            if highlight_all_w or lab in labels:
                draw.line([(xa, ya), (xb, yb)], fill=zone_color, width=6)
        for lab, (nx, ny) in nozzle_xy.items():
            if highlight_all_n or lab in nzz_labs:
                draw.ellipse([nx - 16, ny - 16, nx + 16, ny + 16], outline=zone_color, width=4)
        return


def _draw_compressor(draw: ImageDraw.ImageDraw, layout: Dict[str, Any], ink: Tuple[int, int, int], accent: Tuple[int, int, int]):
    x0, y0, x1, y1 = layout["body"]
    cx = (x0 + x1) / 2
    cy = (y0 + y1) / 2
    bw = x1 - x0
    bh = y1 - y0
    draw.rectangle([x0, y0 + bh * 0.25, x1, y1], outline=ink, width=3)
    r = min(bw, bh) * 0.18
    for frac in (0.28, 0.55, 0.78):
        cx_i = x0 + bw * frac
        draw.ellipse([cx_i - r, cy - r * 1.4, cx_i + r, cy + r * 0.6], outline=accent, width=2)
        draw.line([(cx_i, cy - r * 1.4), (cx_i, y0 + bh * 0.1)], fill=accent, width=2)
    draw.line([(x0 - 10, y1), (x1 + 10, y1)], fill=ink, width=3)
    draw.text((cx - 50, y0 - 8), "Компрессор", fill=ink)


def _draw_crane(draw: ImageDraw.ImageDraw, layout: Dict[str, Any], ink: Tuple[int, int, int], accent: Tuple[int, int, int]):
    x0, y0, x1, y1 = layout["body"]
    cx = (x0 + x1) / 2
    tower_w = (x1 - x0) * 0.18
    draw.rectangle([cx - tower_w / 2, y0, cx + tower_w / 2, y1], outline=ink, width=3)
    boom_y = y0 + (y1 - y0) * 0.22
    draw.line([(cx, boom_y), (x1 + 40, boom_y - 20)], fill=accent, width=4)
    draw.line([(x1 + 40, boom_y - 20), (x1 + 40, boom_y + 60)], fill=accent, width=2)
    draw.arc([x1 + 32, boom_y + 55, x1 + 48, boom_y + 75], 0, 360, fill=accent, width=2)
    draw.polygon(
        [(cx - tower_w, y1), (cx + tower_w, y1), (cx + tower_w * 1.4, y1 + 25), (cx - tower_w * 1.4, y1 + 25)],
        outline=ink,
    )
    draw.text((cx - 30, y0 - 22), "ГПМ", fill=ink)


def render_vessel_scheme(
    raw_geometry: Optional[Dict[str, Any]] = None,
    *,
    width: int = 1200,
    height: int = 900,
    scheme_layer: Optional[str] = None,
    overlays: Optional[Dict[str, Any]] = None,
) -> Tuple[bytes, Dict[str, Any], List[Dict[str, Any]]]:
    """Рендер PNG. Возвращает (png_bytes, geometry, suggested_points)."""
    geo = normalize_geometry(raw_geometry)
    kind = geo.get("equipment_kind") or "vessel"
    family = geo.get("scheme_family") or resolve_family(kind)
    layer = str(scheme_layer or geo.get("scheme_layer") or "vik").lower()
    geo["scheme_layer"] = layer
    if family == FAMILY_VESSEL_DEV and height < 1050:
        height = 1050
    if family == FAMILY_TANK and height < 900:
        height = 900
    try:
        from scheme_ndt_overlays import layer_title as _layer_title

        if layer in ("vik", "uzt", "hardness", "uzk", "mpk"):
            geo["title"] = _layer_title(layer, equipment_kind=kind)
    except Exception:
        pass

    img = Image.new("RGB", (width, height), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    ink = (30, 30, 30)
    accent = (30, 80, 160)
    weld_color = (180, 40, 40)
    font_sm = _font(13)
    font_title = _font(16)
    font_tiny = _font(11)

    draw.rectangle([8, 8, width - 9, height - 9], outline=(180, 180, 180), width=1)
    title = geo.get("title") or kind_title(kind)
    draw.text((24, 12), title, fill=ink, font=font_title)

    suggested: List[Dict[str, Any]] = []
    family_kw = dict(
        width=width,
        height=height,
        ink=ink,
        accent=accent,
        weld_color=weld_color,
        font_sm=font_sm,
        font_tiny=font_tiny,
        suggested=suggested,
    )

    if family == FAMILY_PIPELINE:
        draw_pipeline_family(draw, geo, **family_kw)
    elif family == FAMILY_TANK:
        draw_tank_family(draw, geo, **family_kw)
    elif family == FAMILY_TOWER:
        draw_tower_family(draw, geo, **family_kw)
    elif family == FAMILY_BOILER:
        draw_boiler_family(draw, geo, **family_kw)
    elif family == FAMILY_MACHINERY:
        draw_machinery_family(draw, geo, **family_kw)
    elif family == FAMILY_ELECTRICAL:
        draw_electrical_family(draw, geo, **family_kw)
    elif family == FAMILY_VALVE:
        draw_valve_family(draw, geo, **family_kw)
    elif family == FAMILY_CRANE:
        draw_crane_family(draw, geo, **family_kw)
    elif family == FAMILY_STATION:
        draw_station_family(draw, geo, **family_kw)
    elif family == FAMILY_GENERIC:
        draw_generic_family(draw, geo, **family_kw)
    elif family == FAMILY_VESSEL_DEV:
        layout = _layout_development(
            geo, width, height, margin_bottom=legend_height_px(geo, overlays or {}, layer) + 24
        )
        x0, y0, x1, y1 = layout["body"]
        n_shell = max(1, int(geo.get("shell_count") or 1))
        # Занятые подписями места: патрубки, швы и размеры регистрируются здесь,
        # чтобы номера точек УЗТ/твёрдости на них не наезжали.
        label_boxes: List[Tuple[float, float, float, float]] = []

        def _mark_text(tx: float, ty: float, text: str, fnt) -> None:
            try:
                tb = draw.textbbox((tx, ty), text, font=fnt)
            except Exception:
                tb = (tx, ty, tx + len(text) * 6.0, ty + 11.0)
            label_boxes.append((tb[0] - 1, tb[1] - 1, tb[2] + 1, tb[3] + 1))

        heads = geo.get("heads") or []
        h0 = heads[0] if heads else {}
        h1 = heads[1] if len(heads) > 1 else {}
        top_cx, top_cy, top_r = layout["head_top"]
        bot_cx, bot_cy, bot_r = layout["head_bottom"]
        _draw_full_head_circle(
            draw, top_cx, top_cy, top_r, ink,
            str(h0.get("label") or ("Левое днище" if layout.get("orient") == "horizontal" else "Верхнее днище")),
            font_tiny,
            weld_color=weld_color,
        )
        _draw_full_head_circle(
            draw, bot_cx, bot_cy, bot_r, ink,
            str(h1.get("label") or ("Правое днище" if layout.get("orient") == "horizontal" else "Нижнее днище")),
            font_tiny,
            weld_color=weld_color,
        )
        dims = geo.get("dimensions") if isinstance(geo.get("dimensions"), dict) else {}
        head_d_mm = dims.get("head_diameter_mm")
        if head_d_mm:
            draw.text((top_cx - 28, top_cy + top_r + 4), f"Ø{head_d_mm:g}", fill=ink, font=font_tiny)
            draw.text((bot_cx - 28, bot_cy + bot_r + 4), f"Ø{head_d_mm:g}", fill=ink, font=font_tiny)

        draw.rectangle([x0, y0, x1, y1], outline=ink, width=3)
        draw.text((x0 + 8, y0 + 6), "Корпус", fill=(90, 90, 90), font=font_tiny)
        horiz = layout.get("orient") == "horizontal"
        weld_segs: Dict[str, Tuple[float, float, float, float]] = {}

        for w in geo.get("welds") or []:
            if str(w.get("kind")) != "circumferential":
                continue
            pos = _f(w.get("position"), 0.0)
            label = str(w.get("label") or "")
            if horiz:
                x = x0 + (x1 - x0) * pos
                draw.line([(x, y0), (x, y1)], fill=weld_color, width=2)
                draw.text((x - 8, y0 - 16), label, fill=weld_color, font=font_sm)
                _mark_text(x - 8, y0 - 16, label, font_sm)
                weld_segs[label] = (x, y0, x, y1)
                px, py = x, y0 - 10
            else:
                y = y0 + (y1 - y0) * pos
                draw.line([(x0, y), (x1, y)], fill=weld_color, width=2)
                if 0.02 < pos < 0.98:
                    draw.text((x1 + 6, y - 8), label, fill=weld_color, font=font_sm)
                    _mark_text(x1 + 6, y - 8, label, font_sm)
                else:
                    ly = y - 8 if pos < 0.5 else y
                    draw.text((x1 + 6, ly), label, fill=weld_color, font=font_tiny)
                    _mark_text(x1 + 6, ly, label, font_tiny)
                weld_segs[label] = (x0, y, x1, y)
                px, py = x1 + 10, y
            suggested.append(
                {
                    "label": label,
                    "point_type": "weld",
                    "x_percent": round(px / width * 100, 2),
                    "y_percent": round(py / height * 100, 2),
                    "notes": "circumferential",
                }
            )

        for w in geo.get("welds") or []:
            if str(w.get("kind")) != "longitudinal":
                continue
            circ = _f(w.get("position"), 0.5)
            span_start = _f(w.get("span_start"), 0.0)
            span_end = _f(w.get("span_end"), 1.0)
            label = str(w.get("label") or "")
            if horiz:
                y = y0 + (y1 - y0) * _clamp01(circ, 0.04, 0.96)
                xa = x0 + (x1 - x0) * span_start
                xb = x0 + (x1 - x0) * span_end
                pad = max(2, abs(xb - xa) * 0.02)
                draw.line([(xa + pad, y), (xb - pad, y)], fill=weld_color, width=2)
                lx, ly = (xa + xb) / 2, y + 4
                weld_segs[label] = (xa, y, xb, y)
            else:
                x = x0 + (x1 - x0) * _clamp01(circ, 0.04, 0.96)
                ya = y0 + (y1 - y0) * span_start
                yb = y0 + (y1 - y0) * span_end
                pad = max(2, (yb - ya) * 0.02)
                draw.line([(x, ya + pad), (x, yb - pad)], fill=weld_color, width=2)
                lx, ly = x + 4, (ya + yb) / 2 - 6
                weld_segs[label] = (x, ya, x, yb)
            draw.text((lx, ly), label, fill=weld_color, font=font_sm)
            _mark_text(lx, ly, label, font_sm)
            suggested.append(
                {
                    "label": label,
                    "point_type": "weld",
                    "x_percent": round(lx / width * 100, 2),
                    "y_percent": round(ly / height * 100, 2),
                    "notes": "longitudinal",
                }
            )

        lengths = dims.get("shell_lengths_mm") if isinstance(dims.get("shell_lengths_mm"), list) else []
        for s in range(n_shell):
            frac = (s + 0.5) / n_shell
            lab = f"Об.{s + 1}"
            if s < len(lengths) and lengths[s]:
                lab = f"{lab} {lengths[s]:g}"
            if horiz:
                xm = x0 + (x1 - x0) * frac
                draw.text((xm - 18, y1 + 6), lab, fill=(100, 100, 100), font=font_tiny)
                _mark_text(xm - 18, y1 + 6, lab, font_tiny)
            else:
                ym = y0 + (y1 - y0) * frac
                draw.text((x0 - 78, ym - 6), lab, fill=(100, 100, 100), font=font_tiny)
                _mark_text(x0 - 78, ym - 6, lab, font_tiny)
        body_len = dims.get("body_length_mm")
        if body_len:
            if horiz:
                draw.text(((x0 + x1) / 2 - 30, y1 + 22), f"L={body_len:g}", fill=ink, font=font_tiny)
            else:
                # справа от корпуса идут метки кольцевых швов К1…Кn — уводим влево
                draw.text((x0 - 78, y1 + 6), f"L={body_len:g}", fill=ink, font=font_tiny)

        nozzle_xy: Dict[str, Tuple[float, float]] = {}
        for n in geo.get("nozzles") or []:
            place = str(n.get("place") or "body")
            label = str(n.get("label") or n.get("id") or "")
            dn = n.get("dn")
            if place in ("head_top", "head_left"):
                circ = _f(n.get("circ"), 0.5)
                ang = -math.pi / 2 + circ * 2 * math.pi
                rr = top_r * 0.55
                nx = top_cx + rr * math.cos(ang)
                ny = top_cy + rr * math.sin(ang)
            elif place in ("head_bottom", "head_right"):
                circ = _f(n.get("circ"), 0.5)
                ang = -math.pi / 2 + circ * 2 * math.pi
                rr = bot_r * 0.55
                nx = bot_cx + rr * math.cos(ang)
                ny = bot_cy + rr * math.sin(ang)
            else:
                axial = _f(n.get("axial", n.get("position")), 0.5)
                circ = _f(n.get("circ"), 0.55)
                if horiz:
                    nx = x0 + (x1 - x0) * axial
                    ny = y0 + (y1 - y0) * circ
                else:
                    nx = x0 + (x1 - x0) * circ
                    ny = y0 + (y1 - y0) * axial
            _draw_nozzle_on_dev(draw, nx, ny, dn, label, accent, font_tiny, label_boxes)
            nozzle_xy[label] = (nx, ny)
            suggested.append(
                {
                    "label": label,
                    "point_type": "nozzle",
                    "x_percent": round(nx / width * 100, 2),
                    "y_percent": round(ny / height * 100, 2),
                    "notes": f"DN{dn}" if dn not in (None, "") else "",
                }
            )
        _draw_layer_overlays(
            draw,
            overlays or {},
            layer,
            width=width,
            height=height,
            weld_segs=weld_segs,
            nozzle_xy=nozzle_xy,
            font_tiny=font_tiny,
            taken=label_boxes,
            body=(x0, y0, x1, y1),
        )
    else:
        draw_generic_family(draw, geo, **family_kw)

    if family != FAMILY_VESSEL_DEV:
        _draw_layer_overlays(
            draw,
            overlays or {},
            layer,
            width=width,
            height=height,
            weld_segs={},
            nozzle_xy={},
            font_tiny=font_tiny,
        )

    lines = _build_legend_lines(geo, overlays or {}, layer)
    k_labs = [str(w.get("label") or "") for w in (geo.get("welds") or []) if str(w.get("kind")) == "circumferential"]
    p_labs = [str(w.get("label") or "") for w in (geo.get("welds") or []) if str(w.get("kind")) == "longitudinal"]
    _draw_legend(draw, lines, width=width, height=height, weld_color=weld_color, accent=accent, font=font_tiny)

    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue(), geo, suggested


def _nozzle_legend_lines(nozzles: List[Any]) -> List[str]:
    """Патрубки с одинаковым назначением объединяются в «Пт3–Пт5 — люк-лаз»."""
    items: List[Tuple[str, str, str]] = []
    for n in nozzles or []:
        if not isinstance(n, dict):
            continue
        lab = str(n.get("label") or "").strip()
        if not lab:
            continue
        purpose = str(n.get("purpose") or "").strip()
        dn = n.get("dn")
        items.append((lab, purpose, "" if dn in (None, "") else f"Ø{dn}"))

    lines: List[str] = []
    i = 0
    while i < len(items):
        lab, purpose, dn = items[i]
        j = i
        while (
            j + 1 < len(items)
            and items[j + 1][1] == purpose
            and items[j + 1][2] == dn
            and purpose
        ):
            j += 1
        head = lab if j == i else f"{lab}–{items[j][0]}"
        bit = f"{head} — {purpose}" if purpose else head
        if dn:
            bit = f"{bit} {dn}"
        lines.append(bit)
        i = j + 1
    return lines


def _build_legend_lines(geo: Dict[str, Any], ov: Dict[str, Any], layer: str) -> List[str]:
    lines: List[str] = []
    k_labs = [str(w.get("label") or "") for w in (geo.get("welds") or []) if str(w.get("kind")) == "circumferential"]
    p_labs = [str(w.get("label") or "") for w in (geo.get("welds") or []) if str(w.get("kind")) == "longitudinal"]
    if k_labs:
        lines.append("Кольцевые швы: " + ", ".join(k_labs))
    if p_labs:
        lines.append("Продольные швы: " + ", ".join(p_labs))
    lines.extend(_nozzle_legend_lines(geo.get("nozzles") or []))
    if layer == "uzt":
        pts = ov.get("uzt_points") or []
        nmax = max((int(p.get("n") or 0) for p in pts), default=len(pts))
        if nmax:
            lines.append(f"1 – {nmax} — точки измерений")
    elif layer == "hardness":
        bp = ov.get("hardness_points") or []
        tzs = ov.get("hardness_T") or []
        uzs = ov.get("hardness_U") or []
        if bp:
            lines.append(f"1 – {len(bp)} — точки измерений")
        if tzs:
            lines.append(f"Т1 – {tzs[-1].get('label') or f'Т{len(tzs)}'} — участки в местах присоединения штуцеров")
        if uzs:
            lines.append(f"У1 – {uzs[-1].get('label') or f'У{len(uzs)}'} — участки на кольцевых и продольных швах")
    elif layer == "uzk":
        lines.append("Зона ультразвукового контроля сварных соединений элементов сосуда")
    elif layer == "mpk":
        lines.append("Зона магнитопорошкового контроля сварных соединений элементов сосуда")
    return lines


def legend_height_px(geo: Dict[str, Any], overlays: Dict[str, Any], layer: str) -> int:
    """Сколько места снизу зарезервировать под легенду (см. _draw_legend)."""
    n = len(_build_legend_lines(geo, overlays or {}, layer))
    rows = math.ceil(n / _LEGEND_COLUMNS) if n else 0
    return int(min(_LEGEND_MAX_H, 24 + rows * _LEGEND_LINE_H))


def _draw_legend(
    draw: ImageDraw.ImageDraw,
    lines: List[str],
    *,
    width: int,
    height: int,
    weld_color: Tuple[int, int, int],
    accent: Tuple[int, int, int],
    font,
) -> None:
    """Легенда целиком: швы + все патрубки, в колонках, без обрезки."""
    if not lines:
        return
    weld_rows = sum(1 for ln in lines[:2] if ln.startswith(("Кольцевые швы", "Продольные швы")))
    rows = math.ceil(len(lines) / _LEGEND_COLUMNS)
    col_w = (width - 48) / _LEGEND_COLUMNS
    legend_y = height - min(_LEGEND_MAX_H, 24 + rows * _LEGEND_LINE_H) + 6

    for i, line in enumerate(lines):
        col, row = divmod(i, rows)
        x = 24 + col * col_w
        y = legend_y + row * _LEGEND_LINE_H
        if y > height - 16:
            continue
        draw.text((x, y), line, fill=weld_color if i < weld_rows else accent, font=font)
