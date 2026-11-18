from docx import Document
from docx.enum.text import WD_TAB_ALIGNMENT, WD_TAB_LEADER

from form_template_filler import (
    _cover_location, _iter_all_paragraphs, _main_sdt_tables, fill_vessel_form_to1,
)


def test_complete_mobile_data_reaches_the_official_report(tmp_path):
    output=tmp_path/'mobile-report.docx'
    data={'report_form_id':'to-1','vessel_name':'Тестовый сепаратор','manufacturer':'Завод инженера',
        'organization':'Заказчик / Цех 12','location':'Цех 12','documents':{'16':True},
        'documents_info':{'16':{'number':'ЭПБ-123','date':'2026-11-18','pages':'40'}},
        'uzt_schemes':[{'label':'Схема 1','measurements':[
            {'point_number':str(i+1),'element_name':f'Элемент {i+1}','thickness':9.3+i/10,
             'nominal_thickness':10.0,'min_allowed_thickness':4.9} for i in range(6)]}],
        'additional_data':{'profile_values':{'shell_material':'09Г2С'}},
        'conclusion':'Заключение инженера из сохранённого обследования'}
    fill_vessel_form_to1({'data':data}, {'name':'Тестовый сепаратор','attributes':{}},str(output),org_settings={})
    doc=Document(output)
    main=_main_sdt_tables(doc)
    documents=main[9]
    assert len(documents.rows)==18
    assert 'Заключение экспертизы промышленной безопасности' in documents.cell(16,1).text
    assert 'ЭПБ-123' in documents.cell(16,2).text
    assert '40' in documents.cell(16,3).text
    text='\n'.join(p.text for p in _iter_all_paragraphs(doc))
    assert 'аппараты воздушного охлаждения газа ______' not in text
    assert 'Заключение инженера из сохранённого обследования' in text
    assert '9,3' in text or '9.3' in text
    assert '09Г2С' in text
    refs=[p for p in _iter_all_paragraphs(doc) if 'Перечень применяемой' in p.text and 'Приложении' in p.text]
    assert refs and all('Приложении № 10' in p.text for p in refs)
    entries=[p for p in _iter_all_paragraphs(doc) if 'PAGEREF' in p._p.xml]
    assert entries
    assert all(p.paragraph_format.tab_stops[0].alignment==WD_TAB_ALIGNMENT.RIGHT for p in entries)
    assert all(p.paragraph_format.tab_stops[0].leader==WD_TAB_LEADER.DOTS for p in entries)


def test_cover_does_not_repeat_a_workshop_already_in_the_customer_hierarchy():
    assert _cover_location('Заказчик / Цех 12','Цех 12')=='Заказчик / Цех 12'
    assert _cover_location('Заказчик','Другая площадка')=='Заказчик, Другая площадка'


def test_landscape_table_formatting_does_not_add_empty_sections_on_repeat():
    from form_template_filler import _finalize_table_typography
    doc=Document()
    doc.add_paragraph('Перед таблицей')
    table=doc.add_table(rows=3,cols=8)
    table.cell(0,0).text='Параметр'
    doc.add_paragraph('После таблицы')
    _finalize_table_typography(doc)
    sections=len(doc.sections)
    _finalize_table_typography(doc)
    assert len(doc.sections)==sections
