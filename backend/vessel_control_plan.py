"""Vessel geometry and control scope. Planned points never become measurements."""
from decimal import Decimal, InvalidOperation
import re


def number(value):
    try:
        result = Decimal(str(value).strip().replace(',', '.'))
        return result if result.is_finite() else None
    except (InvalidOperation, ValueError):
        return None


def vessel_shells(g):
    elements = g('vessel_elements', 'passport_elements', default=[]) or []
    shells = [dict(e) for e in elements if isinstance(e, dict)
              and 'обечай' in str(e.get('name') or e.get('element_name') or '').lower()]
    # Explicit passport segmentation is authoritative, including nonstandard lengths.
    aggregate = len(shells) == 1 and str(shells[0].get('name') or shells[0].get('element_name')).strip().lower() in ('обечайка', 'обечайки')
    if shells and not aggregate:
        return shells
    template = shells[0] if aggregate else {}
    length = number(template.get('length_mm') or template.get('length')) if aggregate else None
    if length is None:
        length = number(g('body_length_mm', 'shell_length_mm', default=None))
    if length is None:
        metres = number(g('body_length_m', default=None))
        length = metres * 1000 if metres is not None else None
    if length is None or length <= 0:
        return shells
    standard = number(g('shell_course_length_mm', default=2000))
    if standard is None or standard <= 0:
        raise ValueError('Длина одной обечайки должна быть положительной')
    count = int((length / standard).to_integral_value(rounding='ROUND_CEILING'))
    if count > 1000:
        raise ValueError('Проверьте длину корпуса и единицы измерения')
    return [{**template, 'name': f'Обечайка {i + 1}', 'length_mm': float(min(standard, length - i * standard)),
             'diameter_mm': template.get('diameter_mm') or g('diameter', default='—'),
             'wall_thickness_mm': template.get('wall_thickness_mm') or g('wall_thickness', default='—'),
             'material': template.get('material') or g('shell_material', default='—')} for i in range(count)]


def method_code(value):
    value = str(value or '').strip().upper()
    return {'УЗК': 'UZK', 'МК': 'MPK', 'МПК': 'MPK', 'MK': 'MPK', 'MPD': 'MPK',
            'ПВК': 'PVK', 'ПВК/МК': 'PVK', 'ТВ': 'HARDNESS', 'TVI': 'HARDNESS'}.get(value, value)


def method_rows(rows, method):
    # An untagged weld cannot serve as evidence for two different methods.
    return [r for r in rows if isinstance(r, dict)
            and method_code(r.get('control_method') or r.get('method')) == method_code(method)]


def planned_count(g, code):
    key = {'UZK': 'uzk_sections', 'MPK': 'mpk_sections', 'PVK': 'pvk_sections',
           'HARDNESS': 'hardness_sections'}[code]
    task = g('technical_task', default={}) or {}
    raw = task.get(key) if isinstance(task, dict) else None
    if raw in (None, ''):
        raw = g(key, default=None)
    if raw in (None, ''):
        return None
    n = number(raw)
    if n is None or n < 0 or n != int(n):
        raise ValueError(f'Техническое задание: {key} должно быть целым неотрицательным числом')
    return int(n)


def shell_points(shells, measurements):
    grouped = {str(s.get('name') or s.get('element_name')): [] for s in shells}
    other = {}
    for row in measurements:
        if not isinstance(row, dict):
            continue
        name = str(row.get('element_name') or row.get('location') or 'Элемент не указан')
        normalized = re.sub(r'[\s№]+', '', name).lower()
        target = next((k for k in grouped if re.sub(r'[\s№]+', '', k).lower() == normalized), None)
        if target is None and len(shells) == 1 and normalized == 'обечайка':
            target = next(iter(grouped))
        (grouped[target] if target else other.setdefault(name, [])).append(row)
    return grouped, other


def control_scope(g):
    shells = vessel_shells(g)
    grouped, _ = shell_points(shells, g('thickness_measurements', default=[]) or [])
    issues = []
    if not shells:
        issues.append('Не задана длина корпуса или состав обечаек')
    for name, points in grouped.items():
        valid = set()
        for p in points:
            idx = number(p.get('point_number') or p.get('section_number'))
            value = number(p.get('thickness'))
            if idx is None or idx != int(idx) or not 1 <= idx <= 12:
                issues.append(f'{name}: номер точки УЗТ должен быть от 1 до 12')
            if idx is not None and idx == int(idx) and 1 <= idx <= 12 and value is not None and value > 0:
                if int(idx) in valid:
                    issues.append(f'{name}: повтор точки {idx}')
                valid.add(int(idx))
        if len(valid) != 12:
            issues.append(f'{name}: заполнено {len(valid)} из 12 точек УЗТ')
    welds = g('weld_inspections', default=[]) or []
    if any(isinstance(r, dict) and not (r.get('control_method') or r.get('method')) for r in welds):
        issues.append('Не указан метод контроля у записей сварных соединений')
    scope = []
    for code, label in [('UZK', 'УЗК'), ('MPK', 'МК'), ('PVK', 'ПВК'), ('HARDNESS', 'Твердометрия')]:
        planned = planned_count(g, code)
        rows = g('hardness_tests', default=[]) or [] if code == 'HARDNESS' else method_rows(welds, code)
        actual = len(rows)
        scope.append((label, planned, actual))
        if planned is None:
            issues.append(f'{label}: объём по техническому заданию не указан')
        elif actual != planned:
            issues.append(f'{label}: в отчёте {actual} участков, по техническому заданию {planned}')
    return shells, scope, issues
