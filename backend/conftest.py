"""
Pytest conftest — фикстуры для тестирования FastAPI backend.

Все зависимости от реальной БД мокаются через unittest.mock.
"""

import sys
import os
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import AsyncClient, ASGITransport

sys.path.insert(0, os.path.dirname(__file__))

# Мок для database.engine — предотвращаем реальное подключение к БД при импорте
_mock_engine = MagicMock()
_mock_engine.begin = MagicMock(return_value=AsyncMock())
_mock_engine.dispose = AsyncMock()

with patch.dict("os.environ", {
    "DB_HOST": "localhost",
    "DB_PASS": "test",
    "DB_NAME": "test_db",
    "DB_SSLMODE": "disable",
    "JWT_SECRET_KEY": "test-secret-key-for-pytest",
}):
    import database
    database.engine = _mock_engine

    from main import app
    from database import get_db
    from auth import verify_token, verify_token_optional


# ---------------------------------------------------------------------------
# Тестовый пользователь
# ---------------------------------------------------------------------------
TEST_USER = "admin"
TEST_USER_DICT = {
    "id": "00000000-0000-0000-0000-000000000001",
    "username": "admin",
    "role": "admin",
    "permissions": ["read", "write", "delete", "admin"],
}


def make_mock_user(
    role: str = "admin",
    username: str = "admin",
    user_id: str = "00000000-0000-0000-0000-000000000001",
) -> MagicMock:
    """Создаёт мок объекта User для использования в тестах."""
    import uuid as _uuid
    user = MagicMock()
    user.id = _uuid.UUID(user_id)
    user.username = username
    user.email = f"{username}@test.com"
    user.full_name = username.capitalize()
    user.role = role
    user.is_active = 1
    user.permissions = None
    user.engineer_id = None
    user.created_at = None
    user.updated_at = None
    return user


# ---------------------------------------------------------------------------
# Мок AsyncSession
# ---------------------------------------------------------------------------
def _make_mock_db() -> AsyncMock:
    """Создаёт мок AsyncSession с базовым поведением."""
    session = AsyncMock()

    mock_result = MagicMock()
    mock_result.scalars.return_value.all.return_value = []
    mock_result.scalars.return_value.first.return_value = None
    mock_result.scalar_one_or_none.return_value = None
    mock_result.scalar.return_value = None
    mock_result.fetchall.return_value = []
    mock_result.fetchone.return_value = None
    mock_result.rowcount = 0

    session.execute.return_value = mock_result
    session.commit = AsyncMock()
    session.rollback = AsyncMock()
    session.close = AsyncMock()
    session.refresh = AsyncMock()
    session.add = MagicMock()
    session.delete = AsyncMock()
    session.flush = AsyncMock()

    return session


# ---------------------------------------------------------------------------
# Override FastAPI dependencies
# ---------------------------------------------------------------------------
def _override_verify_token():
    return TEST_USER


def _override_verify_token_optional():
    return TEST_USER


@pytest.fixture(autouse=True)
def override_dependencies():
    """Перекрывает все зависимости от БД и аутентификации на уровне FastAPI."""
    mock_db = _make_mock_db()

    async def _override_get_db():
        yield mock_db

    app.dependency_overrides[get_db] = _override_get_db
    app.dependency_overrides[verify_token] = _override_verify_token
    app.dependency_overrides[verify_token_optional] = _override_verify_token_optional

    yield mock_db

    app.dependency_overrides.clear()


@pytest.fixture
def mock_db(override_dependencies):
    """Доступ к мок-сессии БД для настройки поведения в конкретных тестах."""
    return override_dependencies


@pytest.fixture
async def client():
    """Async HTTP клиент для тестирования FastAPI endpoints."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as ac:
        yield ac
