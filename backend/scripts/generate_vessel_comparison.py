"""Reproducible, synthetic vessel fixtures for document layout QA (no database writes)."""
import copy
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from word_generator import WordGenerator
from report_snapshot import save_report_snapshot, load_technical_report_snapshot
from scripts.test_official_form_fillers import _base_data


def fixture(length, serial, name, variant, root):
    count = (length + 1999) // 2000
    nominal = 10 if variant == 1 else 12
    diameter = 2400 if variant == 1 else 1400
    shells = [dict(name=f'Обечайка {i+1}', length_mm=min(2000, length-i*2000), diameter_mm=diameter,
                   wall_thickness_mm=nominal, material='09Г2С', gost='ГОСТ 19281', weld_data='Автоматическая сварка') for i in range(count)]
    heads = [dict(name=n, length_mm=640, diameter_mm=diameter, wall_thickness_mm=nominal, material='09Г2С', gost='ГОСТ 19281', weld_data='Автоматическая сварка') for n in ['Днище левое', 'Днище правое']]
    measurements = [dict(location=e['name'], element=e['name'], element_name=e['name'], point_number=j,
                         section_number=str(j), thickness=round(nominal-0.1-((i+j)%5)*0.1, 1), nominal_thickness=nominal,
                         x_percent=20+60*(i+.2+(j-1)%3*.25)/(count+2), y_percent=30+10*((j-1)//3))
                    for i,e in enumerate(shells+heads) for j in range(1,13)]
    task = dict(uzk_sections=4 if variant == 1 else 2, mpk_sections=3 if variant == 1 else 0,
                pvk_sections=0 if variant == 1 else 2, hardness_sections=3 if variant == 1 else 2)
    welds = [dict(weld_number=f'К{i+1}', area_number=str(i+1), control_method=method,
                  defect_description='Дефектов не обнаружено', description='Недопустимые индикации отсутствуют',
                  conclusion='годен', defect_number='—', equivalent_area='—', depth='—', length='—', location=f'К{i+1}/П{i+1}')
             for method,key in [('UZK','uzk_sections'),('MPK','mpk_sections'),('PVK','pvk_sections')] for i in range(task[key])]
    hardness = [dict(weld_number=f'К{i+1}/П{i+1}', area_number=str(i+1), location=f'К{i+1}/П{i+1}',
                     allowed_hardness_base='120–180', allowed_hardness_weld='225',
                     hardness_base_t1=146+i, hardness_base_t5=149+i, hardness_weld=162+i,
                     hardness_haz_t2=155+i, hardness_haz_t4=153+i) for i in range(task['hardness_sections'])]
    pressure = '0,7' if variant == 1 else '1,2'
    data = _base_data(vessel_name=name, equipment_device_name=name, serial_number=serial, reg_number=f'К-{variant}79',
        report_form_id='to-1', body_length_mm=length, diameter=str(diameter), wall_thickness=str(nominal),
        vessel_elements=shells+heads, thickness_measurements=measurements, hardness_tests=hardness, weld_inspections=welds,
        technical_task=task, working_pressure=pressure, allowed_pressure=pressure,
        working_temperature='40', allowed_temperature='40', design_temperature='60', min_wall_temperature='минус 40',
        design_pressure='1,6', test_pressure='2,0', working_medium='Нефтегазовая смесь' if variant == 1 else 'Воздух',
        volume='50' if variant == 1 else '10', scheme_index=f'С-{variant}',
        organization='ООО «Контрольный заказчик»', location=f'Площадка диагностики № {variant}',
        opo_name='Площадка подготовки продукции', opo_code=f'А00-00000-00{variant}', opo_hazard_class='II',
        contract_number='КП-26/09 от 01.09.2026', source_report_number=f'ТО-ПРОВЕРКА-{variant}',
        report_number=f'ТО-ПРОВЕРКА-{variant}', protocol_number=f'ТО-ПРОВЕРКА-{variant}', purpose='сепарации нефтегазовой смеси' if variant == 1 else 'накопления сжатого воздуха',
        manufacturer='Завод контрольного оборудования', manufacturing_year='2012', commissioning_year='2013',
        functional_params=f'Рабочее давление {pressure} МПа; температура 40 °C.', vibration='Вибрация не выявлена',
        support_state='Опоры работоспособны', kip_state='КИП работоспособны', manometer_verification='Поверка действительна до 18.09.2027',
        functional_checks=[dict(name='Герметичность', result='Течей не обнаружено'),dict(name='Рабочие параметры', result=f'{pressure} МПа, 40 °C')],
        operational_conclusion='Отклонений при оперативном диагностировании не выявлено.',
        visual_defects=[], has_external_defects=False, has_internal_defects=False,
        vik_conclusion='При наружном и внутреннем осмотре недопустимых дефектов не обнаружено.',
        doc_analysis_conclusion='Представленная техническая документация идентифицирует сосуд и условия эксплуатации.',
        operating_conditions_conclusion='Условия эксплуатации соответствуют представленным паспортным характеристикам.',
        epb_compliance_analysis='Оценка выполнена по перечню нормативных документов, указанному в исходном отчёте.',
        uzt_conclusion='Измеренные толщины не ниже допустимых значений, приведённых в расчётных данных.',
        hardness_conclusion='Измеренные значения твёрдости находятся в установленных пределах.',
        mpk_conclusion='Недопустимых индикаций не обнаружено.' if task['mpk_sections'] else 'Техническим заданием не предусмотрен.',
        pvk_conclusion='Недопустимых индикаций не обнаружено.' if task['pvk_sections'] else 'Техническим заданием не предусмотрен.',
        uzk_conclusion='Дефекты, превышающие браковочный уровень, не обнаружены.',
        ovality_measurements=[dict(section_number=str(i+1),max_diameter=diameter+2,min_diameter=diameter-2,deviation_percent=round(400/diameter,3), allowed_ovality='1,0') for i in range(count)],
        deflection_measurements=[dict(section_number=str(i+1),deflection_mm=2.0,deflection_percent=0.1) for i in range(count)],
        hydraulic_test_history=[dict(date='2026-09-18',type='гидравлическое',pressure='2,0',medium='вода',result='Течи и остаточные деформации не обнаружены')],
        hydrostatic_test=dict(date='2026-09-18',test_pressure='2,0',medium='вода',hold_time='10 мин',result='Течи и остаточные деформации не обнаружены'),
        residual_life_years='5',residual_life_until='18.09.2031',
        epb_conclusion=f'{name}, зав. № {serial}, соответствует требованиям промышленной безопасности при соблюдении установленных условий эксплуатации.',
        epb_conditions=f'Давление не выше {pressure} МПа, температура не выше 40 °C; контроль технического состояния по регламенту.',
        calculation_result='Значения фактической толщины превышают минимально допустимые значения из расчёта.',
        calculation_data=dict(method='По методике, указанной в техническом отчёте',residual_life_years=5,
            elements=[dict(element=e['name'], nominal_thickness=nominal,min_thickness=min(p['thickness'] for p in measurements if p['location']==e['name']),
                           min_allowed_thickness=nominal-2,corrosion_rate=0.04,residual_life_years=5,allowed_pressure=pressure,conclusion='Условия прочности выполняются') for e in shells+heads]),
        inspection_engineers=[dict(full_name='Иванов Иван Иванович',method='UZT',role='Специалист НК II уровня',certificate_number='КОНТРОЛЬ-01',valid_until='2027-09-18')],
        fittings=[dict(name='Предохранительный клапан',quantity=2,dn=80,pressure='1,6'),dict(name='Манометр',quantity=1,dn='—',pressure='1,6')],
        inspection_reglament=[dict(control_type='Наружный и внутренний осмотр, УЗТ',periodicity='По утверждённому регламенту',executor='Ответственное лицо',date='18.09.2028')],
    )
    from vessel_scheme_renderer import render_vessel_scheme, _layout_development, legend_height_px
    data['customer_address']='Контрольная площадка, административное здание'
    data['ndt_normative']='Технологическая карта ТК-ПРОВЕРКА (контрольный пример заполнения)'
    for code,instrument in [('vik','Комплект ВИК'),('functional','Манометр'),('uzt','Ультразвуковой толщиномер'),('uzk','Ультразвуковой дефектоскоп'),('mpk','Магнитный дефектоскоп'),('pvk','Комплект капиллярного контроля'),('hardness','Твердомер')]:
        data[f'{code}_instruments']=f'{instrument}, № ПРОВЕРКА-{variant}; контрольные данные прибора'
    from scheme_ndt_overlays import collect_scheme_overlays
    import math
    geometry={'equipment_kind':'vessel','orientation':'vertical','shell_count':count,'dimensions':{'shell_lengths_mm':[s['length_mm'] for s in shells], 'body_length_mm':length,'head_diameter_mm':diameter}}
    data['scheme_geometry']=geometry
    layout=_layout_development(geometry,1800,1100,margin_bottom=legend_height_px(geometry,collect_scheme_overlays(data),'uzt')+24)
    x0,y0,x1,y1=layout['body']
    for i,element in enumerate(shells+heads):
        for j,p in enumerate([p for p in measurements if p['location']==element['name']]):
            if i<count:
                x=x0+(x1-x0)*((j%4+.5)/4)
                y=y0+(y1-y0)*((i+(j//4+.5)/3)/count)
            else:
                cx,cy,r=layout['head_top' if i==count else 'head_bottom']
                a=2*math.pi*j/12;x=cx+r*.65*math.cos(a);y=cy+r*.65*math.sin(a)
            p['x_percent']=100*x/1800;p['y_percent']=100*y/1100
    scheme = root / f'scheme-{variant}.png'
    png,_,_ = render_vessel_scheme(geometry,width=1800,height=1100,scheme_layer='uzt',overlays=collect_scheme_overlays(data))
    scheme.write_bytes(png)  # QA preview only; production must render from snapshot geometry.
    inspection = dict(id=f'00000000-0000-0000-0000-00000000000{variant}',date_performed='2026-09-18',status='COMPLETED',data=data)
    equipment = dict(id=f'00000000-0000-0000-0001-00000000000{variant}',name=name,serial_number=serial,type_code='VESSEL',location=data['location'],attributes={})
    return inspection,equipment


def main():
    root = Path(sys.argv[1]).resolve();root.mkdir(parents=True,exist_ok=True)
    from report_org_settings import load_report_org_settings
    org=load_report_org_settings();org['contractor']['director_name']='Петров Пётр Петрович'
    org['customer']={'legal_name':'ООО «Контрольный заказчик»'}
    generator=WordGenerator()
    for variant,(length,serial,name) in enumerate([(11000,'КП-11001','Сепаратор НГС 50-0,9-2400'),(5500,'КП-05502','Ресивер РГС 10-1,6-1400')],1):
        inspection,equipment=fixture(length,serial,name,variant,root)
        technical=root/f'{variant}_Технический_отчет_{length}мм.docx'
        epb=root/f'{variant}_ЭПБ_{length}мм.docx'
        generator.generate_report_word(inspection,equipment,[],str(technical),'TECHNICAL_REPORT',org_settings=org)
        snapshot=technical.with_suffix('.docx.snapshot.json')
        if snapshot.exists(): snapshot.unlink()  # QA output only; production snapshots remain write-once.
        save_report_snapshot(technical,inputs=dict(inspection=inspection,equipment=equipment,ndt_methods=[],report_type='TECHNICAL_REPORT',org_settings=org),actor='layout-qa',form_id='to-1')
        source=load_technical_report_snapshot(technical,snapshot)
        epb_inspection=copy.deepcopy(source['inspection']);epb_inspection['data']['report_number']=f'ЭПБ-ПРОВЕРКА-{variant}'
        generator.generate_report_word(epb_inspection,source['equipment'],[],str(epb),'EXPERTISE',org_settings=org)
        (root/f'fixture-{variant}.json').write_text(json.dumps(source,ensure_ascii=False,indent=2),encoding='utf-8')
        print(technical.name,epb.name,flush=True)


if __name__=='__main__': main()
