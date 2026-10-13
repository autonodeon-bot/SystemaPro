"""Editable reference topology. Dimensions/results are synthetic, not read from Visio."""
import json
import math
from pathlib import Path
from uuid import uuid5, NAMESPACE_URL

ROOT = Path(__file__).resolve().parents[1]
def ident(name): return str(uuid5(NAMESPACE_URL, 'systemapro:visio-reference:'+name))
g = dict(schema_version=2, model_id=ident('model'), revision=0, units='mm', equipment_kind='vessel', orientation='horizontal',
         coordinate_frame=dict(axis='A_to_B',view_from='A',clockwise=True,confirmed=True,zero_description='Учебный пример: верхняя образующая, вид слева A'),
         parts=[],elements=[],welds=[],control_points=[],control_zones=[],sections=[],control_templates=[],source_documents=[],
         source_note='Компоновка по примеру Visio. Размеры и результаты синтетические.',
         views=[dict(id=ident('view'),kind='development',cut_angle_deg=0,label_overrides={})])
source='ТЕСТ: условные размеры для демонстрации; не паспортные данные'
def part(name,kind,diameter=2000,**kw):
    p=dict(id=ident(name),kind=kind,designation=name,dimensions=dict(diameter_mm=diameter,thickness_mm=12),dimension_source=source,**kw)
    g['parts'].append(p);return p
heads=[part('Левое днище','head',side='A',head_type='elliptical'),part('Правое днище','head',side='B',head_type='elliptical')]
shells=[part(f'Обечайка {i+1}','shell') for i in range(6)]
for p,length in zip(shells,[1800,1800,1650,1100,1800,1900]):p['dimensions']['length_mm']=length
def placement(owner,u,v):
    if owner['kind']=='shell':return dict(mode='physical',z_local_mm=round(u*owner['dimensions']['length_mm'],3),theta_deg=v*360)
    return dict(mode='physical',radius_projection_mm=round(math.hypot(u-.5,v-.5)*owner['dimensions']['diameter_mm'],3),theta_deg=math.degrees(math.atan2(u-.5,.5-v))%360)
def point(owner,n,u,v,body=None):
    p=dict(id=ident(owner['id']+':point:'+str(n)),kind='point',owner_id=owner['id'],local_number=n,method='УЗТ',planned_methods=['УЗТ'],status='planned',placement=placement(owner,u,v))
    if body:p['body_number']=body
    g['control_points'].append(p)
    return p
for i,p in enumerate(shells):
    for row,v in enumerate([.10,.34,.65,.91]):
        for col,u in enumerate([.15,.49,.83]):point(p,row*3+col+1,u,v,i*12+row*3+col+1)
for p in heads:
    for i,u in enumerate([.10,.26,.40,.60,.74,.90]):point(p,i+1,u,.5)
    for i,v in enumerate([.08,.25,.41,.60,.75,.92]):point(p,i+7,.5,v)
chain=[heads[0],*shells,heads[1]]
for i,(a,b) in enumerate(zip(chain,chain[1:])):
    g['welds'].append(dict(id=ident(f'К{i+1}'),kind='circumferential',designation=f'К{i+1}',connected_part_ids=[a['id'],b['id']],geometry=dict(boundary_index=i)))
for i,(p,angles) in enumerate(zip(shells,[(244,110),(220,145),(245,112),(220,145),(245,112),(220,145)])):
    for j,angle in enumerate(angles):g['welds'].append(dict(id=ident(f'П{i*2+j+1}'),kind='longitudinal',designation=f'П{i*2+j+1}',connected_part_ids=[p['id']],geometry=dict(theta_deg=angle)))
for i,p in enumerate(heads):g['welds'].append(dict(id=ident(f'П{13+i}'),kind='head_joint',designation=f'П{13+i}',connected_part_ids=[p['id']],geometry=dict(offset_mm=-320)))
def element(owner,name,u,v,dn=150,kind='nozzle',measured=False):
    e=dict(id=ident(owner['id']+name),parent_id=owner['id'],kind=kind,designation=name,dn=dn,dimensions=dict(diameter_mm=dn,thickness_mm=10),dimension_source=source,attachment_to_vessel='welded',end_connection='flanged',placement=placement(owner,u,v))
    g['elements'].append(e)
    if measured:
        for n,(x,y) in enumerate([(0,.5),(1,.5),(.5,0),(.5,1)],1):point(e,n,x,y)
    return e
element(shells[0],'В',.48,.22,200);element(shells[0],'Г',.48,.78,250,measured=True)
for name,u in [('Н1',.22),('Н2',.40),('З1',.70)]:element(shells[1],name,u,.22,80)
element(shells[1],'Л',.65,.78,150,measured=True)
manway=element(shells[2],'Т',.50,.22,600,kind='manway',measured=True)
element(shells[4],'Е1',.45,.17,100);element(shells[4],'Е2',.45,.26,100);element(shells[4],'Д',.55,.78,100)
element(shells[5],'Б2',.3,.22,200);element(shells[5],'Б1',.7,.22,200);element(shells[5],'Ж',.55,.78,250,measured=True)
for name,u,v,dn,measured in [('П1',.34,.17,100,True),('С1',.68,.17,100,True),('И1',.18,.32,80,False),('К1',.81,.31,120,False),('И2',.17,.68,80,False),('К2',.81,.65,120,False),('Р',.32,.80,65,False),('С2',.67,.8,80,False),('М',.5,.87,80,False)]:element(heads[0],name,u,v,dn,measured=measured)
element(heads[1],'А',.5,.25,600,measured=True)
cover=part('Крышка люка Т','cover',600,parent_id=manway['id'])
for i,u in enumerate([.10,.26,.40,.60,.74,.90]):point(cover,i+1,u,.5)
element(cover,'З2',.5,.27,100,measured=True);cover_nozzle=element(cover,'З3',.5,.72,150,measured=True)
g['welds'].append(dict(id=ident('attachment-З3'),kind='attachment',designation='Шов З3',connected_part_ids=[cover['id']],geometry=dict(element_id=cover_nozzle['id'])))
g['control_zones'].append(dict(id=ident('zone-cover'),kind='weld_zone',designation='4 уч.',weld_id=ident('attachment-З3'),planned_methods=['УЗК'],coverage=dict(kind='whole')))
for i,(shell,q) in enumerate([(shells[0],.05),(shells[2],.9),(shells[5],.93)]):g['sections'].append(dict(id=ident(f'section{i}'),kind='ovality',owner_id=shell['id'],designation=['I–I','II–II','III–III'][i],z_local_mm=shell['dimensions']['length_mm']*q))
for i,(weld,method,start,end) in enumerate([('К2','УЗК',263,293),('К3','ПВК',268,304),('П3','МК',.62,.82)]):
    w=next(w for w in g['welds'] if w['designation']==weld)
    g['control_zones'].append(dict(id=ident(f'zone{i}'),kind='weld_zone',designation=f'{i+1} уч.',weld_id=w['id'],planned_methods=[method],coverage=dict(kind='interval' if weld.startswith('П') else 'sector',start=start,end=end)))
g['sections'].append(dict(id=ident('profile'),kind='weld_profile',owner_id=ident('К2'),designation='А–А',method='ТВ',positions=['Основной металл','ЗТВ','Шов','ЗТВ','Основной металл']))
payload=json.dumps(g,ensure_ascii=False,indent=2)+'\n'
for path in ['mobile/assets/data/visio_vessel_example.json','public/examples/visio-vessel.json']:
    dest=ROOT/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(payload,encoding='utf-8')
print(f'{len(g["parts"])} parts, {len(g["elements"])} elements, {len(g["control_points"])} points')
