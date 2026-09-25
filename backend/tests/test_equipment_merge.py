from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
import pytest
from fastapi import HTTPException
from equipment_merge import fill_missing_attributes
from equipment_crud_api import _authorize_equipment_write


def test_offline_values_fill_blanks_but_keep_operator_values_and_zero():
    current = {'pressure': '12', 'zero': 0, 'material': ''}
    merged, conflicts = fill_missing_attributes(current, {'pressure': '10', 'zero': '2', 'material': 'Сталь', 'diameter': 0})
    assert merged == {'pressure': '12', 'zero': 0, 'material': 'Сталь', 'diameter': 0}
    assert conflicts == ['pressure', 'zero']
    assert current['material'] == ''


@pytest.mark.asyncio
@pytest.mark.parametrize('role', ['client', 'unknown'])
async def test_readonly_roles_cannot_modify_equipment(role):
    result = MagicMock()
    result.scalar_one_or_none.return_value = SimpleNamespace(role=role, id='test')
    db = AsyncMock()
    db.execute.return_value = result
    with pytest.raises(HTTPException) as exc:
        await _authorize_equipment_write(db, 'user', 'equipment')
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_engineer_requires_equipment_assignment():
    user = MagicMock(); user.scalar_one_or_none.return_value = SimpleNamespace(role='engineer', id='user')
    access = MagicMock(); access.scalar_one_or_none.return_value = None
    db = AsyncMock(); db.execute.side_effect = [user, access]
    with pytest.raises(HTTPException) as exc:
        await _authorize_equipment_write(db, 'user', 'equipment')
    assert exc.value.status_code == 403
