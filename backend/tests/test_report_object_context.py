import copy
import uuid
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

from form_template_filler import _build_context
from models import Assignment, Branch, Enterprise, Equipment, Opo, Workshop
from report_object_context import resolve_report_object


def objects():
    enterprise = Enterprise(id=uuid.uuid4(), name='ПАО «Сургутнефтегаз»')
    branch = Branch(id=uuid.uuid4(), name='НГДУ «Лянторнефть»', enterprise_id=enterprise.id)
    workshop = Workshop(id=uuid.uuid4(), name='Пункт подготовки и сбора нефти', branch_id=branch.id)
    equipment = Equipment(id=uuid.uuid4(), equipment_code='EQ-774929E8', name='Сепаратор нефтегазовый',
                          serial_number='1075', workshop_id=workshop.id, attributes={})
    rows = {(type(item), item.id): item for item in (enterprise, branch, workshop, equipment)}
    db = SimpleNamespace(get=AsyncMock(side_effect=lambda model, identity: rows.get((model, identity))))
    return db, rows, equipment, workshop, branch, enterprise


@pytest.mark.asyncio
async def test_foreign_opo_is_excluded_and_location_matches_official_report():
    db, rows, equipment, workshop, _, _ = objects()
    other = Workshop(id=uuid.uuid4(), branch_id=uuid.uuid4(), name='Цех ГазНефти')
    opo = Opo(id=uuid.uuid4(), name='ОПО-004', workshop_id=other.id,
              survey_data={'organization': 'ГазНефть', 'executors': 'Тестовый специалист', 'documents': {'1': True}})
    equipment.opo_id = opo.id
    rows.update({(Workshop, other.id): other, (Opo, opo.id): opo})
    data = {'location': None, 'equipment_location': None, 'documents': {'1': False}}
    before = copy.deepcopy(data)
    result = await resolve_report_object(db, equipment, data)
    assert result['opo'] is None and result['warnings']
    assert result['equipment']['enterprise_name'] == 'ПАО «Сургутнефтегаз»'
    assert result['equipment']['location'] == workshop.name
    assert 'executors' not in result['data']
    assert result['data']['documents']['1'] is False
    context = _build_context({'data': result['data']}, result['equipment'], [], {}, [])
    assert context['device_name'] == result['equipment']['name']
    assert context['serial'] == result['equipment']['serial_number']
    assert context['location'] == result['equipment']['location']
    assert 'ГазНефть' not in str(context['data'])
    assert data == before


@pytest.mark.asyncio
async def test_checklist_identity_and_location_are_shown_in_preview_and_report():
    db, _, equipment, _, _, _ = objects()
    data = {'vessel_name': 'Уточнённый сепаратор', 'serial_number': '4198-2 к-т',
            'equipment_location': 'ДНС ЦДНГ-12 Ай-Пимского месторождения'}
    result = await resolve_report_object(db, equipment, data)
    context = _build_context({'data': result['data']}, result['equipment'], [], {}, [])
    assert result['equipment']['name'] == context['device_name'] == data['vessel_name']
    assert result['equipment']['location'] == context['location'] == data['equipment_location']
    assert result['equipment']['serial_number'] == context['serial'] == data['serial_number']


@pytest.mark.asyncio
async def test_opo_with_direct_branch_is_resolved_without_workshop():
    db, rows, equipment, _, branch, enterprise = objects()
    opo = Opo(id=uuid.uuid4(), name='Действующее ОПО', branch_id=branch.id,
              survey_data={'documents': {'1': True, '2': True}})
    rows[(Opo, opo.id)] = opo
    equipment.opo_id = opo.id
    result = await resolve_report_object(db, equipment, {'documents': {'1': False}})
    assert result['opo']['enterprise_name'] == enterprise.name
    assert result['opo']['branch_name'] == branch.name
    assert result['data']['documents'] == {'1': False, '2': True}
    assert not result['warnings']


@pytest.mark.asyncio
async def test_foreign_stored_opo_copy_does_not_reappear_from_checklist():
    db, rows, equipment, _, _, _ = objects()
    opo = Opo(id=uuid.uuid4(), name='Чужое ОПО', enterprise_id=uuid.uuid4())
    enterprise = Enterprise(id=opo.enterprise_id, name='ГазНефть')
    rows.update({(Opo, opo.id): opo, (Enterprise, enterprise.id): enterprise})
    equipment.opo_id = opo.id
    result = await resolve_report_object(db, equipment, {'opo': {'id': str(opo.id), 'name': opo.name},
                                                        'opo_name': opo.name, 'opo_survey': {'executors': 'Тест'}})
    assert result['opo'] is None
    assert not any(key.startswith('opo') for key in result['data'])


@pytest.mark.asyncio
async def test_different_equipment_in_assignment_is_rejected():
    db, rows, equipment, _, _, _ = objects()
    assignment = Assignment(id=uuid.uuid4(), equipment_id=uuid.uuid4())
    rows[(Assignment, assignment.id)] = assignment
    with pytest.raises(HTTPException) as error:
        await resolve_report_object(db, equipment, {}, assignment.id)
    assert error.value.status_code == 409


@pytest.mark.asyncio
async def test_missing_equipment_hierarchy_can_use_valid_opo_hierarchy():
    db, rows, equipment, workshop, _, enterprise = objects()
    equipment.workshop_id = None
    opo = Opo(id=uuid.uuid4(), name='ОПО', workshop_id=workshop.id)
    equipment.opo_id = opo.id
    rows[(Opo, opo.id)] = opo
    result = await resolve_report_object(db, equipment, {})
    assert result['equipment']['enterprise_name'] == enterprise.name
    assert result['equipment']['location'] == workshop.name


@pytest.mark.asyncio
async def test_opo_opt_out_is_respected():
    db, rows, equipment, workshop, _, _ = objects()
    opo = Opo(id=uuid.uuid4(), name='ОПО', workshop_id=workshop.id)
    equipment.opo_id = opo.id
    rows[(Opo, opo.id)] = opo
    result = await resolve_report_object(db, equipment, {'include_opo_data': False})
    assert result['opo'] is None and not result['warnings']
    assert 'opo' not in result['data']
