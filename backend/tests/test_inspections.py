"""Тесты API обследований (inspections)."""

import pytest
from unittest.mock import MagicMock

from conftest import make_mock_user


def _setup_user_mock(mock_db, role="admin"):
    """Настраивает мок для запроса текущего пользователя из БД."""
    mock_user = make_mock_user(role=role)

    user_result = MagicMock()
    user_result.scalar_one_or_none.return_value = mock_user

    empty_result = MagicMock()
    empty_result.scalars.return_value.all.return_value = []
    empty_result.scalar_one_or_none.return_value = None
    empty_result.scalar.return_value = 0
    empty_result.fetchall.return_value = []

    mock_db.execute.side_effect = [user_result, empty_result, empty_result, empty_result]
    return mock_user


@pytest.mark.asyncio
async def test_get_inspections(client, mock_db):
    """GET /api/inspections — возвращает 200 со списком обследований."""
    _setup_user_mock(mock_db)
    response = await client.get("/api/inspections")
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_get_inspections_with_filters(client, mock_db):
    """GET /api/inspections?status=DRAFT — фильтр по статусу."""
    _setup_user_mock(mock_db)
    response = await client.get("/api/inspections", params={"status": "DRAFT"})
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_get_inspections_groups(client, mock_db):
    """GET /api/inspections/groups — возвращает 200 с группами."""
    _setup_user_mock(mock_db)
    response = await client.get("/api/inspections/groups")
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_create_inspection_missing_equipment_id(client, mock_db):
    """POST /api/inspections — без equipment_id → 422."""
    response = await client.post("/api/inspections", json={})
    assert response.status_code in (400, 422)


@pytest.mark.asyncio
async def test_create_inspection_invalid_equipment_id(client, mock_db):
    """POST /api/inspections — невалидный UUID → 422."""
    response = await client.post(
        "/api/inspections",
        json={"equipment_id": "not-a-uuid"},
    )
    assert response.status_code in (400, 422)


@pytest.mark.asyncio
async def test_create_inspection_invalid_status(client, mock_db):
    """POST /api/inspections — недопустимый статус → 422."""
    response = await client.post(
        "/api/inspections",
        json={
            "equipment_id": "00000000-0000-0000-0000-000000000001",
            "status": "INVALID_STATUS",
        },
    )
    assert response.status_code in (400, 422)
