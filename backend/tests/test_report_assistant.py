import uuid
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException, Response
from report_assistant import prepare_vessel_report
from report_assistant_api import ReviewedDraft, analyze, export_draft, load_source


def fixture():
    return {'id': str(uuid.uuid4()), 'data': {'report_form_id': 'to-1', 'serial_number': 'TEST-1',
            'working_pressure': '1,6', 'design_pressure': '1.8', 'volume': '2', 'wall_thickness': '8',
            'thickness_measurements': [{'thickness': '7,8'}, {'thickness': ''}, {'thickness': '7.9'}], 'defects': []}}, {}


def test_only_actual_measurements_count_and_empty_defects_are_not_a_verdict():
    i, e = fixture()
    r = prepare_vessel_report(i, e)
    assert r['measurements']['measured'] == 2
    assert r['measurements']['pending'] == 1
    assert r['measurements']['minimum_mm'] == '7.8'
    assert 'Пустой список не подтверждает отсутствие дефектов' in r['draft_text']
    assert r['llm_connected'] is False


@pytest.mark.parametrize('value', [True, 'NaN', 'Infinity', '-2', '0', {}, []])
def test_invalid_numbers_never_enter_measurement_summary(value):
    i, e = fixture(); i['data']['thickness_measurements'] = [{'thickness': value}]
    r = prepare_vessel_report(i, e)
    assert r['measurements']['measured'] == 0
    assert r['measurements']['invalid'] == 1


def test_conflict_omitted_and_pressure_contradiction_detected():
    i, e = fixture(); e['serial_number'] = 'DIFFERENT'; i['data']['working_pressure'] = '2'
    r = prepare_vessel_report(i, e)
    assert {'conflict_serial_number', 'pressure_conflict'} <= {x['code'] for x in r['findings']}
    assert 'TEST-1' not in r['draft_text']


def test_archived_points_excluded_and_duplicates_reported():
    i, e = fixture()
    i['data']['base_vessel_scheme'] = {'geometry': {'control_points': [{'id':'old','archived':True}]}}
    i['data']['thickness_measurements'] = [{'scheme_point_id':'old','thickness':'1'},
                                         {'scheme_point_id':'new','thickness':'7'}, {'scheme_point_id':'new','thickness':'8'}]
    r = prepare_vessel_report(i, e)
    assert r['measurements']['archived'] == 1
    assert r['measurements']['minimum_mm'] is None
    assert r['measurements']['duplicate_rows'] == 2
    assert r['measurements']['measured'] == 0
    assert 'duplicate_point' in {x['code'] for x in r['findings']}


def test_fingerprint_changes_with_equipment_or_data_and_preserves_inputs():
    import copy
    i, e = fixture(); original = copy.deepcopy(i)
    r = prepare_vessel_report(i, e)
    assert i == original
    e['serial_number'] = 'OTHER'
    assert r['source_fingerprint'] != prepare_vessel_report(i, e)['source_fingerprint']
    e.clear(); i['data']['volume'] = '3'
    assert r['source_fingerprint'] != prepare_vessel_report(i, e)['source_fingerprint']


def db_fixture(role='admin', active=True, own=True):
    i, e = fixture(); user = SimpleNamespace(id=uuid.uuid4(), username='test', role=role, is_active=active)
    inspection = SimpleNamespace(**i, equipment_id=uuid.uuid4(), created_by=user.id if own else uuid.uuid4())
    equipment = SimpleNamespace(id=inspection.equipment_id, type_id=None, attributes={})
    db = AsyncMock(); result = MagicMock(); result.scalar_one_or_none.return_value = user
    db.execute.return_value = result; db.get.side_effect = [inspection, equipment]
    return db, user, inspection


@pytest.mark.asyncio
@pytest.mark.parametrize('role,active', [('client',True), ('admin',False), ('unknown',True)])
async def test_forbidden_accounts_cannot_read_source(role, active):
    db, _, i = db_fixture(role, active)
    with pytest.raises(HTTPException) as exc: await load_source(uuid.UUID(i.id), 'test', db)
    assert exc.value.status_code == 403
    db.get.assert_not_awaited()


@pytest.mark.asyncio
async def test_unassigned_engineer_denied(monkeypatch):
    db, _, i = db_fixture('engineer', own=False)
    authorize = AsyncMock(side_effect=HTTPException(403, 'denied'))
    monkeypatch.setattr('report_assistant_api._authorize_equipment_write', authorize)
    with pytest.raises(HTTPException) as exc: await load_source(uuid.UUID(i.id), 'test', db)
    assert exc.value.status_code == 403
    authorize.assert_awaited_once()


@pytest.mark.asyncio
async def test_analysis_has_no_store_and_never_mutates_database():
    db, _, i = db_fixture(); response = Response()
    result = await analyze(uuid.UUID(i.id), response, 'test', db)
    assert result['mode'] == 'rules'
    assert response.headers['Cache-Control'] == 'no-store'
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_non_vessel_rejected():
    db, _, i = db_fixture(); i.data['report_form_id'] = 'to-13'
    with pytest.raises(HTTPException) as exc: await load_source(uuid.UUID(i.id), 'test', db)
    assert exc.value.status_code == 422


@pytest.mark.asyncio
async def test_export_rejects_stale_source(monkeypatch):
    i, e = fixture(); r = prepare_vessel_report(i,e)
    monkeypatch.setattr('report_assistant_api.load_source', AsyncMock(return_value=(SimpleNamespace(username='test', id=uuid.uuid4()),r)))
    with pytest.raises(HTTPException) as exc:
        await export_draft(uuid.UUID(i['id']), ReviewedDraft(source_fingerprint='0'*64, text='draft',confirmed=True), 'test', AsyncMock())
    assert exc.value.status_code == 409


@pytest.mark.asyncio
async def test_export_marks_draft_and_includes_findings(monkeypatch):
    i, e = fixture(); r = prepare_vessel_report(i,e)
    monkeypatch.setattr('report_assistant_api.load_source', AsyncMock(return_value=(SimpleNamespace(username='test', id=uuid.uuid4()),r)))
    response = await export_draft(uuid.UUID(i['id']), ReviewedDraft(source_fingerprint=r['source_fingerprint'],text='Reviewed text',confirmed=True), 'test', AsyncMock())
    text = response.body.decode('utf-8-sig')
    assert 'НЕ ЗАКЛЮЧЕНИЕ' in text and 'Reviewed text' in text and 'Замечания' in text


def test_confirmation_is_required():
    from pydantic import ValidationError
    with pytest.raises(ValidationError): ReviewedDraft(source_fingerprint='0'*64,text='draft',confirmed=False)


def test_duplicate_exclusion_is_independent_of_row_order():
    i, e = fixture()
    rows = [{'scheme_point_id': 'a', 'thickness': '1'}, {'scheme_point_id': 'a', 'thickness': '99'},
            {'scheme_point_id': 'b', 'thickness': '7.5'}]
    for order in (rows, list(reversed(rows))):
        i['data']['thickness_measurements'] = order
        stats = prepare_vessel_report(i, e)['measurements']
        assert stats['measured'] == 1 and stats['duplicate_rows'] == 2
        assert stats['minimum_mm'] == stats['maximum_mm'] == '7.5'


@pytest.mark.asyncio
async def test_word_export_contains_reviewed_text_facts_and_warnings(monkeypatch):
    import io
    from docx import Document
    i, e = fixture(); result = prepare_vessel_report(i, e)
    monkeypatch.setattr('report_assistant_api.load_source', AsyncMock(return_value=(SimpleNamespace(username='test', id=uuid.uuid4()), result)))
    response = await export_draft(uuid.UUID(i['id']), ReviewedDraft(source_fingerprint=result['source_fingerprint'],
                                 text='Проверенный текст\x00', confirmed=True, format='docx'), 'test', AsyncMock())
    document = Document(io.BytesIO(response.body))
    text = '\n'.join(p.text for p in document.paragraphs)
    assert 'Проверенный текст' in text and 'НЕ ЗАКЛЮЧЕНИЕ' in text
    assert 'Замечания автоматической проверки' in text
    assert result['source_fingerprint'] in text
    assert len(document.tables[0].rows) == len(result['facts']) + 1
    assert '.docx' in response.headers['Content-Disposition']


def test_export_format_is_validated():
    from pydantic import ValidationError
    with pytest.raises(ValidationError):
        ReviewedDraft(source_fingerprint='0'*64, text='draft', confirmed=True, format='html')
