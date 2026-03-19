"""Тесты системных endpoints: /, /health, /metrics."""

import pytest
from unittest.mock import MagicMock


@pytest.mark.asyncio
async def test_root_endpoint(client):
    """GET / — возвращает 200 с информацией о платформе."""
    response = await client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "message" in data
    assert "version" in data
    assert data["status"] == "running"


@pytest.mark.asyncio
async def test_health_endpoint(client, mock_db):
    """GET /health — возвращает 200 при подключённой (мок) БД."""
    mock_result = MagicMock()
    mock_db.execute.return_value = mock_result

    response = await client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["database"] == "connected"


@pytest.mark.asyncio
async def test_health_endpoint_db_failure(client, mock_db):
    """GET /health — возвращает 503 если БД недоступна."""
    mock_db.execute.side_effect = Exception("Connection refused")

    response = await client.get("/health")
    assert response.status_code == 503
    data = response.json()
    assert "unhealthy" in data["detail"].lower() or "Database" in data["detail"]


@pytest.mark.asyncio
async def test_metrics_endpoint(client):
    """GET /metrics — возвращает 200 со счётчиками метрик."""
    response = await client.get("/metrics")
    assert response.status_code == 200
    data = response.json()
    assert "http_requests_total" in data
    assert "report_generation_count" in data
    assert isinstance(data["http_requests_total"], int)
