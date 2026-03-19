"""Тесты API отчётов (reports)."""

import uuid

import pytest
from unittest.mock import MagicMock

from conftest import make_mock_user


def _setup_user_and_reports(mock_db, reports=None, role="admin"):
    """Настраивает мок: запрос пользователя + запрос отчётов."""
    mock_user = make_mock_user(role=role)

    user_result = MagicMock()
    user_result.scalar_one_or_none.return_value = mock_user

    reports_result = MagicMock()
    reports_result.scalars.return_value.all.return_value = reports or []

    mock_db.execute.side_effect = [user_result, reports_result]
    return mock_user


@pytest.mark.asyncio
async def test_get_reports(client, mock_db):
    """GET /api/reports — возвращает 200 со списком отчётов."""
    _setup_user_and_reports(mock_db)
    response = await client.get("/api/reports")
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_get_reports_empty(client, mock_db):
    """GET /api/reports — пустой список при отсутствии данных."""
    _setup_user_and_reports(mock_db, reports=[])
    response = await client.get("/api/reports")
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_validate_report(client, mock_db):
    """GET /api/reports/validate/{inspection_id} — возвращает 200 или 404."""
    inspection_id = str(uuid.uuid4())

    mock_user = make_mock_user()
    user_result = MagicMock()
    user_result.scalar_one_or_none.return_value = mock_user

    empty_result = MagicMock()
    empty_result.scalars.return_value.all.return_value = []
    empty_result.scalar_one_or_none.return_value = None

    mock_db.execute.side_effect = [user_result, empty_result, empty_result]

    response = await client.get(f"/api/reports/validate/{inspection_id}")
    assert response.status_code in (200, 404)


@pytest.mark.asyncio
async def test_get_reports_user_not_found(client, mock_db):
    """GET /api/reports — пользователь не найден → 404."""
    mock_result = MagicMock()
    mock_result.scalar_one_or_none.return_value = None
    mock_db.execute.return_value = mock_result

    response = await client.get("/api/reports")
    assert response.status_code == 404
