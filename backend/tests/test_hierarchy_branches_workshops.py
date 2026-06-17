"""Тесты CRUD филиалов и цехов в иерархии."""

import uuid
from unittest.mock import MagicMock

import pytest

from conftest import make_mock_user


@pytest.mark.asyncio
async def test_update_branch(client, mock_db):
    mock_admin = make_mock_user(role="admin")
    branch_id = uuid.uuid4()
    branch = MagicMock()
    branch.id = branch_id
    branch.enterprise_id = uuid.uuid4()
    branch.name = "Старый филиал"
    branch.code = "B1"
    branch.description = ""
    branch.is_active = True

    admin_result = MagicMock()
    admin_result.scalar_one_or_none.return_value = mock_admin

    branch_result = MagicMock()
    branch_result.scalar_one_or_none.return_value = branch

    mock_db.execute.side_effect = [admin_result, branch_result]

    response = await client.put(
        f"/api/hierarchy/branches/{branch_id}",
        json={"name": "Новый филиал", "code": "B2"},
    )
    assert response.status_code == 200
    assert response.json()["name"] == "Новый филиал"


@pytest.mark.asyncio
async def test_delete_branch_method_allowed(client, mock_db):
    mock_admin = make_mock_user(role="admin")
    branch_id = uuid.uuid4()
    branch = MagicMock()
    branch.id = branch_id
    branch.is_active = True

    admin_result = MagicMock()
    admin_result.scalar_one_or_none.return_value = mock_admin

    branch_result = MagicMock()
    branch_result.scalar_one_or_none.return_value = branch

    count_result = MagicMock()
    count_result.scalar.return_value = 0

    mock_db.execute.side_effect = [admin_result, branch_result, count_result]

    response = await client.delete(f"/api/hierarchy/branches/{branch_id}")
    assert response.status_code != 405
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_delete_workshop_method_allowed(client, mock_db):
    mock_admin = make_mock_user(role="admin")
    workshop_id = uuid.uuid4()
    workshop = MagicMock()
    workshop.id = workshop_id
    workshop.is_active = True

    admin_result = MagicMock()
    admin_result.scalar_one_or_none.return_value = mock_admin

    workshop_result = MagicMock()
    workshop_result.scalar_one_or_none.return_value = workshop

    count_result = MagicMock()
    count_result.scalar.return_value = 0

    mock_db.execute.side_effect = [admin_result, workshop_result, count_result]

    response = await client.delete(f"/api/hierarchy/workshops/{workshop_id}")
    assert response.status_code != 405
    assert response.status_code == 200
