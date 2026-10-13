"""Authorized production acceptance test. Creates only an explicitly marked test vessel."""
import asyncio
import copy
import hashlib
import io
import json
import zipfile
import math
from datetime import timedelta
from pathlib import Path
from uuid import uuid4, UUID
import requests
from sqlalchemy import select
from database import AsyncSessionLocal, engine
from models import User, Inspection, Questionnaire
from auth import create_access_token
from vessel_geometry_v2 import normalize_v2, render_v2
from vessel_snapshot_api import bind_plan
from form_media_helpers import collect_scheme_paths

OUT = Path('/app/uploads/vessel_v2_acceptance')
OUT.mkdir(exist_ok=True)

async def identity():
    async with AsyncSessionLocal() as db:
        user = (await db.execute(select(User).where(User.role == 'admin', User.is_active == True).order_by(User.created_at).limit(1))).scalar_one()
        return user.username


async def verify_database(ident):
    async with AsyncSessionLocal() as db:
        inspection=await db.get(Inspection,UUID(ident))
        questionnaire=await db.get(Questionnaire,inspection.questionnaire_id)
        assert questionnaire.data==inspection.data
        for sheet in collect_scheme_paths(inspection.data,{}): assert Path(sheet['path']).is_file()
        return True

def main():
    loop = asyncio.new_event_loop()
    username = loop.run_until_complete(identity())
    token = create_access_token({'sub': username}, timedelta(minutes=30))
    class Client(requests.Session):
        def request(self, method, url, **kwargs):
            return super().request(method, 'http://127.0.0.1:8000' + url, timeout=240, **kwargs)
    client = Client()
    client.headers.update({'Authorization':f'Bearer {token}'})
    def request(method, path, **kwargs):
        r = client.request(method, path, **kwargs)
        if r.status_code >= 400: raise RuntimeError(f'{path}: {r.status_code} {r.text[:1600]}')
        return r
    results = {}
    results['health'] = request('GET','/health').json()
    forms = request('GET','/api/report-forms').json()
    assert len(forms) == 44
    results['forms'] = len(forms)
    for form in forms: assert request('GET',f'/api/report-forms/{form["id"]}/schema').json()
    g = json.loads(Path('/app/vessel-v2-fixture.json').read_text())
    g.update(model_id=str(uuid4()), revision=1, base_revision=0, operation_id=str(uuid4()), orientation='horizontal')
    g['coordinate_frame'].update(confirmed=True, zero_description='ТЕСТ: ноль по условной верхней образующей, вид от A')
    for p in g['parts']:
        p['dimension_source']='Синтетический приёмочный пример, не натурный замер'
        p['dimensions'].setdefault('diameter_mm', 2000 if p['kind']!='cover' else 600)
        p['dimensions']['thickness_mm']=12
    head = next(p for p in g['parts'] if p.get('side')=='A')
    cover = next(p for p in g['parts'] if p['kind']=='cover')
    for owner,count,radius in [(head,9,600)]:
        for i in range(count):
            element = dict(id=str(uuid4()),kind='nozzle',parent_id=owner['id'],designation=f'Ш-{owner.get("side","К")}-{i+1}',
                           dimensions={'diameter_mm':100},dn=100,dimension_source='ТЕСТ',
                           placement={'mode':'physical','theta_deg':i*360/count,'radius_projection_mm':radius if i<6 else 300})
            g['elements'].append(element)
    # Actual longitudinal welds are entered explicitly, separately from ring welds.
    for i,p in enumerate(x for x in g['parts'] if x['kind']=='shell'):
        g['welds'].append(dict(id=str(uuid4()),kind='longitudinal',designation=f'П{i+1}',connected_part_ids=[p['id']],geometry={'theta_deg':90 if i%2 else 270}))
    ring = next(w for w in g['welds'] if w['kind']=='circumferential')
    for method,coverage in [('УЗК',{'kind':'whole'}),('ПВК',{'kind':'sector','start':80,'end':120})]:
        g['control_zones'].append(dict(id=str(uuid4()),kind='weld_zone',designation=f'{method} {ring["designation"]}',weld_id=ring['id'],planned_methods=[method],coverage=coverage))
    g['sections']=[dict(id=str(uuid4()),kind='weld_profile',owner_id=ring['id'],designation='А–А',method='ТВ',positions=['Основной металл','ЗТВ','Шов','ЗТВ','Основной металл'])]
    g = normalize_v2(g)
    assert len([w for w in g['welds'] if w['kind']=='circumferential']) == 7
    assert len([p for p in g['control_points'] if p.get('body_number')]) == 72
    name='[ТЕСТ КОНСТРУКТОРА V2] 13.10.2026 — не производственный объект'
    # A persisted run descriptor permits inspection without accidentally creating repeated objects.
    state_file=OUT/'state.json'
    state=json.loads(state_file.read_text()) if state_file.exists() else {}
    if not state.get('equipment_id'):
        equipment=request('POST','/api/equipment',json={'name':name,'serial_number':'TEST-V2-20261013','location':'Тестовая среда данных на рабочем сервере','attributes':{'test_data':True,'purpose':'Приёмка конструктора, не эксплуатация'}}).json()
        state['equipment_id']=equipment['id'];state_file.write_text(json.dumps(state))
    data=bind_plan({'vessel_name':name,'serial_number':'TEST-V2-20261013','report_form_id':'to-1','inspection_date':'2026-10-13','test_data':True,
                   'diameter':'2000','wall_thickness':'12','working_pressure':'ТЕСТ','conclusion':'ТЕСТОВЫЕ ДАННЫЕ. Не является заключением о техническом состоянии.'},g)
    for i,row in enumerate(data['thickness_measurements']): row.update(thickness=10.25+(i%4)*.1,nominal_thickness=12,comment='Синтетическое значение для проверки передачи в отчёт')
    for row in data['weld_inspections']: row.update(result_status='recorded',defects='ТЕСТ: синтетическая запись контроля',conclusion='ТЕСТ, оценка не выполнялась')
    data['hardness_tests']=[{'section_profile_id':g['sections'][0]['id'],'weld_id':ring['id'],'model_revision':g['revision'],'area_number':'А–А','result_status':'recorded','comment':'ТЕСТОВЫЕ ДАННЫЕ','weld_number':ring['designation'],'hardness_base_t1':'150','hardness_haz_t2':'151','hardness_weld':'152','hardness_haz_t4':'153','hardness_base_t5':'154'}]
    files={'photos/control_scheme.png':render_v2(g,1190,842)[0]}
    views=[v for v in g['views'] if v.get('kind') not in ('part_detail','section_detail')]
    for part in g['parts']:
        file=f'photos/doc_vessel_detail_{part["id"]}.png'
        files[file]=render_v2(g,1190,842,detail=part['id'])[0]
        views.append(dict(id=str(uuid4()),kind='part_detail',part_id=part['id'],designation=part['designation'],revision=g['revision'],document_number=f'vessel_detail_{part["id"]}',image_path=file))
    g['views']=views
    data['base_vessel_scheme']={'source':'constructor','geometry':g,'image_path':'photos/control_scheme.png'}
    data['control_scheme_image']='photos/control_scheme.png'
    payload={'equipment_id':state['equipment_id'],'data':data,'status':'DRAFT','date_performed':'2026-10-13T00:00:00+03:00','conclusion':data['conclusion']}
    files['checklist.json']=json.dumps(payload,ensure_ascii=False).encode()
    manifest={'version':2,'equipment_id':state['equipment_id'],'checksums':{name:hashlib.sha256(value).hexdigest() for name,value in files.items()}}
    archive=io.BytesIO()
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for name,value in files.items():z.writestr(name,value)
        z.writestr('manifest.json',json.dumps(manifest))
    if not state.get('inspection_id'):
        first=request('POST','/api/inspections/upload-archive',files={'file':('test-vessel.zip',archive.getvalue(),'application/zip')}).json()
        repeat=request('POST','/api/inspections/upload-archive',files={'file':('test-vessel.zip',archive.getvalue(),'application/zip')}).json()
        assert first['id']==repeat['id']
        state.update(inspection_id=first['id'],archive_idempotent=True);state_file.write_text(json.dumps(state))
    ident=state['inspection_id']
    current=request('GET',f'/api/vessel-scheme/inspections/{ident}').json()['data']
    saved=current['base_vessel_scheme']['geometry']
    paths=collect_scheme_paths(current,{})
    assert len(paths)>=len(saved['parts'])+1
    assert all(Path(x['path']).is_file() and Path(x['path']).stat().st_size>100 for x in paths)
    assert len(current['thickness_measurements'])==78
    assert current['thickness_measurements'][0]['thickness']==10.25
    updated=copy.deepcopy(saved);updated.update(base_revision=saved['revision'],revision=saved['revision']+1,operation_id=str(uuid4()))
    updated['coordinate_frame']['zero_description']='ТЕСТ: повторно открыто и сохранено; ноль проверен'
    owners={p['id']:p for p in updated['parts']}
    for point in updated['control_points']:
        old=point['placement'];owner=owners[point['owner_id']]
        if old['mode']!='schematic':continue
        if owner['kind']=='shell':
            point['placement']={'mode':'physical','z_local_mm':old['u']*owner['dimensions']['length_mm'],'theta_deg':(old['v']*360+updated['views'][0]['cut_angle_deg'])%360}
        else:
            x,y=old['u']-.5,.5-old['v']
            point['placement']={'mode':'physical','radius_projection_mm':math.hypot(x,y)*owner['dimensions']['diameter_mm'],'theta_deg':math.degrees(math.atan2(x,y))%360}
        updated.setdefault('revision_history',[]).append({'entity_id':point['id'],'reason':'ТЕСТ: заданы точные координаты по синтетическому источнику','revision':updated['revision'],'old_placement':old})
    for cover in [p for p in updated['parts'] if p['kind']=='cover']:
        for i,element in enumerate(e for e in updated['elements'] if e['parent_id']==cover['id']):
            element['placement']={'mode':'physical','radius_projection_mm':180,'theta_deg':90+i*180}
    if not any(s.get('kind')=='ovality' for s in updated.get('sections',[])):
        shell=next(p for p in updated['parts'] if p['kind']=='shell')
        updated['sections'].append({'id':str(uuid4()),'kind':'ovality','owner_id':shell['id'],'designation':'I–I','z_local_mm':1000,'note':'ТЕСТ: сечение, без оценки годности'})
    response=request('PUT',f'/api/vessel-scheme/inspections/{ident}',json={'geometry':updated}).json()
    replay=request('PUT',f'/api/vessel-scheme/inspections/{ident}',json={'geometry':updated}).json()
    assert replay.get('replayed')
    stale=copy.deepcopy(updated);stale['operation_id']=str(uuid4())
    conflict=client.put(f'/api/vessel-scheme/inspections/{ident}',json={'geometry':stale})
    assert conflict.status_code==409
    reopened=request('GET',f'/api/vessel-scheme/inspections/{ident}').json()['data']
    assert reopened['thickness_measurements']==current['thickness_measurements']
    assert {p['id'] for p in reopened['base_vessel_scheme']['geometry']['control_points']}=={p['id'] for p in saved['control_points']}
    results['database_and_questionnaire_equal']=loop.run_until_complete(verify_database(ident))
    results.update(state, snapshot_idempotent=True, conflict_status=conflict.status_code, points=78, body_points=72, scheme_files=len(paths), measurement_1=10.25)
    (OUT/'reopened.json').write_text(json.dumps(reopened,ensure_ascii=False))
    vector=request('POST','/api/vessel-scheme/export?format=pdf',json={'geometry':response['geometry']})
    assert vector.content.startswith(b'%PDF');(OUT/'drawing.pdf').write_bytes(vector.content)
    report=request('POST','/api/reports/generate',json={'inspection_id':ident,'report_type':'TECHNICAL_REPORT','format':'pdf'}).json()
    results['report']=report
    (OUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
    print(json.dumps(results,ensure_ascii=False),flush=True)
    loop.run_until_complete(engine.dispose())
    loop.close()

if __name__=='__main__':main()
