"""Отрисовка семейств карт контроля (кроме развёртки сосуда).

Единый стиль: рамка, заголовок, легенда, точки контроля.
"""
from __future__ import annotations

from typing import Any, Dict, List, Tuple

from PIL import ImageDraw

Point = Tuple[float, float]


def _f(v: Any, default: float = 0.0) -> float:
    try:
        if v is None or v == "":
            return default
        return float(str(v).replace(",", "."))
    except (TypeError, ValueError):
        return default


def _add_point(
    suggested: List[Dict[str, Any]],
    label: str,
    x: float,
    y: float,
    width: int,
    height: int,
    ptype: str,
    notes: str = "",
) -> None:
    suggested.append(
        {
            "label": label,
            "point_type": ptype,
            "x_percent": round(x / width * 100, 2),
            "y_percent": round(y / height * 100, 2),
            "notes": notes,
        }
    )


def draw_pipeline_family(
    draw: ImageDraw.ImageDraw,
    geo: Dict[str, Any],
    *,
    width: int,
    height: int,
    ink: Tuple[int, int, int],
    accent: Tuple[int, int, int],
    weld_color: Tuple[int, int, int],
    font_sm,
    font_tiny,
    suggested: List[Dict[str, Any]],
) -> None:
    kind = geo.get("equipment_kind") or "pipeline"
    n = max(1, int(geo.get("shell_count") or 4))
    margin_x, margin_y = 80, 90
    y = height * 0.42
    h = min(70, height * 0.1)
    x0, x1 = margin_x, width - margin_x
    draw.rectangle([x0, y - h / 2, x1, y + h / 2], outline=ink, width=3)
    # фланцы
    draw.rectangle([x0 - 10, y - h / 2 - 8, x0 + 2, y + h / 2 + 8], outline=ink, width=2)
    draw.rectangle([x1 - 2, y - h / 2 - 8, x1 + 10, y + h / 2 + 8], outline=ink, width=2)

    labels = {
        "underground_pipeline": "Подземный трубопровод",
        "aboveground_pipeline": "Надземный газопровод",
        "main_pipeline": "Магистральный газопровод",
        "gas_collector": "Коллектор / шлейф",
        "pipeline_crossing": "Переход (дорога / ж.д.)",
        "wellhead_piping": "Обвязка устья",
        "gas_pipeline_gx": "Газопровод ГХ",
    }
    draw.text((x0, y - h / 2 - 28), labels.get(kind, "Трубопровод"), fill=ink, font=font_sm)

    # стыки секций
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        draw.line([(x, y - h / 2), (x, y + h / 2)], fill=weld_color, width=2)
        lab = f"К{i + 1}"
        draw.text((x + 2, y - h / 2 - 16), lab, fill=weld_color, font=font_tiny)
        _add_point(suggested, lab, x, y - h / 2 - 10, width, height, "weld", "circumferential")

    if kind == "underground_pipeline":
        gy = y + h / 2 + 40
        draw.line([(x0 - 20, gy), (x1 + 20, gy)], fill=(120, 90, 50), width=2)
        for gx in range(int(x0), int(x1), 30):
            draw.line([(gx, gy), (gx + 10, gy + 12)], fill=(120, 90, 50), width=1)
        draw.text((x0, gy + 14), "уровень земли", fill=(120, 90, 50), font=font_tiny)
    elif kind == "pipeline_crossing":
        # условная дорога сверху
        road_y = y - h / 2 - 55
        draw.rectangle([x0 + 80, road_y, x1 - 80, road_y + 28], outline=accent, width=2)
        draw.text((x0 + 90, road_y + 6), "дорога / ж.д.", fill=accent, font=font_tiny)
    elif kind == "aboveground_pipeline":
        # опоры
        for i in range(1, n):
            x = x0 + (x1 - x0) * (i / n)
            draw.line([(x, y + h / 2), (x, y + h / 2 + 35)], fill=ink, width=2)
            draw.line([(x - 12, y + h / 2 + 35), (x + 12, y + h / 2 + 35)], fill=ink, width=2)

    for i, nzz in enumerate(geo.get("nozzles") or []):
        pos = _f(nzz.get("position") or nzz.get("axial"), 0.3 + i * 0.2)
        x = x0 + (x1 - x0) * min(0.95, max(0.05, pos))
        draw.ellipse([x - 10, y - h / 2 - 28, x + 10, y - h / 2 - 8], outline=accent, width=2)
        lab = str(nzz.get("label") or f"Пт{i + 1}")
        draw.text((x + 12, y - h / 2 - 28), lab, fill=accent, font=font_tiny)
        _add_point(suggested, lab, x, y - h / 2 - 18, width, height, "nozzle")


def draw_tank_family(
    draw: ImageDraw.ImageDraw,
    geo: Dict[str, Any],
    *,
    width: int,
    height: int,
    ink: Tuple[int, int, int],
    accent: Tuple[int, int, int],
    weld_color: Tuple[int, int, int],
    font_sm,
    font_tiny,
    suggested: List[Dict[str, Any]],
) -> None:
    """Резервуар: круг (план днища/крыши) + полоса стенки с поясами."""
    n = max(1, int(geo.get("shell_count") or 3))
    cx = width * 0.32
    cy = height * 0.45
    r = min(width, height) * 0.18
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=ink, width=3)
    draw.ellipse([cx - r * 0.15, cy - r * 0.15, cx + r * 0.15, cy + r * 0.15], outline=ink, width=2)
    # радиальные швы крыши
    import math

    for i in range(4):
        ang = -math.pi / 2 + i * math.pi / 2
        draw.line(
            [(cx, cy), (cx + r * 0.95 * math.cos(ang), cy + r * 0.95 * math.sin(ang))],
            fill=weld_color,
            width=2,
        )
    draw.text((cx - 40, cy - r - 22), "План (крыша/днище)", fill=ink, font=font_sm)

    # стенка — развёртка поясов
    sx0 = width * 0.55
    sx1 = width * 0.92
    sy0 = height * 0.22
    sy1 = height * 0.78
    draw.rectangle([sx0, sy0, sx1, sy1], outline=ink, width=3)
    draw.text((sx0, sy0 - 20), "Развёртка стенки", fill=ink, font=font_sm)
    for i in range(n + 1):
        yy = sy0 + (sy1 - sy0) * (i / n)
        draw.line([(sx0, yy), (sx1, yy)], fill=weld_color, width=2)
        lab = f"К{i + 1}"
        draw.text((sx1 + 6, yy - 7), lab, fill=weld_color, font=font_tiny)
        _add_point(suggested, lab, sx1 + 8, yy, width, height, "weld")
    # продольные вразбежку
    for s in range(n):
        phase = 0.3 if s % 2 == 0 else 0.7
        x = sx0 + (sx1 - sx0) * phase
        y0 = sy0 + (sy1 - sy0) * (s / n) + 3
        y1 = sy0 + (sy1 - sy0) * ((s + 1) / n) - 3
        draw.line([(x, y0), (x, y1)], fill=weld_color, width=2)
        lab = f"П{s + 1}"
        draw.text((x + 4, (y0 + y1) / 2), lab, fill=weld_color, font=font_tiny)
        _add_point(suggested, lab, x, (y0 + y1) / 2, width, height, "weld", "longitudinal")

    for i, nzz in enumerate(geo.get("nozzles") or []):
        pos = _f(nzz.get("axial") or nzz.get("position"), 0.4)
        circ = _f(nzz.get("circ"), 0.5)
        x = sx0 + (sx1 - sx0) * circ
        y = sy0 + (sy1 - sy0) * pos
        draw.ellipse([x - 12, y - 12, x + 12, y + 12], outline=accent, width=2)
        lab = str(nzz.get("label") or f"Пт{i + 1}")
        draw.text((x + 14, y - 6), lab, fill=accent, font=font_tiny)
        _add_point(suggested, lab, x, y, width, height, "nozzle")


def draw_tower_family(
    draw: ImageDraw.ImageDraw,
    geo: Dict[str, Any],
    *,
    width: int,
    height: int,
    ink: Tuple[int, int, int],
    accent: Tuple[int, int, int],
    weld_color: Tuple[int, int, int],
    font_sm,
    font_tiny,
    suggested: List[Dict[str, Any]],
) -> None:
    kind = geo.get("equipment_kind") or "chimney"
    n = max(2, int(geo.get("shell_count") or 4))
    cx = width / 2
    top = 70
    bot = height - 80
    top_w = 50 if kind == "flare" else 70
    bot_w = 140 if kind == "flare" else 160
    # трапеция ствола
    draw.polygon(
        [(cx - top_w / 2, top), (cx + top_w / 2, top), (cx + bot_w / 2, bot), (cx - bot_w / 2, bot)],
        outline=ink,
    )
    title = "Факел" if kind == "flare" else "Дымовая труба"
    draw.text((cx - 50, top - 28), title, fill=ink, font=font_sm)
    for i in range(1, n):
        t = i / n
        y = top + (bot - top) * t
        w = top_w + (bot_w - top_w) * t
        draw.line([(cx - w / 2, y), (cx + w / 2, y)], fill=weld_color, width=2)
        lab = f"К{i}"
        draw.text((cx + w / 2 + 6, y - 7), lab, fill=weld_color, font=font_tiny)
        _add_point(suggested, lab, cx + w / 2 + 8, y, width, height, "weld")
    # продольный со смещением по поясам
    for s in range(n):
        t0, t1 = s / n, (s + 1) / n
        y0 = top + (bot - top) * t0 + 4
        y1 = top + (bot - top) * t1 - 4
        off = 0.35 if s % 2 == 0 else 0.65
        w0 = top_w + (bot_w - top_w) * t0
        x = cx - w0 / 2 + w0 * off
        draw.line([(x, y0), (x, y1)], fill=weld_color, width=2)
        lab = f"П{s + 1}"
        draw.text((x + 4, (y0 + y1) / 2), lab, fill=weld_color, font=font_tiny)
        _add_point(suggested, lab, x, (y0 + y1) / 2, width, height, "weld", "longitudinal")
    if kind == "flare":
        # оголовок
        draw.polygon([(cx - 18, top), (cx + 18, top), (cx, top - 28)], outline=accent)
        draw.text((cx + 30, top - 20), "оголовок", fill=accent, font=font_tiny)


def draw_boiler_family(
    draw: ImageDraw.ImageDraw,
    geo: Dict[str, Any],
    *,
    width: int,
    height: int,
    ink: Tuple[int, int, int],
    accent: Tuple[int, int, int],
    weld_color: Tuple[int, int, int],
    font_sm,
    font_tiny,
    suggested: List[Dict[str, Any]],
) -> None:
    kind = geo.get("equipment_kind") or "boiler"
    x0, y0 = width * 0.25, height * 0.22
    x1, y1 = width * 0.75, height * 0.78
    draw.rectangle([x0, y0, x1, y1], outline=ink, width=3)
    # барабан сверху
    cy = y0 + 50
    draw.ellipse([x0 + 40, cy - 35, x1 - 40, cy + 35], outline=ink, width=3)
    draw.text((x0 + 50, cy - 50), "Барабан" if kind == "boiler" else "Аппарат", fill=ink, font=font_sm)
    # экранные трубы
    for i in range(6):
        xx = x0 + 50 + i * ((x1 - x0 - 100) / 5)
        draw.line([(xx, cy + 40), (xx, y1 - 40)], fill=accent, width=2)
    draw.line([(x0 + 40, y1 - 30), (x1 - 40, y1 - 30)], fill=weld_color, width=2)
    draw.text((x0 + 40, y1 - 28), "К1", fill=weld_color, font=font_tiny)
    _add_point(suggested, "К1", x0 + 60, y1 - 30, width, height, "weld")
    draw.text((x0, y0 - 24), "Котёл" if kind == "boiler" else "Котельное оборудование", fill=ink, font=font_sm)


def draw_machinery_family(
    draw: ImageDraw.ImageDraw,
    geo: Dict[str, Any],
    *,
    width: int,
    height: int,
    ink: Tuple[int, int, int],
    accent: Tuple[int, int, int],
    weld_color: Tuple[int, int, int],
    font_sm,
    font_tiny,
    suggested: List[Dict[str, Any]],
) -> None:
    kind = geo.get("equipment_kind") or "compressor"
    titles = {
        "compressor": "Центробежный нагнетатель",
        "gpa": "Газоперекачивающий агрегат",
        "gpa_drive": "Электропривод ГПА",
        "electric_motor": "Электродвигатель",
    }
    cx, cy = width / 2, height / 2
    # корпус
    draw.rectangle([cx - 220, cy - 80, cx + 160, cy + 80], outline=ink, width=3)
    # ротор / вал
    draw.line([(cx - 240, cy), (cx + 200, cy)], fill=accent, width=3)
    for i, fx in enumerate((-120, -20, 80)):
        draw.ellipse([cx + fx - 35, cy - 55, cx + fx + 35, cy + 55], outline=accent, width=2)
        lab = f"С{i + 1}"
        draw.text((cx + fx - 8, cy + 60), lab, fill=weld_color, font=font_tiny)
        _add_point(suggested, lab, cx + fx, cy + 50, width, height, "weld")
    # фундамент
    draw.line([(cx - 240, cy + 100), (cx + 180, cy + 100)], fill=ink, width=3)
    draw.text((cx - 220, cy - 110), titles.get(kind, "Агрегат"), fill=ink, font=font_sm)


def draw_electrical_family(
    draw: ImageDraw.ImageDraw,
    geo: Dict[str, Any],
    *,
    width: int,
    height: int,
    ink: Tuple[int, int, int],
    accent: Tuple[int, int, int],
    weld_color: Tuple[int, int, int],
    font_sm,
    font_tiny,
    suggested: List[Dict[str, Any]],
) -> None:
    kind = geo.get("equipment_kind") or "transformer"
    titles = {
        "transformer": "Силовой трансформатор",
        "lightning_protection": "Молниезащита / заземление",
        "dc_system": "Система постоянного тока",
        "diesel_station": "Дизельная электростанция",
        "cable_line": "Кабельная линия 6–10 кВ",
        "power_station": "Электростанция СН",
        "switchgear": "Распределительное устройство",
    }
    draw.text((60, 70), titles.get(kind, "Электрооборудование"), fill=ink, font=font_sm)

    if kind == "cable_line":
        n = max(3, int(geo.get("shell_count") or 6))
        y = height * 0.45
        x0, x1 = 80, width - 80
        draw.line([(x0, y), (x1, y)], fill=accent, width=4)
        for i in range(n + 1):
            x = x0 + (x1 - x0) * (i / n)
            draw.line([(x, y - 20), (x, y + 20)], fill=weld_color, width=2)
            lab = f"М{i + 1}"
            draw.text((x - 6, y + 24), lab, fill=weld_color, font=font_tiny)
            _add_point(suggested, lab, x, y, width, height, "custom", "marker")
        draw.text((x0, y - 40), "трасса кабеля", fill=ink, font=font_tiny)
        return

    if kind == "lightning_protection":
        cx = width / 2
        draw.line([(cx, 120), (cx, height - 120)], fill=accent, width=3)
        draw.polygon([(cx, 100), (cx - 18, 130), (cx + 18, 130)], outline=accent)
        for i, yy in enumerate((0.35, 0.55, 0.75)):
            y = height * yy
            draw.line([(cx, y), (cx + 80, y + 40)], fill=ink, width=2)
            lab = f"З{i + 1}"
            draw.text((cx + 85, y + 30), lab, fill=weld_color, font=font_tiny)
            _add_point(suggested, lab, cx + 80, y + 40, width, height, "custom")
        return

    # трансформатор / щит / ДЭС — блок с зонами
    x0, y0 = width * 0.28, height * 0.28
    x1, y1 = width * 0.72, height * 0.72
    draw.rectangle([x0, y0, x1, y1], outline=ink, width=3)
    mid = (y0 + y1) / 2
    draw.line([(x0, mid), (x1, mid)], fill=weld_color, width=2)
    draw.ellipse([x0 + 30, y0 + 30, x0 + 110, y0 + 110], outline=accent, width=2)
    draw.ellipse([x1 - 110, y0 + 30, x1 - 30, y0 + 110], outline=accent, width=2)
    for i, (px, py) in enumerate(
        ((x0 + 70, y0 + 70), (x1 - 70, y0 + 70), ((x0 + x1) / 2, mid + 50))
    ):
        lab = f"Т{i + 1}"
        draw.text((px + 8, py), lab, fill=weld_color, font=font_tiny)
        _add_point(suggested, lab, px, py, width, height, "custom")


def draw_valve_family(
    draw: ImageDraw.ImageDraw,
    geo: Dict[str, Any],
    *,
    width: int,
    height: int,
    ink: Tuple[int, int, int],
    accent: Tuple[int, int, int],
    weld_color: Tuple[int, int, int],
    font_sm,
    font_tiny,
    suggested: List[Dict[str, Any]],
) -> None:
    kind = geo.get("equipment_kind") or "pipeline_valve"
    titles = {
        "pipeline_valve": "Трубопроводная арматура",
        "wellhead_tree": "Фонтанная арматура",
        "metering": "Замерное устройство",
        "prg": "ПРГ",
    }
    cx, cy = width / 2, height / 2
    draw.text((80, 70), titles.get(kind, "Арматура"), fill=ink, font=font_sm)
    # горизонтальная труба
    draw.rectangle([cx - 280, cy - 25, cx + 280, cy + 25], outline=ink, width=3)
    # корпус арматуры
    draw.polygon(
        [(cx - 50, cy - 25), (cx + 50, cy - 25), (cx + 70, cy + 25), (cx - 70, cy + 25)],
        outline=accent,
    )
    draw.line([(cx, cy - 25), (cx, cy - 90)], fill=accent, width=3)
    draw.ellipse([cx - 22, cy - 115, cx + 22, cy - 70], outline=accent, width=2)
    # стыки
    for i, dx in enumerate((-180, -90, 90, 180)):
        x = cx + dx
        draw.line([(x, cy - 25), (x, cy + 25)], fill=weld_color, width=2)
        lab = f"К{i + 1}"
        draw.text((x + 2, cy - 42), lab, fill=weld_color, font=font_tiny)
        _add_point(suggested, lab, x, cy - 30, width, height, "weld")
    if kind == "wellhead_tree":
        # вертикальная колонна
        draw.rectangle([cx - 20, cy + 25, cx + 20, cy + 160], outline=ink, width=2)
        draw.text((cx + 30, cy + 80), "колонна", fill=ink, font=font_tiny)


def draw_crane_family(
    draw: ImageDraw.ImageDraw,
    geo: Dict[str, Any],
    *,
    width: int,
    height: int,
    ink: Tuple[int, int, int],
    accent: Tuple[int, int, int],
    weld_color: Tuple[int, int, int],
    font_sm,
    font_tiny,
    suggested: List[Dict[str, Any]],
) -> None:
    kind = geo.get("equipment_kind") or "crane"
    if kind == "crane_runway":
        n = max(3, int(geo.get("shell_count") or 4))
        y1, y2 = height * 0.38, height * 0.55
        x0, x1 = 70, width - 70
        draw.line([(x0, y1), (x1, y1)], fill=ink, width=4)
        draw.line([(x0, y2), (x1, y2)], fill=ink, width=4)
        draw.text((x0, y1 - 28), "Подкрановые пути", fill=ink, font=font_sm)
        for i in range(n + 1):
            x = x0 + (x1 - x0) * (i / n)
            draw.line([(x, y1), (x, y2)], fill=weld_color, width=2)
            lab = f"С{i + 1}"
            draw.text((x - 6, y2 + 8), lab, fill=weld_color, font=font_tiny)
            _add_point(suggested, lab, x, y2, width, height, "weld")
        return

    cx = width / 2
    x0, y0, x1, y1 = cx - 40, 120, cx + 40, height - 100
    draw.rectangle([x0, y0, x1, y1], outline=ink, width=3)
    boom_y = y0 + 40
    draw.line([(cx, boom_y), (cx + 220, boom_y - 30)], fill=accent, width=4)
    draw.line([(cx + 220, boom_y - 30), (cx + 220, boom_y + 70)], fill=accent, width=2)
    draw.arc([cx + 208, boom_y + 65, cx + 232, boom_y + 90], 0, 360, fill=accent, width=2)
    draw.polygon(
        [(cx - 60, y1), (cx + 60, y1), (cx + 90, y1 + 30), (cx - 90, y1 + 30)],
        outline=ink,
    )
    draw.text((cx - 40, y0 - 28), "ГПМ", fill=ink, font=font_sm)
    for i, yy in enumerate((0.3, 0.55, 0.75)):
        y = y0 + (y1 - y0) * yy
        draw.line([(x0, y), (x1, y)], fill=weld_color, width=2)
        lab = f"К{i + 1}"
        draw.text((x1 + 6, y - 6), lab, fill=weld_color, font=font_tiny)
        _add_point(suggested, lab, x1 + 8, y, width, height, "weld")


def draw_station_family(
    draw: ImageDraw.ImageDraw,
    geo: Dict[str, Any],
    *,
    width: int,
    height: int,
    ink: Tuple[int, int, int],
    accent: Tuple[int, int, int],
    weld_color: Tuple[int, int, int],
    font_sm,
    font_tiny,
    suggested: List[Dict[str, Any]],
) -> None:
    kind = geo.get("equipment_kind") or "grs"
    titles = {
        "grs": "ГРС — схема узлов",
        "prg": "ПРГ",
        "gis_station": "ГИС / ПЗРГ / УИРГ",
        "pu_unit": "ПУ — схема",
    }
    draw.text((60, 70), titles.get(kind, "Станция / узел"), fill=ink, font=font_sm)
    blocks = [
        ("Вход", 0.18, 0.35),
        ("Редуц.", 0.45, 0.35),
        ("Учёт", 0.72, 0.35),
        ("Выход", 0.45, 0.65),
    ]
    n = max(3, int(geo.get("shell_count") or 4))
    blocks = blocks[:n]
    centers = []
    for title, fx, fy in blocks:
        bx = width * fx
        by = height * fy
        w, h = 110, 70
        draw.rectangle([bx - w / 2, by - h / 2, bx + w / 2, by + h / 2], outline=ink, width=2)
        draw.text((bx - 28, by - 8), title, fill=ink, font=font_tiny)
        centers.append((bx, by, title))
        _add_point(suggested, title, bx, by, width, height, "custom")
    # связи
    for i in range(len(centers) - 1):
        x0, y0, _ = centers[i]
        x1, y1, _ = centers[i + 1]
        draw.line([(x0 + 55, y0), (x1 - 55, y1)], fill=accent, width=2)
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        lab = f"К{i + 1}"
        draw.text((mx, my - 14), lab, fill=weld_color, font=font_tiny)
        _add_point(suggested, lab, mx, my, width, height, "weld")


def draw_generic_family(
    draw: ImageDraw.ImageDraw,
    geo: Dict[str, Any],
    *,
    width: int,
    height: int,
    ink: Tuple[int, int, int],
    accent: Tuple[int, int, int],
    weld_color: Tuple[int, int, int],
    font_sm,
    font_tiny,
    suggested: List[Dict[str, Any]],
) -> None:
    title = str(geo.get("title") or "Карта контроля")
    x0, y0 = 80, 100
    x1, y1 = width - 80, height - 90
    draw.rectangle([x0, y0, x1, y1], outline=ink, width=3)
    # сетка зон контроля 3×3
    for i in range(1, 3):
        x = x0 + (x1 - x0) * (i / 3)
        y = y0 + (y1 - y0) * (i / 3)
        draw.line([(x, y0), (x, y1)], fill=(200, 200, 200), width=1)
        draw.line([(x0, y), (x1, y)], fill=(200, 200, 200), width=1)
    idx = 1
    for row in range(3):
        for col in range(3):
            x = x0 + (x1 - x0) * ((col + 0.5) / 3)
            y = y0 + (y1 - y0) * ((row + 0.5) / 3)
            draw.ellipse([x - 8, y - 8, x + 8, y + 8], outline=accent, width=2)
            lab = f"Т{idx}"
            draw.text((x + 10, y - 6), lab, fill=weld_color, font=font_tiny)
            _add_point(suggested, lab, x, y, width, height, "custom")
            idx += 1
    draw.text((x0, y0 - 24), title, fill=ink, font=font_sm)
