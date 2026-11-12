from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import httpx
import pyotp
import pytest
from fastapi import FastAPI

from auth import create_access_token, hash_password
from auth_api import router as auth_router
from auth_2fa_api import router as mfa_router
from database import get_db
from observability import _metrics_middleware, http_requests_total
from security import hash_recovery_code, limiter


@pytest.fixture
def security_app(monkeypatch):
    # Real JWT validation and real router serialization; only persistence is mocked.
    monkeypatch.setattr(limiter, "enabled", False)
    user = SimpleNamespace(id="test-user", username="alice", email="alice@test.invalid",
                           role="engineer", is_active=True, failed_login_count=0,
                           locked_until=None, password_hash=hash_password("Correct-password-42"),
                           totp_enabled=True, totp_secret=pyotp.random_base32(),
                           totp_recovery_codes=[hash_recovery_code("ABCD-EFGH")])
    db = AsyncMock()
    result = MagicMock()
    result.scalar_one_or_none.return_value = user
    db.execute.return_value = result
    app = FastAPI()
    app.include_router(auth_router)
    app.include_router(mfa_router)
    app.dependency_overrides[get_db] = lambda: db
    return app, user, db


def auth_headers():
    return {"Authorization": "Bearer " + create_access_token({"sub": "alice"})}


@pytest.mark.asyncio
async def test_active_mfa_cannot_be_reset_or_reenabled(security_app):
    app, user, db = security_app
    secret, codes = user.totp_secret, list(user.totp_recovery_codes)
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url="http://test") as c:
        assert (await c.post("/api/auth/2fa/setup", headers=auth_headers())).status_code == 409
        assert (await c.post("/api/auth/2fa/enable", headers=auth_headers(),
                             json={"code": pyotp.TOTP(secret).now()})).status_code == 409
    assert user.totp_enabled and user.totp_secret == secret
    assert user.totp_recovery_codes == codes
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_mfa_lifecycle_and_login(security_app):
    app, user, db = security_app
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url="http://test") as c:
        url = "/api/auth/2fa/disable"
        code = pyotp.TOTP(user.totp_secret).now()
        assert (await c.post(url, headers=auth_headers(), json={"password": "wrong", "code": code})).status_code == 401
        assert user.totp_enabled
        assert (await c.post(url, headers=auth_headers(), json={"password": "Correct-password-42", "code": code})).status_code == 200
        setup = await c.post("/api/auth/2fa/setup", headers=auth_headers())
        assert setup.status_code == 200
        assert not user.totp_enabled
        code = pyotp.TOTP(setup.json()["secret"]).now()
        enabled = await c.post("/api/auth/2fa/enable", headers=auth_headers(), json={"code": code})
        assert enabled.status_code == 200 and user.totp_enabled
        assert len(enabled.json()["recovery_codes"]) == 8
        response = await c.post("/api/auth/2fa/verify", json={"username": "alice", "password": "Correct-password-42", "code": code})
        assert response.status_code == 200 and "access_token" in response.json()
        assert "password_hash" not in response.json()


@pytest.mark.asyncio
async def test_recovery_code_accepted_once(security_app):
    app, user, db = security_app
    body = {"username": "alice", "password": "Correct-password-42", "code": "ABCD-EFGH"}
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url="http://test") as c:
        assert (await c.post("/api/auth/2fa/verify", json=body)).status_code == 200
        assert (await c.post("/api/auth/2fa/verify", json=body)).status_code == 400
    assert user.totp_recovery_codes == []


@pytest.mark.asyncio
async def test_mfa_failures_lock_account(security_app):
    app, user, db = security_app
    body = {"username": "alice", "password": "wrong", "code": "123456"}
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url="http://test") as c:
        for _ in range(5):
            assert (await c.post("/api/auth/2fa/verify", json=body)).status_code == 401
        body["password"] = "Correct-password-42"
        body["code"] = pyotp.TOTP(user.totp_secret).now()
        assert (await c.post("/api/auth/2fa/verify", json=body)).status_code == 423
    assert user.locked_until is not None


@pytest.mark.asyncio
async def test_login_never_returns_password_hash(security_app):
    app, user, db = security_app
    user.totp_enabled = False
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url="http://test") as c:
        r = await c.post("/api/auth/login", data={"username": "alice", "password": "Correct-password-42"})
    assert r.status_code == 200
    assert set(r.json()) == {"access_token", "token_type", "role"}


@pytest.mark.asyncio
async def test_inactive_and_unauthenticated_cannot_setup(security_app):
    app, user, db = security_app
    user.is_active = False
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url="http://test") as c:
        assert (await c.post("/api/auth/2fa/setup", headers=auth_headers())).status_code == 403
        assert (await c.post("/api/auth/2fa/setup")).status_code in (401, 403)
    db.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_unknown_urls_do_not_create_unbounded_metric_labels():
    app = FastAPI()
    app.middleware("http")(_metrics_middleware)
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url="http://test") as c:
        for i in range(40):
            assert (await c.get(f"/probe-unique-{i}")).status_code == 404
    samples = list(http_requests_total.collect())[0].samples
    assert not any("probe-unique" in s.labels.get("path", "") for s in samples)
    assert any(s.labels.get("path") == "unmatched" for s in samples)
