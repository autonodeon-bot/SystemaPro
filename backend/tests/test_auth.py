import uuid
from datetime import datetime, timedelta
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from jose import jwt

from auth import (
    ALGORITHM,
    ACCESS_TOKEN_EXPIRE_MINUTES,
    SECRET_KEY,
    create_access_token,
    get_user_permissions,
    hash_password,
    require_permission,
    verify_password,
    verify_token,
    verify_token_optional,
)
from auth_api import get_current_user, login


class TestCreateAccessToken:
    def test_create_access_token_should_encode_sub_and_exp(self):
        token = create_access_token({"sub": "alice", "role": "engineer"})
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        assert payload["sub"] == "alice"
        assert payload["role"] == "engineer"
        assert "exp" in payload

    def test_create_access_token_should_use_custom_expires_delta(self):
        delta = timedelta(minutes=5)
        token = create_access_token({"sub": "bob"}, expires_delta=delta)
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        exp = datetime.utcfromtimestamp(payload["exp"])
        now = datetime.utcnow()
        assert timedelta(minutes=4) < (exp - now) <= timedelta(minutes=6)

    def test_create_access_token_should_default_to_configured_ttl(self):
        token = create_access_token({"sub": "carol"})
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        exp = datetime.utcfromtimestamp(payload["exp"])
        now = datetime.utcnow()
        lower = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES - 2)
        upper = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES + 2)
        assert lower < (exp - now) < upper


class TestVerifyToken:
    def test_verify_token_should_return_username_when_valid(self):
        token = create_access_token({"sub": "validuser"})
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
        assert verify_token(credentials=creds) == "validuser"

    def test_verify_token_should_raise_when_credentials_missing(self):
        with pytest.raises(HTTPException) as exc:
            verify_token(credentials=None)
        assert exc.value.status_code == 401

    def test_verify_token_should_raise_when_sub_missing(self):
        token = jwt.encode(
            {"exp": datetime.utcnow() + timedelta(hours=1)},
            SECRET_KEY,
            algorithm=ALGORITHM,
        )
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
        with pytest.raises(HTTPException) as exc:
            verify_token(credentials=creds)
        assert exc.value.status_code == 401

    def test_verify_token_should_raise_on_malformed_token(self):
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="not-a-jwt")
        with pytest.raises(HTTPException) as exc:
            verify_token(credentials=creds)
        assert exc.value.status_code == 401


class TestVerifyTokenOptional:
    def test_verify_token_optional_should_return_none_without_credentials(self):
        assert verify_token_optional(credentials=None) is None

    def test_verify_token_optional_should_return_username_when_valid(self):
        token = create_access_token({"sub": "optuser"})
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
        assert verify_token_optional(credentials=creds) == "optuser"

    def test_verify_token_optional_should_return_none_on_invalid_token(self):
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="bad")
        assert verify_token_optional(credentials=creds) is None


class TestPasswordHashing:
    def test_hash_password_and_verify_password_should_round_trip(self):
        raw = "my-secret-password"
        hashed = hash_password(raw)
        assert hashed != raw
        assert verify_password(raw, hashed) is True

    def test_verify_password_should_fail_for_wrong_plain(self):
        hashed = hash_password("correct")
        assert verify_password("wrong", hashed) is False

    def test_hash_password_should_truncate_beyond_72_bytes(self):
        long_pw = "x" * 100
        h = hash_password(long_pw)
        assert verify_password(long_pw, h) is True
        assert verify_password("x" * 72, h) is True


class TestPermissions:
    def test_get_user_permissions_should_return_list_for_known_user(self):
        perms = get_user_permissions("admin")
        assert "admin" in perms

    def test_get_user_permissions_should_return_empty_for_unknown(self):
        assert get_user_permissions("nonexistent_user_xyz") == []

    def test_require_permission_should_allow_when_granted(self):
        checker = require_permission("read")
        assert checker(username="engineer") == "engineer"

    def test_require_permission_should_raise_for_unknown_user(self):
        checker = require_permission("read")
        with pytest.raises(HTTPException) as exc:
            checker(username="unknown_user_zzz")
        assert exc.value.status_code == 403

    def test_require_permission_should_raise_when_permission_missing(self):
        checker = require_permission("delete")
        with pytest.raises(HTTPException) as exc:
            checker(username="client")
        assert exc.value.status_code == 403


def _make_request() -> "Request":
    """Минимальный starlette Request для тестов (slowapi требует instance)."""
    from starlette.requests import Request as _Req

    scope = {
        "type": "http",
        "method": "POST",
        "path": "/api/auth/login",
        "headers": [(b"host", b"testserver")],
        "client": ("127.0.0.1", 0),
        "server": ("testserver", 80),
        "scheme": "http",
        "query_string": b"",
        "app": MagicMock(),
    }
    return _Req(scope)


@pytest.mark.asyncio
class TestLogin:
    async def test_login_should_succeed_for_fallback_admin(self):
        form = MagicMock()
        form.username = "admin"
        form.password = "admin123"
        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = None
        mock_db = MagicMock()
        mock_db.execute = AsyncMock(return_value=mock_result)

        out = await login(_make_request(), form, mock_db)
        assert out["token_type"] == "bearer"
        assert out["role"] == "admin"
        assert "access_token" in out
        payload = jwt.decode(out["access_token"], SECRET_KEY, algorithms=[ALGORITHM])
        assert payload["sub"] == "admin"

    async def test_login_should_reject_invalid_fallback_credentials(self):
        form = MagicMock()
        form.username = "admin"
        form.password = "wrong"
        mock_db = MagicMock()
        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = None
        mock_db.execute = AsyncMock(return_value=mock_result)

        with pytest.raises(HTTPException) as exc:
            await login(_make_request(), form, mock_db)
        assert exc.value.status_code == 401

    async def test_login_should_reject_wrong_db_password(self):
        from auth import hash_password

        form = MagicMock()
        form.username = "dbuser"
        form.password = "wrong"
        mock_user = MagicMock()
        mock_user.is_active = True
        mock_user.password_hash = hash_password("right")
        mock_user.role = "engineer"
        mock_user.username = "dbuser"
        mock_user.failed_login_count = 0
        mock_user.locked_until = None
        mock_user.totp_enabled = False

        mock_db = MagicMock()
        mock_db.commit = AsyncMock()
        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = mock_user
        mock_db.execute = AsyncMock(return_value=mock_result)

        with pytest.raises(HTTPException) as exc:
            await login(_make_request(), form, mock_db)
        assert exc.value.status_code == 401

    async def test_login_should_reject_inactive_db_user(self):
        form = MagicMock()
        form.username = "inactive"
        form.password = "any"
        mock_user = MagicMock()
        mock_user.is_active = False

        mock_db = MagicMock()
        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = mock_user
        mock_db.execute = AsyncMock(return_value=mock_result)

        with pytest.raises(HTTPException) as exc:
            await login(_make_request(), form, mock_db)
        assert exc.value.status_code == 403


@pytest.mark.asyncio
class TestGetCurrentUser:
    async def test_get_current_user_should_return_db_payload(self):
        uid = uuid.uuid4()
        mock_user = MagicMock()
        mock_user.id = uid
        mock_user.username = "u1"
        mock_user.email = "u1@example.com"
        mock_user.full_name = "User One"
        mock_user.role = "engineer"
        mock_user.engineer_id = None

        mock_db = MagicMock()
        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = mock_user
        mock_db.execute = AsyncMock(return_value=mock_result)

        out = await get_current_user(username="u1", db=mock_db)
        assert out["username"] == "u1"
        assert out["role"] == "engineer"
        assert out["id"] == str(uid)

    async def test_get_current_user_should_fallback_to_users_db(self):
        mock_db = MagicMock()
        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = None
        mock_db.execute = AsyncMock(return_value=mock_result)

        out = await get_current_user(username="admin", db=mock_db)
        assert out["username"] == "admin"
        assert out["role"] == "admin"

    async def test_get_current_user_should_404_when_unknown(self):
        mock_db = MagicMock()
        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = None
        mock_db.execute = AsyncMock(return_value=mock_result)

        with pytest.raises(HTTPException) as exc:
            await get_current_user(username="totally_unknown_xyz", db=mock_db)
        assert exc.value.status_code == 404
