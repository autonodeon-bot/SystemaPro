"""Тесты API инженеров и пользователей."""

import pytest
from unittest.mock import MagicMock

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from shared import _ref_cache
from conftest import make_mock_user


@pytest.fixture(autouse=True)
def clear_engineers_cache():
    """Очищает кэш инженеров перед каждым тестом."""
    keys_to_delete = [k for k in _ref_cache if k.startswith("engineer")]
    for k in keys_to_delete:
        del _ref_cache[k]
    yield
    keys_to_delete = [k for k in _ref_cache if k.startswith("engineer")]
    for k in keys_to_delete:
        del _ref_cache[k]


@pytest.mark.asyncio
async def test_get_engineers(client, mock_db):
    """GET /api/engineers — возвращает 200 с объектом items."""
    mock_result = MagicMock()
    mock_result.scalars.return_value.all.return_value = []
    mock_db.execute.return_value = mock_result

    response = await client.get("/api/engineers")
    assert response.status_code == 200
    data = response.json()
    assert "items" in data
    assert isinstance(data["items"], list)


@pytest.mark.asyncio
async def test_get_engineers_empty(client, mock_db):
    """GET /api/engineers — пустой список при отсутствии инженеров."""
    mock_result = MagicMock()
    mock_result.scalars.return_value.all.return_value = []
    mock_db.execute.return_value = mock_result

    response = await client.get("/api/engineers")
    assert response.status_code == 200
    data = response.json()
    assert data["items"] == []


@pytest.mark.asyncio
async def test_get_users(client, mock_db):
    """GET /api/users — возвращает 200 со списком пользователей (admin)."""
    mock_admin = make_mock_user(role="admin")

    admin_result = MagicMock()
    admin_result.scalar_one_or_none.return_value = mock_admin

    users_result = MagicMock()
    users_result.scalars.return_value.all.return_value = [mock_admin]

    mock_db.execute.side_effect = [admin_result, users_result]

    response = await client.get("/api/users")
    assert response.status_code == 200
    data = response.json()
    assert "items" in data
    assert isinstance(data["items"], list)


@pytest.mark.asyncio
async def test_get_users_empty(client, mock_db):
    """GET /api/users — пустой список."""
    mock_admin = make_mock_user(role="admin")

    admin_result = MagicMock()
    admin_result.scalar_one_or_none.return_value = mock_admin

    users_result = MagicMock()
    users_result.scalars.return_value.all.return_value = []

    mock_db.execute.side_effect = [admin_result, users_result]

    response = await client.get("/api/users")
    assert response.status_code == 200
    data = response.json()
    assert data["items"] == []


@pytest.mark.asyncio
async def test_get_users_forbidden_for_engineer(client, mock_db):
    """GET /api/users — инженер получает 403."""
    mock_engineer = make_mock_user(role="engineer", username="engineer1")

    engineer_result = MagicMock()
    engineer_result.scalar_one_or_none.return_value = mock_engineer

    mock_db.execute.return_value = engineer_result

    response = await client.get("/api/users")
    assert response.status_code == 403
