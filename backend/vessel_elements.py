"""Part-local vessel attachments. These are not inspection measurement points."""
import math

ELEMENT_NAMES = {
    'nozzle': 'Штуцер', 'manway': 'Люк', 'instrument': 'Бобышка КИП',
    'drain': 'Дренаж', 'vent': 'Воздушник', 'pad': 'Укрепляющая накладка',
    'support': 'Опора', 'lug': 'Строповая проушина',
}


def normalize_elements(raw, count):
    if not isinstance(raw, list) or len(raw) > 500:
        raise ValueError('Допускается до 500 элементов')
    result, ids = [], set()
    parts = {'head_top', 'head_bottom'} | {f'shell_{i+1}' for i in range(count)}
    for i, item in enumerate(raw):
        if not isinstance(item, dict):
            raise ValueError('Некорректный элемент')
        e = dict(item)
        if e.get('kind') not in ELEMENT_NAMES or e.get('part_id') not in parts:
            raise ValueError('Неизвестный элемент или часть сосуда')
        e['id'] = str(e.get('id') or f'E{i+1}')
        if e['id'] in ids:
            raise ValueError('Повторяющийся идентификатор элемента')
        ids.add(e['id'])
        for axis in ('x', 'y'):
            value = float(e.get(axis, .5))
            if not math.isfinite(value) or not 0 <= value <= 1:
                raise ValueError('Координаты элемента должны быть от 0 до 1')
            e[axis] = value
        if e['part_id'].startswith('head') and math.hypot(e['x']-.5, e['y']-.5) > .5:
            raise ValueError('Элемент за пределами днища')
        e['label'] = str(e.get('label') or e['id'])[:80]
        e['control_points'] = int(e.get('control_points', 0))
        if e['control_points'] not in (0, 2, 4):
            raise ValueError('Допускаются 0, 2 или 4 обозначения контроля')
        result.append(e)
    return result


def draw_elements(draw, elements, layout, font, horizontal=False):
    x0, y0, x1, y1 = layout['body']
    count = layout['shell_count']
    ink = '#245a91'
    for e in elements:
        part = e['part_id']
        if part.startswith('head'):
            cx, cy, r = layout[part]
            x, y = cx + (e['x']-.5)*2*r, cy + (e['y']-.5)*2*r
        else:
            index = int(part.split('_')[1])-1
            if horizontal:
                x, y = x0+(x1-x0)*(index+e['y'])/count, y0+(y1-y0)*e['x']
            else:
                x, y = x0+(x1-x0)*e['x'], y0+(y1-y0)*(index+e['y'])/count
        draw_symbol(draw, x, y, e['kind'], ink)
        draw.text((x+14, y-18), e['label'], fill=ink, font=font)
        for i, (dx, dy) in enumerate([(0,-18),(0,18),(-18,0),(18,0)][:e['control_points']]):
            draw.ellipse((x+dx-2,y+dy-2,x+dx+2,y+dy+2),fill='#b42828')
            draw.text((x+dx+3,y+dy-5),str(i+1),fill=ink,font=font)


def draw_symbol(draw, x, y, kind, ink='#245a91'):
    r = 10
    if kind in ('support', 'pad'):
        draw.rectangle((x-r,y-r*.75,x+r,y+r*.75),outline=ink,width=2)
        if kind == 'support': draw.line((x-14,y+r,x+14,y+r),fill=ink,width=2)
    elif kind == 'manway':
        draw.ellipse((x-14,y-10,x+14,y+10),outline=ink,width=2)
        draw.ellipse((x-10,y-6,x+10,y+6),outline=ink,width=2)
    else:
        draw.ellipse((x-r,y-r,x+r,y+r),outline=ink,width=2)
        if kind in ('nozzle','manway'): draw.ellipse((x-6,y-6,x+6,y+6),outline=ink,width=2)
        if kind == 'instrument':
            draw.line((x-r,y,x+r,y),fill=ink,width=2)
            draw.line((x,y-r,x,y+r),fill=ink,width=2)
        if kind in ('drain','vent'):
            sign = 1 if kind == 'drain' else -1
            draw.line((x,y,x,y+sign*18),fill=ink,width=2)
            draw.line((x-5,y+sign*12,x,y+sign*18,x+5,y+sign*12),fill=ink,width=2)
        if kind == 'lug': draw.rectangle((x-r,y,x+r,y+r*1.5),outline=ink,width=2)
