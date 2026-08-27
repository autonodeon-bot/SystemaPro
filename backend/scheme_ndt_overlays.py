"""Слои карт контроля (ВИК / УЗТ / ТК / УЗК / МПК) для всех форм ТО.

Одна геометрия конструктора + данные обследования → отдельные PNG
с заголовком, легендой, точками и зонами — как в эталонных схемах.
"""
from __future__ import annotations

import io
import logging
import math
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from PIL import Image, ImageDraw, ImageFont

logger = logging.getLogger(__name__)

LAYER_VIK = "vik"
LAYER_UZT = "uzt"
LAYER_HARDNESS = "hardness"
LAYER_UZK = "uzk"
LAYER_MPK = "mpk"

LAYER_ORDER = (LAYER_VIK, LAYER_UZT, LAYER_HARDNESS, LAYER_UZK, LAYER_MPK)

LAYER_TITLES: Dict[str, str] = {
    LAYER_VIK: "Карта проведения визуального и измерительного контроля (наружная поверхность).",
    LAYER_UZT: "Схема проведения ультразвуковой толщинометрии элементов сосуда",
    LAYER_HARDNESS: "Схема измерения твердости металла элементов сосуда",
    LAYER_UZK: "Схема проведения ультразвукового контроля сварных соединений элементов сосуда",
    LAYER_MPK: "Схема проведения магнитопорошкового контроля сварных соединений элементов сосуда",
}

# Подписи якорей в шаблоне Word → слой
ANCHOR_LAYERS = (
    LAYER_VIK,
    LAYER_UZT,
    LAYER_HARDNESS,
    LAYER_UZK,
    LAYER_MPK,
)

UZT_MAX_POINTS = 150
HARDNESS_BASE_MAX = 25
HARDNESS_T_MAX = 20
HARDNESS_U_MAX = 30
HARDNESS_POINTS_PER_ZONE = 5


def layer_title(layer: str, *, equipment_kind: str = "vessel") -> str:
    """Заголовок карты. Для не-сосудов «элементов сосуда» → «элементов оборудования»."""
    title = LAYER_TITLES.get(layer) or "Карта контроля"
    kind = str(equipment_kind or "vessel").lower()
    if kind not in ("vessel", "gas_separator", "oil_settler", "receiver", "pig_trap", "air_cooler", ""):
        title = title.replace("элементов сосуда", "элементов оборудования")
        title = title.replace("элемента сосуда", "элемента оборудования")
    return title


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


def extract_geometry(data: Dict[str, Any]) -> Dict[str, Any]:
    """Геометрия конструктора из inspection.data."""
    geo: Dict[str, Any] = {}
    base = data.get("base_vessel_scheme")
    if isinstance(base, dict):
        raw = base.get("geometry")
        if isinstance(raw, dict):
            geo = dict(raw)
        if base.get("orientation") and not geo.get("orientation"):
            geo["orientation"] = base.get("orientation")
    if data.get("orientation") and not geo.get("orientation"):
        geo["orientation"] = data.get("orientation")
    if data.get("scheme_geometry") and isinstance(data.get("scheme_geometry"), dict):
        merged = dict(data["scheme_geometry"])
        merged.update(geo)
        geo = merged
    dims = _dimensions_from_elements(data)
    if dims:
        existing = geo.get("dimensions") if isinstance(geo.get("dimensions"), dict) else {}
        geo["dimensions"] = {**dims, **existing}
    return geo


def _dimensions_from_elements(data: Dict[str, Any]) -> Dict[str, Any]:
    elements = data.get("vessel_elements") or data.get("elements") or []
    if not isinstance(elements, list):
        return {}
    shell_lengths: List[float] = []
    head_d = None
    body_len = None
    for el in elements:
        if not isinstance(el, dict):
            continue
        name = str(el.get("name") or el.get("element_name") or "").lower()
        length = _f(el.get("length_mm") or el.get("length") or el.get("height"), 0)
        diam = _f(
            el.get("diameter_mm") or el.get("inner_diameter") or el.get("diameter"),
            0,
        )
        if "обечай" in name or "корпус" in name:
            if length:
                shell_lengths.append(length)
            if diam and head_d is None:
                head_d = diam
        if "днищ" in name and diam:
            head_d = head_d or diam
    if shell_lengths:
        body_len = sum(shell_lengths)
    passport_d = _f(data.get("diameter") or data.get("inner_diameter"), 0)
    passport_h = _f(data.get("shell_length") or data.get("height") or data.get("length"), 0)
    out: Dict[str, Any] = {}
    if shell_lengths:
        out["shell_lengths_mm"] = shell_lengths
    if body_len:
        out["body_length_mm"] = body_len
    elif passport_h:
        out["body_length_mm"] = passport_h
    if head_d or passport_d:
        out["head_diameter_mm"] = head_d or passport_d
    return out


def collect_scheme_overlays(data: Dict[str, Any]) -> Dict[str, Any]:
    """Точки, участки и зоны контроля из обследования."""
    overlays: Dict[str, Any] = {
        "uzt_points": _collect_uzt_points(data),
        "hardness_points": _collect_hardness_base_points(data),
        "hardness_T": _collect_hardness_zones(data, prefixes=("Т", "T"), max_n=HARDNESS_T_MAX),
        "hardness_U": _collect_hardness_zones(data, prefixes=("У", "U"), max_n=HARDNESS_U_MAX),
        "uzk_zones": _collect_weld_zones(data, methods=("UZK", "УЗК")),
        "mpk_zones": _collect_weld_zones(data, methods=("MPK", "МПК", "МПД", "MK", "МК", "MPI")),
        "dimensions": _dimensions_from_elements(data),
    }
    return overlays


def _collect_uzt_points(data: Dict[str, Any]) -> List[Dict[str, Any]]:
    src: List[Dict[str, Any]] = []
    raw = data.get("thickness_measurements") or data.get("thicknessMeasurements") or []
    if isinstance(raw, list):
        src.extend(p for p in raw if isinstance(p, dict))
    for sch in data.get("uzt_schemes") or []:
        if isinstance(sch, dict):
            for m in sch.get("measurements") or []:
                if isinstance(m, dict):
                    src.append(m)
    points: List[Dict[str, Any]] = []
    for i, p in enumerate(src[:UZT_MAX_POINTS]):
        n_raw = p.get("section_number") or p.get("point_number") or p.get("number") or p.get("point")
        try:
            n = int(str(n_raw).lstrip("TТtтUuУу"))
        except (TypeError, ValueError):
            n = i + 1
        xp = p.get("x_percent")
        yp = p.get("y_percent")
        points.append(
            {
                "n": n,
                "x_percent": _f(xp, 0) if xp not in (None, "") else None,
                "y_percent": _f(yp, 0) if yp not in (None, "") else None,
                "element": str(p.get("element") or p.get("element_name") or p.get("location") or ""),
            }
        )
    return _autoplace_missing(points, max_n=UZT_MAX_POINTS)


def _collect_hardness_base_points(data: Dict[str, Any]) -> List[Dict[str, Any]]:
    tests = data.get("hardness_tests") or []
    if not isinstance(tests, list):
        return []
    points: List[Dict[str, Any]] = []
    for i, t in enumerate(tests):
        if not isinstance(t, dict):
            continue
        label = str(t.get("point_number") or t.get("area_number") or t.get("weld_number") or "")
        upper = label.upper().replace("У", "U")
        if upper.startswith("T") or upper.startswith("U") or label.upper().startswith("У"):
            continue
        xp = t.get("x_percent")
        yp = t.get("y_percent")
        points.append(
            {
                "n": i + 1,
                "x_percent": _f(xp, 0) if xp not in (None, "") else None,
                "y_percent": _f(yp, 0) if yp not in (None, "") else None,
                "label": str(i + 1),
            }
        )
        if len(points) >= HARDNESS_BASE_MAX:
            break
    return _autoplace_missing(points, max_n=HARDNESS_BASE_MAX, y0=0.28, y1=0.72)


def _collect_hardness_zones(
    data: Dict[str, Any],
    *,
    prefixes: Sequence[str],
    max_n: int,
) -> List[Dict[str, Any]]:
    tests = data.get("hardness_tests") or []
    if not isinstance(tests, list):
        return []
    prefs = tuple(p.upper() for p in prefixes)
    zones: List[Dict[str, Any]] = []
    for t in tests:
        if not isinstance(t, dict):
            continue
        label = str(
            t.get("area_number") or t.get("point_number") or t.get("weld_number") or t.get("zone") or ""
        ).strip()
        up = label.upper().replace("У", "U")
        if not any(up.startswith(p) for p in prefs):
            continue
        xp = t.get("x_percent")
        yp = t.get("y_percent")
        zones.append(
            {
                "label": label or f"{prefixes[0]}{len(zones) + 1}",
                "x_percent": _f(xp, 0) if xp not in (None, "") else None,
                "y_percent": _f(yp, 0) if yp not in (None, "") else None,
            }
        )
        if len(zones) >= max_n:
            break
    return _autoplace_missing(zones, max_n=max_n, y0=0.22, y1=0.78, as_label=True)


def _collect_weld_zones(data: Dict[str, Any], methods: Sequence[str]) -> List[Dict[str, Any]]:
    methods_u = {m.upper() for m in methods}
    items: List[Dict[str, Any]] = []
    welds = data.get("weld_inspections") or data.get("uzk_results") or []
    if isinstance(welds, list):
        for w in welds:
            if not isinstance(w, dict):
                continue
            method = str(w.get("control_method") or w.get("method") or "").upper()
            if methods_u and method and method not in methods_u:
                # УЗК-зона: пустой метод тоже берём, МПК — только явный
                if "UZK" in methods_u or "УЗК" in methods_u:
                    if method in ("MPK", "МПК", "МПД", "MK", "МК"):
                        continue
                else:
                    continue
            lab = str(w.get("weld_number") or w.get("joint") or w.get("seam") or "").strip()
            if lab:
                items.append({"weld_label": lab, "kind": _weld_kind_from_label(lab)})
            nzz = str(w.get("nozzle") or w.get("nozzle_label") or "").strip()
            if nzz:
                items.append({"nozzle_label": nzz, "kind": "nozzle"})
    # Если зон нет — подсветить все швы и патрубки (как на эталоне «по всей протяжённости»)
    if not items:
        items.append({"kind": "all_welds"})
        items.append({"kind": "all_nozzles"})
    return items


def _weld_kind_from_label(label: str) -> str:
    u = (label or "").upper().replace("П", "P").replace("К", "K")
    if u.startswith("K"):
        return "circumferential"
    if u.startswith("P"):
        return "longitudinal"
    return "weld"


def _autoplace_missing(
    points: List[Dict[str, Any]],
    *,
    max_n: int,
    y0: float = 0.26,
    y1: float = 0.78,
    as_label: bool = False,
) -> List[Dict[str, Any]]:
    missing = [p for p in points if p.get("x_percent") in (None, 0) and p.get("y_percent") in (None, 0)]
    # 0,0 почти наверняка «не задано», если обе координаты пустые/ноль
    placed = [p for p in points if p not in missing]
    n_miss = len(missing)
    if n_miss == 0:
        return points[:max_n]
    cols = max(4, int(math.ceil(math.sqrt(n_miss * 1.6))))
    rows = max(1, int(math.ceil(n_miss / cols)))
    for i, p in enumerate(missing):
        col = i % cols
        row = i // cols
        p["x_percent"] = round(18 + (64 * (col + 0.5) / cols), 2)
        p["y_percent"] = round((y0 + (y1 - y0) * ((row + 0.5) / rows)) * 100, 2)
        if as_label and not p.get("label"):
            p["label"] = str(i + 1)
    return (placed + missing)[:max_n]


def render_hardness_detail_t(max_label: str = "Т20") -> bytes:
    """Эскиз: штуцер + обечайка, 5 точек (Т1–Тn)."""
    return _render_hardness_detail(
        title=f"Схема измерения твердости металла на участках Т1 – {max_label}.",
        mode="nozzle",
    )


def render_hardness_detail_u(max_label: str = "У30") -> bytes:
    """Эскиз: стыковой шов обечаек, 5 точек (У1–Уn)."""
    return _render_hardness_detail(
        title=f"Схема измерения твердости металла на участках У1 – {max_label}.",
        mode="butt",
    )


def _render_hardness_detail(*, title: str, mode: str) -> bytes:
    w, h = 900, 520
    img = Image.new("RGB", (w, h), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    ink = (30, 30, 30)
    green = (40, 160, 70)
    font = _font(16)
    font_sm = _font(13)
    draw.rectangle([8, 8, w - 9, h - 9], outline=(180, 180, 180), width=1)
    draw.text((24, 16), title, fill=ink, font=font)

    dots: List[Tuple[float, float]] = []
    if mode == "nozzle":
        # горизонтальная обечайка
        draw.rectangle([80, 280, 820, 430], outline=ink, width=3)
        draw.text((90, 440), "Обечайка корпуса", fill=ink, font=font_sm)
        # штуцер
        draw.rectangle([380, 90, 520, 282], outline=ink, width=3)
        draw.line([(450, 90), (450, 430)], fill=(160, 160, 160), width=1)
        draw.text((530, 140), "Штуцер", fill=ink, font=font_sm)
        # катет шва
        draw.polygon([(380, 282), (360, 282), (380, 250)], outline=ink)
        draw.polygon([(520, 282), (540, 282), (520, 250)], outline=ink)
        dots = [(700, 300), (580, 300), (450, 270), (450, 200), (450, 130)]
    else:
        draw.rectangle([80, 180, 360, 380], outline=ink, width=3)
        draw.rectangle([540, 180, 820, 380], outline=ink, width=3)
        draw.ellipse([350, 175, 550, 385], outline=ink, width=3)
        draw.line([(80, 280), (820, 280)], fill=(160, 160, 160), width=1)
        draw.text((120, 400), "Обечайка корпуса", fill=ink, font=font_sm)
        draw.text((560, 400), "Обечайка корпуса/днище", fill=ink, font=font_sm)
        dots = [(180, 280), (280, 280), (450, 280), (620, 280), (720, 280)]

    for i, (x, y) in enumerate(dots, start=1):
        r = 9
        draw.ellipse([x - r, y - r, x + r, y + r], fill=green, outline=ink, width=1)
        draw.text((x + 12, y - 10), str(i), fill=ink, font=font)

    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def png_to_tempfile(png: bytes, suffix: str = ".png") -> str:
    fd, path = tempfile.mkstemp(suffix=suffix)
    try:
        import os

        os.close(fd)
        Path(path).write_bytes(png)
    except Exception:
        logger.exception("Не удалось записать временную схему")
    return path


def render_all_layer_pngs(
    data: Dict[str, Any],
    *,
    width: int = 1400,
    height: int = 1050,
) -> List[Dict[str, Any]]:
    """Список слоёв: layer, title, png_bytes, extra_pngs[]."""
    from vessel_scheme_renderer import render_vessel_scheme

    geo = extract_geometry(data)
    overlays = collect_scheme_overlays(data)
    kind = str(geo.get("equipment_kind") or data.get("equipment_kind") or "vessel")
    items: List[Dict[str, Any]] = []
    for layer in LAYER_ORDER:
        title = layer_title(layer, equipment_kind=kind)
        geo_layer = dict(geo)
        geo_layer["title"] = title
        geo_layer["scheme_layer"] = layer
        try:
            png, _, _ = render_vessel_scheme(
                geo_layer,
                width=width,
                height=height,
                scheme_layer=layer,
                overlays=overlays,
            )
        except Exception:
            logger.exception("Рендер слоя схемы %s", layer)
            continue
        extra: List[Tuple[str, bytes]] = []
        if layer == LAYER_HARDNESS:
            t_zones = overlays.get("hardness_T") or []
            u_zones = overlays.get("hardness_U") or []
            t_max = t_zones[-1]["label"] if t_zones else "Т20"
            u_max = u_zones[-1]["label"] if u_zones else "У30"
            extra.append((f"Схема измерения твердости металла на участках Т1 – {t_max}", render_hardness_detail_t(str(t_max))))
            extra.append((f"Схема измерения твердости металла на участках У1 – {u_max}", render_hardness_detail_u(str(u_max))))
        items.append({"layer": layer, "title": title, "png": png, "extra": extra})
    return items
