"""Lossless vessel document validation and projection. No inferred measurements."""
from __future__ import annotations

from copy import deepcopy
import io
import math
from typing import Any


def finite(value: Any, name: str, *, positive=False) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f'{name}: finite number required')
    if positive and value <= 0:
        raise ValueError(f'{name}: positive number required')
    return float(value)


def normalize_v2(raw: dict) -> dict:
    g = deepcopy(raw)
    if g.get('schema_version') != 2:
        raise ValueError('Unsupported schema_version')
    if not g.get('model_id') or not isinstance(g.get('revision'), int) or g['revision'] < 0:
        raise ValueError('model_id and nonnegative revision required')
    if g.get('orientation') not in ('horizontal', 'vertical'):
        raise ValueError('Invalid orientation')
    ids = {}
    for key, maximum in [('parts', 300), ('elements', 250), ('welds', 200),
                         ('control_points', 500), ('control_zones', 1000)]:
        items = g.setdefault(key, [])
        if not isinstance(items, list) or len(items) > maximum:
            raise ValueError(f'{key}: invalid collection or too many entries')
        for e in items:
            if not isinstance(e, dict) or not isinstance(e.get('id'), str) or not e['id'] or e['id'] in ids:
                raise ValueError(f'{key}: unique id required')
            ids[e['id']] = e
    shells = [p for p in g['parts'] if p['kind'] == 'shell']
    if not 1 <= len(shells) <= 20:
        raise ValueError('1..20 shells required')
    heads = [p for p in g['parts'] if p['kind'] == 'head']
    if sorted(p.get('side', '') for p in heads) != ['A', 'B']:
        raise ValueError('Heads A and B required')
    diagnostics = []
    def warn(e, field, message):
        diagnostics.append(dict(entity_id=e.get('id'), field=field, severity='warning', message=message))
    for p in g['parts']:
        if p['kind'] not in ('shell', 'head', 'cover'):
            raise ValueError('Unknown part kind')
        for key, value in p.get('dimensions', {}).items():
            if value is not None:
                finite(value, key, positive=True)
        if p['kind'] == 'cover' and ids.get(p.get('parent_id'), {}).get('kind') != 'manway':
            raise ValueError('Cover must belong to a manway')
        if not p.get('dimension_source'):
            warn(p, 'dimensions', 'Источник размеров не подтверждён')
    part_ids = {p['id'] for p in g['parts']}
    for e in g['elements'] + g['control_points']:
        owner = ids.get(e.get('parent_id', e.get('owner_id')))
        if owner is None or owner is e:
            raise ValueError(f'{e["id"]}: unknown owner')
        if e in g['elements'] and owner['id'] not in part_ids:
            raise ValueError('Element must belong to a part')
        p = e.get('placement', {})
        if p.get('mode') == 'schematic':
            for axis in ('u', 'v'):
                if not 0 <= finite(p.get(axis), axis) <= 1:
                    raise ValueError('Schematic coordinate outside 0..1')
        elif p.get('mode') == 'physical':
            p['theta_deg'] = finite(p.get('theta_deg'), 'theta_deg') % 360
            shell = owner['kind'] == 'shell'
            coordinate = 'z_local_mm' if shell else 'radius_projection_mm'
            distance = finite(p.get(coordinate), coordinate)
            limit = owner.get('dimensions', {}).get('length_mm' if shell else 'diameter_mm')
            if limit is None or distance < 0 or distance > limit / (1 if shell else 2):
                raise ValueError(f'{e["id"]}: coordinate outside owner or missing dimension')
        else:
            raise ValueError('Unknown placement mode')
    for w in g['welds']:
        connected = w.get('connected_part_ids', [])
        if not connected or any(i not in part_ids for i in connected):
            raise ValueError('Weld references missing part')
        if w['kind'] == 'circumferential' and len(connected) != 2:
            raise ValueError('Ring weld must connect exactly two parts')
        if w['kind'] == 'head_joint':
            owner=ids[connected[0]]
            diameter=owner.get('dimensions',{}).get('diameter_mm')
            if owner['kind'] not in ('head','cover') or not diameter or abs(finite(w.get('geometry',{}).get('offset_mm'),'head seam offset')) >= diameter/2:
                raise ValueError('Head seam must be inside a dimensioned disk')
        if w['kind'] == 'longitudinal':
            w['geometry']['theta_deg'] = finite(w.get('geometry', {}).get('theta_deg'), 'weld angle') % 360
        if w['kind'] == 'attachment':
            element=ids.get(w.get('geometry',{}).get('element_id'))
            if not element or element.get('parent_id') not in connected:
                raise ValueError('Attachment weld must reference its own element')
    weld_ids = {w['id'] for w in g['welds']}
    for z in g['control_zones']:
        if z.get('weld_id') not in weld_ids:
            raise ValueError('Zone references missing weld')
        if not z.get('planned_methods') or any(m not in ('УЗК', 'МК', 'ПВК', 'ВИК', 'ТВ') for m in z['planned_methods']):
            raise ValueError('Invalid control method')
        c = z.get('coverage', {})
        if c.get('kind') == 'sector':
            a, b = finite(c.get('start'), 'sector start'), finite(c.get('end'), 'sector end')
            c['start'], c['end'] = a % 360, b % 360
            c['span_deg'] = (b-a) % 360
            if c['span_deg'] == 0:
                raise ValueError('Use whole coverage for a full circle')
        elif c.get('kind') == 'interval':
            a, b = finite(c.get('start'), 'start'), finite(c.get('end'), 'end')
            if not 0 <= a < b <= 1:
                raise ValueError('Interval must satisfy 0 <= start < end <= 1')
        elif c.get('kind') != 'whole':
            raise ValueError('Invalid coverage')
    for section in g.get('sections', []):
        owner = ids.get(section.get('owner_id'))
        if not owner or section.get('kind') not in ('ovality','weld_profile'):
            raise ValueError('Section references missing owner or has invalid kind')
        if section['kind'] == 'ovality':
            length = owner.get('dimensions',{}).get('length_mm')
            if owner['kind'] != 'shell' or length is None or not 0 <= finite(section.get('z_local_mm'),'section position') <= length:
                raise ValueError('Ovality section must be inside a dimensioned shell')
    # Detect cycles through nested covers/elements before projection.
    for e in g['parts'] + g['elements']:
        seen = set()
        current = e
        while current.get('parent_id'):
            if current['id'] in seen:
                raise ValueError('Cyclic ownership')
            seen.add(current['id'])
            current = ids[current['parent_id']]
    if not g.get('coordinate_frame', {}).get('confirmed'):
        warn({}, 'coordinate_frame', 'Подтвердите ноль и направление отсчёта')
    g['diagnostics'] = diagnostics
    return g


def position(e: dict, owner: dict, cut: float = 0) -> tuple[float, float]:
    p = e['placement']
    if p['mode'] == 'schematic':
        return p['u'], p['v']
    angle = (p['theta_deg']-(cut if owner['kind']=='shell' else 0)) % 360
    if owner['kind'] == 'shell':
        return p['z_local_mm']/owner['dimensions']['length_mm'], angle/360
    r = p['radius_projection_mm']/owner['dimensions']['diameter_mm']
    return .5+r*math.sin(math.radians(angle)), .5-r*math.cos(math.radians(angle))


def render_v2(g: dict, width: int, height: int, *, detail: str | None = None, layer: str | None = None, vector_canvas=None, svg=False, exterior_b=False):
    from PIL import Image, ImageDraw
    from vessel_scheme_renderer import _font
    from vessel_elements import draw_symbol
    img = Image.new('RGB', (width, height), 'white')
    d = ImageDraw.Draw(img)
    if vector_canvas is not None or svg:
        from vessel_vector import VectorDraw
        d=VectorDraw(width,height,vector_canvas)
    font = _font(14)
    horizontal = g['orientation'] == 'horizontal'
    cut = (g.get('views') or [{}])[0].get('cut_angle_deg', 0)
    parts = {p['id']: p for p in g['parts']}
    entities = {e['id']: e for e in g['parts']+g['elements']}
    rects = {}
    if detail in parts:
        rects[detail] = (100, 85, width-100, height-100)
        if parts[detail]['kind'] != 'shell':
            r = min(width-200, height-185)/2
            rects[detail] = (width/2-r, height/2-r, width/2+r, height/2+r)
    else:
        shells = [p for p in g['parts'] if p['kind'] == 'shell']
        known = all(p.get('dimensions', {}).get('length_mm') for p in shells)
        lengths = [p['dimensions']['length_mm'] if known else 1 for p in shells]
        body = (width*.18, 100, width*.80, 100+height*.68) if horizontal else (160, height*.24, width-160, height*.78)
        cursor = 0
        for p, length in zip(shells, lengths):
            a, b = cursor/sum(lengths), (cursor+length)/sum(lengths)
            x1,y1,x2,y2 = body
            rects[p['id']] = (x1+(x2-x1)*a,y1,x1+(x2-x1)*b,y2) if horizontal else (x1,y1+(y2-y1)*a,x2,y1+(y2-y1)*b)
            cursor += length
        diameter = min(width*.15, (height-250)*.8) if horizontal else min(height*.14, width*.4)
        for p in parts.values():
            if p['kind'] != 'head': continue
            a = p['side'] == 'A'
            cx,cy = (width*(.09 if a else .90), height*(.46 if a else .37)) if horizontal else (width/2,height*(.14 if a else .88))
            rects[p['id']] = (cx-diameter/2,cy-diameter/2,cx+diameter/2,cy+diameter/2)
        covers = [p for p in parts.values() if p['kind']=='cover']
        for i,p in enumerate(covers):
            diameter=min(width*.15,height*.30/len(covers));cx=width*.90;cy=height*(.64+.30*(i+.5)/len(covers))
            rects[p['id']] = (cx-diameter/2,cy-diameter/2,cx+diameter/2,cy+diameter/2)
    def radius(e, rect):
        owner=entities[e['parent_id']]; dims=owner.get('dimensions',{})
        scale=((rect[2]-rect[0] if horizontal else rect[3]-rect[1])/(dims.get('length_mm') or 2000)) if owner['kind']=='shell' else (rect[2]-rect[0])/(dims.get('diameter_mm') or 2000)
        try: diameter=float(e.get('dimensions',{}).get('diameter_mm') or e.get('dn') or 100)
        except (ValueError,TypeError):diameter=100
        return max(14 if owner['kind']=='shell' and any(p['owner_id']==e['id'] for p in g['control_points']) else 9,min(38,diameter*scale/2))
    d.text((20,12),f'Сосуд • рев. {g["revision"]} • {parts[detail]["designation"] if detail in parts else "Общий вид"} • {layer or "Все методы"}',font=_font(18),fill='black')
    d.text((20,40),f'A → B · со стороны A · по часовой стрелке · разрез {cut}°',font=font,fill='black')
    if detail in parts:
        dims=parts[detail].get('dimensions',{})
        dim_text=' · '.join(f'{label}: {dims.get(key) or "не задано"} мм' for key,label in [('length_mm','Длина'),('diameter_mm','Диаметр'),('thickness_mm','Толщина')])
    else:
        lengths=[p.get('dimensions',{}).get('length_mm') for p in parts.values() if p['kind']=='shell']
        dim_text=f'Длина корпуса: {sum(lengths) if all(lengths) else "не задана"} мм · обечаек: {len(lengths)}'
    d.text((20,64),dim_text,font=font,fill='black')
    for id,r in rects.items():
        if svg: d.begin_entity(id)
        if parts[id]['kind']=='shell': d.rectangle(r,outline='black',width=2)
        else: d.ellipse(r,outline='black',width=2)
        d.text((r[0]+6,r[1]+6 if parts[id]['kind']=='shell' else r[3]+4),parts[id]['designation'],font=_font(10 if parts[id]['kind']=='shell' else 14),fill='black')
        if svg: d.end_entity()
    for section in g.get('sections',[]):
        if section.get('kind') != 'ovality' or section['owner_id'] not in rects:continue
        owner=parts[section['owner_id']];x1,y1,x2,y2=rects[owner['id']]
        q=section['z_local_mm']/owner['dimensions']['length_mm']
        a,b=((x1+(x2-x1)*q,y1),(x1+(x2-x1)*q,y2)) if horizontal else ((x1,y1+(y2-y1)*q),(x2,y1+(y2-y1)*q))
        for i in range(0,24,2):
            d.line([(a[0]+(b[0]-a[0])*i/24,a[1]+(b[1]-a[1])*i/24),(a[0]+(b[0]-a[0])*(i+1)/24,a[1]+(b[1]-a[1])*(i+1)/24)],fill='gray')
        d.text((a[0]+4,a[1]+18),section['designation'],font=font,fill='black')
    for w in g['welds']:
        if w['kind']=='attachment':continue
        ids=[i for i in w['connected_part_ids'] if i in rects and parts[i]['kind']=='shell']
        if w['kind']=='head_joint':
            owner=parts[w['connected_part_ids'][0]];r=rects.get(owner['id'])
            if r:
                offset=w['geometry']['offset_mm']/owner['dimensions']['diameter_mm']*(r[3]-r[1]);cx=(r[0]+r[2])/2;cy=(r[1]+r[3])/2+offset
                half=math.sqrt(max(0,((r[2]-r[0])/2)**2-offset**2))
                d.line([(cx-half,cy),(cx+half,cy)],fill='black',width=2);d.text((cx+8,cy+3),w['designation'],font=_font(11),fill='black')
            continue
        if not ids: continue
        x1,y1,x2,y2=rects[ids[0]]
        if w['kind']=='longitudinal':
            q=((w['geometry']['theta_deg']-cut)%360)/360
            a,b=((x1,y1+(y2-y1)*q),(x2,y1+(y2-y1)*q)) if horizontal else ((x1+(x2-x1)*q,y1),(x1+(x2-x1)*q,y2))
        else:
            first=ids[0]==w['connected_part_ids'][-1]
            a,b=((x1 if first else x2,y1),(x1 if first else x2,y2)) if horizontal else ((x1,y1 if first else y2),(x2,y1 if first else y2))
        d.line([a,b],fill='black',width=2)
        label_at=(a[0]+3,a[1]-20) if w['kind']=='circumferential' else ((a[0]+b[0])/2-10,a[1]+4 if q>.65 else a[1]-18) if horizontal else (a[0]+4,(a[1]+b[1])/2)
        d.text(label_at,w['designation'],font=_font(12),fill='black')
        for z in g['control_zones']:
            if z['weld_id']!=w['id'] or (layer and layer not in z['planned_methods']):continue
            coverage=z['coverage'];whole=coverage['kind']=='whole'
            sector=coverage['kind']=='sector'
            start=0 if whole else ((coverage['start']-cut)%360/360 if sector else coverage['start'])
            span=1 if whole else ((coverage['end']-coverage['start'])%360/360 if sector else coverage['end']-coverage['start'])
            for i in range(61):
                if i/60>span:break
                q=(start+i/60)%1
                x,y=a[0]+(b[0]-a[0])*q,a[1]+(b[1]-a[1])*q
                d.line([(x-3,y-3),(x+3,y+3)],fill='black',width=2)
    marks={}
    label_boxes=[]
    for e in g['elements']+g['control_points']:
        if e.get('archived'):continue
        owner=entities[e.get('parent_id',e.get('owner_id'))]
        r=rects.get(owner['id'])
        if r is None and owner['id'] in marks:
            x,y=marks[owner['id']];rr=radius(owner,rects[owner['parent_id']]);r=(x-rr,y-rr,x+rr,y+rr)
        if r is None:continue
        u,v=position(e,owner,cut)
        if exterior_b and owner.get('side')=='B':u=1-u
        if owner['kind']=='shell' and not horizontal:u,v=v,u
        x,y=r[0]+u*(r[2]-r[0]),r[1]+v*(r[3]-r[1]);marks[e['id']]=(x,y)
        point='owner_id' in e
        if point and layer and layer!='УЗТ':continue
        if svg: d.begin_entity(e['id'])
        if point:
            d.line([(x-3,y-3),(x+3,y+3)],fill='black',width=2);d.line([(x-3,y+3),(x+3,y-3)],fill='black',width=2);label=str(e.get('body_number',e['local_number']))
        else:
            if e['kind'] in ('nozzle','manway'):
                rr=radius(e,r);d.ellipse((x-rr,y-rr,x+rr,y+rr),outline='black',width=1)
                if e['kind']=='manway':d.ellipse((x-rr*.87,y-rr*.87,x+rr*.87,y+rr*.87),outline='black',width=1)
                d.line([(x-rr-4,y),(x+rr+4,y)],fill='gray');d.line([(x,y-rr-4),(x,y+rr+4)],fill='gray')
            else:draw_symbol(d,x,y,e['kind'])
            label=e['designation']
            for w in g['welds']:
                if w['kind']!='attachment' or w['geometry']['element_id']!=e['id']:continue
                for z in g['control_zones']:
                    if z['weld_id']!=w['id'] or (layer and layer not in z['planned_methods']):continue
                    rr=radius(e,r)+3
                    for i in range(72):
                        angle=i*5;cov=z['coverage']
                        if cov['kind']=='sector' and (angle-cov['start'])%360>(cov['end']-cov['start'])%360:continue
                        a=math.radians(angle)
                        d.line([(x+rr*math.sin(a),y-rr*math.cos(a)),(x+(rr+4)*math.sin(a+.03),y-(rr+4)*math.cos(a+.03))],fill='black')
                    d.text((x+rr+8,y+rr),z['designation'],font=_font(10),fill='black')
        offset=(g.get('views') or [{}])[0].get('label_overrides',{}).get(e['id'],{})
        dx,dy=offset.get('dx',-3 if point else -20),offset.get('dy',-16 if point else -30)
        if point and owner['kind'] not in ('shell','head','cover') and not offset:
            dx,dy={1:(-12,-5),2:(5,-5),3:(-3,-16),4:(-3,6)}.get(e['local_number'],(5,-12))
        tx,ty=x+dx,y+dy
        label_width=max(14,len(label)*8)
        if not offset and not point:
            for attempt in range(30):
                box=(tx,ty,tx+label_width,ty+16)
                if not any(box[0]<b[2]+3 and box[2]+3>b[0] and box[1]<b[3]+3 and box[3]+3>b[1] for b in label_boxes): break
                ty+=18
            tx=min(max(6,tx),width-label_width-6)
        label_boxes.append((tx,ty,tx+label_width,ty+16))
        if not point or offset:d.line([(x,y),(tx,ty)],fill='gray')
        d.text((tx,ty),label,font=_font(10 if point else 13),fill='black')
        if svg: d.end_entity()
    if detail is None:
        for section in g.get('sections',[]):
            if section['kind']!='weld_profile':continue
            x=width*.83;y=110
            d.text((x,y-24),section['designation']+' · профиль шва',font=_font(11),fill='black')
            d.rectangle((x+60,y+8,x+90,y+28),outline='black')
            d.line([(x,y+18),(x+155,y+18)],fill='black')
            for i in range(5):
                px=x+15+i*30;d.line([(px-2,y+15),(px+2,y+21)],fill='black');d.line([(px-2,y+21),(px+2,y+15)],fill='black');d.text((px-3,y-5),str(i+1),font=_font(9),fill='black')
            d.text((x,y+36),'Металл · ЗТВ · шов · ЗТВ · металл',font=_font(9),fill='black')
            break
        d.text((width*.20,height-72),'× Точка УЗТ    К — кольцевой шов    П — продольный / шов днища',font=_font(12),fill='black')
        d.text((width*.20,height-52),'Штриховка — участок НК    I–III — сечения овальности    Крышка Т — отдельная деталь',font=_font(12),fill='black')
    methods=[layer] if layer else sorted({m for z in g['control_zones'] for m in z['planned_methods']})
    d.text((20,height-38),'План контроля. Методы: '+(', '.join(methods) or 'не заданы')+'. Значения измерений не назначены.',font=font,fill='black')
    if vector_canvas is not None or svg:
        return d.finish(),g,[]
    out=io.BytesIO();img.save(out,format='PNG')
    return out.getvalue(),g,[]


def render_profile(geometry, section):
    from PIL import Image, ImageDraw
    from vessel_scheme_renderer import _font
    image=Image.new('RGB',(1190,842),'white');draw=ImageDraw.Draw(image)
    draw.text((35,30),f'{section["designation"]} • профиль пяти позиций • рев. {geometry["revision"]}',font=_font(24),fill='black')
    draw.text((35,75),f'Метод: {section.get("method") or "не задан"}. План контроля, не результаты.',font=_font(18),fill='black')
    draw.line([(100,400),(1090,400)],fill='black',width=3)
    for i,title in enumerate(section.get('positions') or ['Основной металл','ЗТВ','Шов','ЗТВ','Основной металл']):
        x=150+i*210
        draw.ellipse((x-5,395,x+5,405),fill='black')
        draw.text((x-65,435),f'{i+1}. {title}',font=_font(16),fill='black')
    output=io.BytesIO();image.save(output,format='PNG');return output.getvalue()
