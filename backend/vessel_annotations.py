"""View-only legend and coordinate callouts; never derive physical sizes from pixels."""
import math

KINDS = {'nozzle': '⊕ Штуцер', 'manway': '◎ Люк', 'support': 'Опора', 'pad': 'Накладка',
         'instrument': 'Бобышка КИП', 'lug': 'Проушина', 'drain': 'Дренаж', 'vent': 'Воздушник', 'cover': 'Крышка — отдельный вид'}


def coordinate_callout(g, entity, owner, detail=None):
    if (g.get('print_settings') or {}).get('show_dimensions', True) is False:
        return []
    point = 'owner_id' in entity
    if detail is None:
        return []
    p = entity.get('placement') or {}
    if p.get('mode') != 'physical':
        return [] if point else ['Положение условное']
    def fmt(value):
        return f'{float(value):.6f}'.rstrip('0').rstrip('.').replace('.', ',')
    key = 'z_local_mm' if owner.get('kind') == 'shell' else 'radius_projection_mm'
    value, angle = p.get(key), p.get('theta_deg')
    if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in (value, angle)):
        return ['Координаты не заданы']
    if key == 'z_local_mm':
        reference = next((w for w in g['welds'] if w['id'] == p.get('reference_weld_id')
                          and w['kind'] == 'circumferential' and owner['id'] in w['connected_part_ids']), None)
        origin = 'от начала детали'
        if reference:
            if reference['connected_part_ids'][0] == owner['id']:
                length = owner.get('dimensions', {}).get('length_mm')
                if not isinstance(length, (int, float)) or not math.isfinite(length):
                    return ['Размер от шва не задан']
                value = length - value
            origin = 'от ' + str(reference['designation'])
        linear = f'{fmt(value)} мм {origin}'
    else:
        linear = f'Rпр={fmt(value)} мм от центра'
    convention = ' · Visio' if p.get('angle_convention') == 'visio-head-2026' else ''
    return [linear, f'θ={fmt(angle % 360)}°{convention}']


def legend_entries(g, visible_ids, layer=None, detail=None):
    visible = set(visible_ids)
    labels = set()
    for e in g['elements']:
        if e['id'] in visible and not e.get('archived'):
            labels.add(KINDS.get(e['kind'], str(e['kind'])))
    if any(p['kind'] == 'cover' and p['id'] in visible for p in g['parts']):
        labels.add(KINDS['cover'])
    if any(p['id'] in visible and not p.get('archived') for p in g['control_points']) and layer in (None, '', 'УЗТ'):
        labels.add('× Точка УЗТ')
    for w in g['welds']:
        zones = [z for z in g['control_zones'] if z['weld_id'] == w['id'] and (not layer or layer in z['planned_methods'])]
        if w['kind'] == 'attachment':
            shown = w.get('geometry', {}).get('element_id') in visible and bool(zones)
        else:
            shown = any(p['id'] in visible and p['id'] in w['connected_part_ids']
                        and (w['kind'] == 'head_joint' or p['kind'] == 'shell') for p in g['parts'])
        if not shown:
            continue
        labels.add({'circumferential': 'К — кольцевой шов', 'longitudinal': 'П — продольный шов',
                    'head_joint': 'Шов днища', 'attachment': 'Шов приварки'}[w['kind']])
        for zone in ([] if w['kind'] == 'head_joint' else zones):
            if zone['weld_id'] == w['id'] and (not layer or layer in zone['planned_methods']):
                # A combined band remains combined when selected through either method.
                for method in zone['planned_methods']:
                    labels.add(('/ ' if method == 'УЗК' else '× ') + method)
    for s in g.get('sections', []):
        if s['kind'] == 'ovality' and s['owner_id'] in visible:
            labels.add('I–III овальность')
        if s['kind'] == 'weld_profile' and detail is None:
            labels.add('А–А твердометрия')
    return sorted(labels)


def legend_lines(entries, width, font=None):
    lines, line = [], 'Обозначения: '
    measure = font.getlength if font else len
    limit = width - 40 if font else max(40, int((width-40)/6.5))
    for entry in entries:
        separator = ' · ' if line and line != 'Обозначения: ' else ''
        if line and measure(line + separator + entry) > limit:
            lines.append(line); line = ''
        line += (' · ' if line and line != 'Обозначения: ' else '') + entry
    if entries:
        lines.append(line)
    return lines


def draw_print_callouts(draw, marks, rows, width, height, font_factory, label_boxes):
    """Match numbered tags to a readable register using only short leaders."""
    panel = width * .59
    font = font_factory(15)
    occupied = list(label_boxes)
    leaders = []
    directions = [(1, -1), (1, 1), (-1, -1), (-1, 1), (0, -1), (0, 1), (1, 0), (-1, 0)]
    directions.extend((math.cos(math.radians(angle)), math.sin(math.radians(angle)))
                      for angle in range(15, 360, 15) if angle % 45)

    def cross(a, b, c, d):
        def side(p, q, r):
            return (q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
        return side(a,b,c)*side(a,b,d) < 0 and side(c,d,a)*side(c,d,b) < 0

    def overlap(a, b):
        return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]

    def edges(box):
        x1, y1, x2, y2 = box
        corners = [(x1, y1), (x2, y1), (x2, y2), (x1, y2)]
        return zip(corners, corners[1:] + corners[:1])

    def text_at(x, y, text):
        available = width - x - 18
        if font.getlength(text) > available:
            while text and font.getlength(text + '…') > available:
                text = text[:-1]
            text += '…'
        draw.text((x, y), text, font=font)

    draw.rectangle((panel-4, 87, width-9, height-110), fill='white')
    draw.text((panel, 91), 'Координаты по номеру выноски', font=font_factory(18))
    for index, (entity_id, number, name, coordinates) in enumerate(rows):
        anchor = marks.get(entity_id)
        if anchor is None:
            continue
        x, y = anchor
        tag_width = font.getlength(number) + 10
        for distance in (26, 36, 48, 62, 82, 108):
            for dx, dy in directions:
                tx, ty = x + dx*distance - tag_width/2, y + dy*distance - 11
                box = (tx, ty, tx+tag_width, ty+22)
                if tx < 12 or box[2] > panel-12 or ty < 87 or box[3] > height-114:
                    continue
                if any(overlap(box, other) for other in occupied):
                    continue
                if any(overlap(box, (mx-5, my-5, mx+5, my+5)) for mx,my in marks.values()):
                    continue
                end = (max(tx,min(x,box[2])), max(ty,min(y,box[3])))
                if any(cross(anchor,end,a,b) for a,b in leaders):
                    continue
                if any(cross(a,b,c,d) for a,b in leaders for c,d in edges(box)):
                    continue
                if any(cross(anchor,end,a,b) for old in occupied for a,b in edges(old)
                       if not (old[0] <= x <= old[2] and old[1] <= y <= old[3])):
                    continue
                draw.line([anchor,end],fill='#444444')
                draw.rectangle(box,fill='white',outline='black')
                draw.text((tx+5,ty+1),number,font=font)
                occupied.append(box)
                leaders.append((anchor,end))
                break
            else:
                continue
            break
        else:
            raise ValueError(f'Не удалось разместить выноску {number}. Увеличьте формат листа.')
        row_y = 122 + index*62
        draw.line([(panel,row_y-3),(width-18,row_y-3)],fill='#b8b8b8')
        text_at(panel,row_y,f'{number}. {name}')
        for line_index, line in enumerate(coordinates,1):
            text_at(panel+16,row_y+line_index*18,line)
