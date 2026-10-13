"""Presentation policy for a single vessel drawing; never changes physical data."""
def sheet_spec(g):
    settings = g.get('print_settings') or {}
    dense = (sum(p['kind']=='shell' for p in g['parts']) > 5 or
             len(g['elements']) > 16 or len(g['control_points']) > 100)
    paper = settings.get('paper', 'auto')
    if paper not in ('A4', 'A3'): paper = 'A3' if dense else 'A4'
    landscape = g.get('orientation') == 'horizontal'
    short, long = (297,420) if paper=='A3' else (210,297)
    return dict(paper=paper, width_mm=long if landscape else short,
                height_mm=short if landscape else long,
                width=1190 if landscape else 842, height=842 if landscape else 1190)

def draw_profile(d, x, y, width=170, scale=1):
    """Five positions perpendicular to a horizontal weld, matching Visio A–A."""
    from vessel_scheme_renderer import _font
    h=120*scale; cx=x+width*.25; mid=y+h/2
    d.rectangle((x,mid-22*scale,x+width*.50,mid+22*scale),fill='#eeeeee',outline='black')
    d.rectangle((x,mid-7*scale,x+width*.50,mid+7*scale),fill='#aaaaaa',outline='black')
    for i,dy in enumerate([-45,-17,0,17,45]):
        yy=mid+dy*scale
        d.line([(cx-3*scale,yy-3*scale),(cx+3*scale,yy+3*scale)],width=1,fill='black')
        d.line([(cx-3*scale,yy+3*scale),(cx+3*scale,yy-3*scale)],width=1,fill='black')
        d.text((cx+5*scale,yy-7*scale),str(i+1),font=_font(round(10*scale)),fill='black')
    for text,dy in [('Осн. металл',-45),('ЗТВ',-17),('Шов',0),('ЗТВ',17),('Осн. металл',45)]:
        d.text((x+width*.53,mid+dy*scale-6*scale),text,font=_font(round(9*scale)),fill='black')

def main_element_rows(elements, data):
    """Group passport rows only; retain shell IDs and every measurement elsewhere."""
    groups={}; heads=[]
    for original in elements:
        e=dict(original); name=str(e.get('name') or e.get('designation') or '').lower()
        kind=e.get('element_type') or e.get('kind')
        shell=kind=='shell' or 'обечай' in name or name in ('корпус','shell')
        head=kind=='head' or 'днищ' in name
        if not shell and not head: continue
        if head: heads.append(e);continue
        # Unknown material/size does not justify merging different rows.
        fields=('diameter','diameter_mm','outer_diameter','wall_thickness_mm','nominal_thickness','thickness','wall_thickness','calc_thickness','steel_grade','material','gost','material_gost','weld_type','weld_data','electrodes','yield_strength','tensile_strength','elongation','reduction','impact','temperature','test_temperature','specimen_type')
        key=tuple(str(e.get(k) or '') for k in fields)
        if not any(key):key=key+(str(e.get('id') or name),)
        if key not in groups:groups[key]={**e,'name':'Обечайка','quantity':0,'length_mm':'','length':'','height':''}
        groups[key]['quantity']+=int(e.get('quantity') or 1)
    rows=list(groups.values())
    if len(rows)==1:
        rows[0]['length_mm']=data.get('shell_length') or data.get('height') or ''
    return rows+heads


def head_title(orientation, side):
    return ('Верхнее днище' if side == 'A' else 'Нижнее днище') if orientation == 'vertical' else ('Левое днище' if side == 'A' else 'Правое днище')

def orient_head_names(g):
    """A is the first/top end; IDs, coordinates and user designations stay intact."""
    defaults={'левое днище','правое днище','верхнее днище','нижнее днище','днище a','днище b','днище а','днище в'}
    for p in g.get('parts', []):
        if p.get('kind')=='head' and str(p.get('designation','')).strip().lower() in defaults:
            p['designation']=head_title(g.get('orientation'),p.get('side'))
    return g

def orient_report_names(data):
    from copy import deepcopy
    if not isinstance(data,dict):return {}
    data=deepcopy(data)
    geometry=(data.get('base_vessel_scheme') or {}).get('geometry') or {}
    if geometry.get('schema_version')!=2:return data
    orient_head_names(geometry)
    names={old:head_title(geometry.get('orientation'),side) for side,old_names in [('A',['Левое днище','Верхнее днище','Днище A']),('B',['Правое днище','Нижнее днище','Днище B'])] for old in old_names}
    def visit(value):
        if isinstance(value,list):
            for item in value:visit(item)
        elif isinstance(value,dict):
            for key,item in value.items():
                if key in ('name','element_name','location','designation') and isinstance(item,str) and item in names:value[key]=names[item]
                else:visit(item)
    visit(data)
    return data
