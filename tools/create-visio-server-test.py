"""Creates only a labelled synthetic vessel through the ordinary authenticated APIs."""
import asyncio, json, io, zipfile, hashlib
from pathlib import Path
from datetime import timedelta
from uuid import uuid4, UUID
import requests
from sqlalchemy import select
from database import AsyncSessionLocal, engine
from models import User, Inspection, Questionnaire
from auth import create_access_token
from vessel_geometry_v2 import normalize_v2, render_v2
from vessel_snapshot_api import bind_plan
from vessel_vector import export_pdf
from form_media_helpers import collect_scheme_paths

OUT=Path('/app/uploads/visio_acceptance');OUT.mkdir(exist_ok=True)
async def identities():
    async with AsyncSessionLocal() as db:
        admin=(await db.execute(select(User).where(User.role=='admin',User.is_active==True).limit(1))).scalar_one()
        engineer=(await db.execute(select(User).where(User.username=='engineer',User.is_active==True))).scalar_one()
        return admin.username,engineer.username,str(engineer.id)
async def verify(ident):
    async with AsyncSessionLocal() as db:
        inspection=await db.get(Inspection,UUID(ident));questionnaire=await db.get(Questionnaire,inspection.questionnaire_id)
        assert inspection.data==questionnaire.data
        data=inspection.data
        assert len(data['thickness_measurements'])==138
        assert all(r['thickness'] is not None and r['scheme_point_id'] for r in data['thickness_measurements'])
        assert len({r['scheme_point_id'] for r in data['thickness_measurements']})==138
        files=collect_scheme_paths(data,{})
        assert len(files)>=10 and all(Path(f['path']).is_file() for f in files)
        return dict(points=138,files=len(files),questionnaire_matches=True)

def main():
    loop=asyncio.new_event_loop();admin,engineer,engineer_id=loop.run_until_complete(identities())
    def client(username):
        c=requests.Session();c.headers['Authorization']='Bearer '+create_access_token({'sub':username},timedelta(minutes=30));return c
    adm=client(admin);eng=client(engineer)
    def req(c,method,path,**kw):
        r=c.request(method,'http://127.0.0.1:8000'+path,timeout=240,**kw)
        if not r.ok:raise RuntimeError(f'{method} {path}: {r.status_code} {r.text[:500]}')
        return r
    statepath=OUT/'state.json';state=json.loads(statepath.read_text()) if statepath.exists() else {}
    name='[ТЕСТ VISIO] Сосуд В-138 — 6 обечаек, 25 элементов'
    if not state.get('equipment_id'):
        equipment=req(adm,'POST','/api/equipment',json=dict(name=name,serial_number='TEST-VISIO-138',location='Учебный объект — не эксплуатируется',attributes=dict(test_data=True,equipment_type='VESSEL',orientation='horizontal',diameter='2000',wall_thickness='12',manufacturer='Учебный изготовитель',manufacture_year='2020'))).json()
        state['equipment_id']=equipment['id'];statepath.write_text(json.dumps(state))
    eq=state['equipment_id']
    req(adm,'POST',f'/api/hierarchy/equipment/{eq}/assign-engineers',json={'user_ids':[engineer_id]})
    g=normalize_v2(json.loads(Path('/app/visio-vessel.json').read_text()))
    g.update(model_id=str(uuid4()),revision=1,base_revision=0,operation_id=str(uuid4()))
    data=dict(test_data=True,vessel_name=name,serial_number='TEST-VISIO-138',reg_number='УЧ-138',inventory_number='УЧ-2026-138',equipment_type='VESSEL',equipment_type_code='VESSEL',orientation='horizontal',
        report_form_id='to-1',inspection_type='NDT',inspection_date='2026-10-13',executors='Учебный инженер',organization='Учебная площадка',equipment_location='Демонстрационный стенд',
        manufacturer='Учебный изготовитель',manufacture_year='2020',commissioning_year='2021',purpose='Проверка конструктора и передачи данных в отчёт',diameter='2000',wall_thickness='12',
        working_pressure='1.0',design_pressure='1.6',test_pressure='2.0',working_temperature='40',design_temperature='100',working_medium='Вода (учебный пример)',medium_characteristics='Неопасная, учебный пример',
        vessel_group='4 (учебное значение)',medium_group='2 (учебное значение)',corrosion_allowance='2',volume='33.0',construction_type='Горизонтальный сварной сосуд: 6 обечаек и 2 эллиптических днища',
        designation='В-138',empty_mass='6200',load_cycles='1000',service_life='20',climatic_version='У1 (учебное значение)',
        operating_life='5 лет (учебное значение)',previous_inspection_result='Учебный пример: предыдущие натурные обследования отсутствуют',
        conclusion='ТЕСТОВЫЕ ДАННЫЕ. Размеры и замеры синтетические. Не является заключением о техническом состоянии.',technical_state='Не оценивалось — учебный пример',calculation_result='Расчёт прочности не выполнялся: учебные данные',residual_life_text='Не назначается: учебный пример',
        include_opo_data=False,documents={str(i):False for i in range(1,18)},documents_info={},documentation_conclusion='Учебный пример: реальные документы не приложены',
        matches_drawing=True,has_thermal_insulation=False,anticorrosion_coating_state='Учебная запись: покрытие без видимых повреждений',support_state='Учебная запись: опоры без видимых повреждений',
        vik_conclusion_text='Учебная запись ВИК. Оценка реального объекта не выполнялась.',uzk_conclusion_text='Учебная запись УЗК. Оценка реального объекта не выполнялась.',mpk_conclusion_text='Учебная запись МК. Оценка реального объекта не выполнялась.',
        vik_roughness='Rz 40 (учебное значение)',vik_illumination='500 лк (учебное значение)',repair_info='Учебный пример: ремонт не задан',accidents_info='Учебный пример: инциденты не заданы',supervisory_remarks='Учебный пример: не применимо',
        contract_number='ТЕСТ-138',contract_date='2026-10-13',work_period_from='2026-10-13',work_period_to='2026-10-13',work_basis='Проверка программного обеспечения',tech_card_number='ТЕСТ-НК-138')
    data=bind_plan(data,g)
    data['ovality_measurements']=[dict(section_number=s['designation'],max_diameter=2002+i,min_diameter=1998-i,deviation_percent=round((4+2*i)/2000*100,2)) for i,s in enumerate([s for s in g['sections'] if s['kind']=='ovality'])]
    entities={e['id']:e for e in g['parts']+g['elements']}
    points={p['id']:p for p in g['control_points']}
    for i,row in enumerate(data['thickness_measurements']):
        owner=entities[points[row['scheme_point_id']]['owner_id']]
        nominal=owner['dimensions']['thickness_mm']
        row.update(thickness=round(nominal-.35-(i%9)*.07,2),nominal_thickness=nominal,comment='СИНТЕТИЧЕСКИЙ ЗАМЕР — только проверка приложения')
    for row in data['weld_inspections']:row.update(result_status='recorded',defects='ТЕСТ: синтетическая запись без обнаруженных индикаций',conclusion='ТЕСТ: не заключение по реальному шву')
    for row in data['hardness_tests']:row.update(result_status='recorded',hardness_base_t1='150',hardness_haz_t2='152',hardness_weld='156',hardness_haz_t4='153',hardness_base_t5='151',comment='Учебные значения HB')
    data['vessel_elements']=[dict(name=e['designation'],element_type=e['kind'],material='09Г2С (учебное значение)',nominal_thickness=str(e['dimensions']['thickness_mm'])) for e in entities.values()]
    files={'photos/control_scheme.png':render_v2(g,1190,842)[0]}
    from PIL import Image, ImageDraw
    from vessel_scheme_renderer import _font
    plate=Image.new('RGB',(1200,550),'white');draw=ImageDraw.Draw(plate)
    draw.rectangle((15,15,1185,535),outline='black',width=4)
    for y,text in [(45,'УЧЕБНЫЙ МАКЕТ — НЕ ФОТО ЗАВОДСКОЙ ТАБЛИЧКИ'),(140,'Сосуд В-138     № TEST-VISIO-138'),(230,'D 2000 мм     L 10050 мм     стенка 12 мм'),(320,'Рраб 1,0 МПа     Tраб 40 °C     год 2020'),(425,'ТОЛЬКО ДЛЯ ТЕСТИРОВАНИЯ ПРИЛОЖЕНИЯ')]:draw.text((45,y),text,font=_font(32),fill='black')
    plate_stream=io.BytesIO();plate.save(plate_stream,format='PNG');files['photos/factory_plate.png']=plate_stream.getvalue()
    data['factory_plate_photo']='photos/factory_plate.png'
    data['additional_data']={'manual_verification_equipment':[dict(name='ТЕСТ: ультразвуковой толщиномер (макет)',serial_number='TEST-UT-138',verification_certificate_number='ТЕСТ — реальная поверка отсутствует',verification_date='2026-10-13',verification_expiry='2027-10-13',measurement_range='0,5–100 мм (учебное значение)',accuracy='±0,1 мм (учебное значение)')]}
    for part in g['parts']:
        path=f'photos/doc_vessel_detail_{part["id"]}.png'
        files[path]=render_v2(g,1190,842,detail=part['id'])[0]
        g['views'].append(dict(id=str(uuid4()),kind='part_detail',part_id=part['id'],designation=part['designation'],revision=1,document_number=f'vessel_detail_{part["id"]}',image_path=path))
    data['base_vessel_scheme'].update(source='constructor',geometry=g,image_path='photos/control_scheme.png')
    data['control_scheme_image']='photos/control_scheme.png'
    payload=dict(equipment_id=eq,data=data,status='DRAFT',date_performed='2026-10-13T00:00:00+03:00',conclusion=data['conclusion'])
    files['checklist.json']=json.dumps(payload,ensure_ascii=False).encode()
    manifest=dict(version=2,equipment_id=eq,checksums={k:hashlib.sha256(v).hexdigest() for k,v in files.items()})
    stream=io.BytesIO()
    with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED) as z:
        for name,content in files.items():z.writestr(name,content)
        z.writestr('manifest.json',json.dumps(manifest))
    if state.get('fixture_revision') != 3:
        previous_id=state.get('inspection_id')
        result=req(eng,'POST','/api/inspections/upload-archive',files={'file':('visio-example.zip',stream.getvalue(),'application/zip')}).json()
        state['inspection_id']=result['id'];state['fixture_revision']=3;statepath.write_text(json.dumps(state))
        if previous_id and previous_id!=result['id']:
            # Retire only this script's earlier synthetic fixture; normal data is untouched.
            old=req(eng,'GET',f'/api/vessel-scheme/inspections/{previous_id}').json()['data']
            assert old.get('test_data') and old.get('serial_number')=='TEST-VISIO-138'
            req(adm,'DELETE',f'/api/inspections/{previous_id}')
    ident=state['inspection_id']
    verified=loop.run_until_complete(verify(ident))
    saved=req(eng,'GET',f'/api/vessel-scheme/inspections/{ident}').json()['data']
    if saved['base_vessel_scheme']['geometry'].get('render_version') != 'visio-final':
        geo=saved['base_vessel_scheme']['geometry']
        geo.update(base_revision=geo['revision'],revision=geo['revision']+1,operation_id=str(uuid4()),render_version='visio-final')
        req(eng,'PUT',f'/api/vessel-scheme/inspections/{ident}',json={'geometry':geo})
        saved=req(eng,'GET',f'/api/vessel-scheme/inspections/{ident}').json()['data']
        verified=loop.run_until_complete(verify(ident))
    (OUT/'saved.json').write_text(json.dumps(saved,ensure_ascii=False,indent=2))
    (OUT/'drawing.pdf').write_bytes(export_pdf(saved['base_vessel_scheme']['geometry']))
    (OUT/'overview.png').write_bytes(render_v2(saved['base_vessel_scheme']['geometry'],1190,842)[0])
    report=req(eng,'POST','/api/reports/generate',json=dict(inspection_id=ident,report_type='TECHNICAL_REPORT',format='pdf')).json()
    state.update(verified,report=report)
    statepath.write_text(json.dumps(state,ensure_ascii=False,indent=2));print(json.dumps(state,ensure_ascii=False))
    loop.run_until_complete(engine.dispose());loop.close()
if __name__=='__main__':main()
