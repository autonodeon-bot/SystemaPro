"""Тесты CRUD предприятий в иерархии."""

import uuid
from unittest.mock import MagicMock

import pytest

from conftest import make_mock_user


@pytest.mark.asyncio
async def test_update_enterprise(client, mock_db):
    mock_admin = make_mock_user(role="admin")
    enterprise_id = uuid.uuid4()
    enterprise = MagicMock()
    enterprise.id = enterprise_id
    enterprise.name = "Старое"
    enterprise.code = "OLD"
    enterprise.description = ""
    enterprise.is_active = True

    admin_result = MagicMock()
    admin_result.scalar_one_or_none.return_value = mock_admin

    ent_result = MagicMock()
    ent_result.scalar_one_or_none.return_value = enterprise

    dup_result = MagicMock()
    dup_result.scalar_one_or_none.return_value = None

    mock_db.execute.side_effect = [admin_result, ent_result, dup_result]

    response = await client.put(
        f"/api/hierarchy/enterprises/{enterprise_id}",
        json={"name": "Новое имя", "code": "NEW", "description": "Описание"},
    )
    assert response.status_code == 200
    assert response.json()["name"] == "Новое имя"


@pytest.mark.asyncio
async def test_delete_enterprise_method_allowed(client, mock_db):
    mock_admin = make_mock_user(role="admin")
    enterprise_id = uuid.uuid4()
    enterprise = MagicMock()
    enterprise.id = enterprise_id
    enterprise.is_active = True

    admin_result = MagicMock()
    admin_result.scalar_one_or_none.return_value = mock_admin

    ent_result = MagicMock()
    ent_result.scalar_one_or_none.return_value = enterprise

    count_result = MagicMock()
    count_result.scalar.return_value = 0

    mock_db.execute.side_effect = [admin_result, ent_result, count_result]

    response = await client.delete(f"/api/hierarchy/enterprises/{enterprise_id}")
    assert response.status_code != 405
    assert response.status_code == 200
