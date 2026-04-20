"""2FA (TOTP) роутер.

Workflow:
  1) POST /api/auth/2fa/setup       → secret + otpauth URI + PNG QR (base64)
  2) POST /api/auth/2fa/enable      → подтверждение кодом, секрет сохраняется, 2FA активируется
  3) POST /api/auth/2fa/verify      → используется во время логина, если у пользователя включено
  4) POST /api/auth/2fa/disable     → отключение (требует пароль + свежий код)
  5) GET  /api/auth/2fa/status      → { enabled, pending }
"""
import base64
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from auth import create_access_token, verify_password, verify_token
from database import get_db
from models import User
from security import (
    AUTH_2FA_RATE_LIMIT,
    generate_recovery_codes,
    generate_totp_secret,
    hash_recovery_code,
    limiter,
    totp_provisioning_uri,
    totp_qr_png,
    verify_totp_code,
)

router = APIRouter(prefix="/api/auth/2fa", tags=["auth"])


# ─── Schemas ──────────────────────────────────────────────────────────────────
class TwoFASetupResponse(BaseModel):
    secret: str
    otpauth_uri: str
    qr_png_base64: str


class TwoFAEnableRequest(BaseModel):
    code: str = Field(..., min_length=6, max_length=8)


class TwoFAEnableResponse(BaseModel):
    enabled: bool
    recovery_codes: list[str]


class TwoFADisableRequest(BaseModel):
    password: str
    code: str = Field(..., min_length=6, max_length=8)


class TwoFAVerifyRequest(BaseModel):
    username: str
    password: str
    code: str = Field(..., min_length=6, max_length=8)


class TwoFAStatusResponse(BaseModel):
    enabled: bool
    has_secret: bool


# ─── Helpers ──────────────────────────────────────────────────────────────────
async def _load_user(db: AsyncSession, username: str) -> User:
    result = await db.execute(
        select(User).where(or_(User.username == username, User.email == username))
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


# ─── Endpoints ────────────────────────────────────────────────────────────────
@router.get("/status", response_model=TwoFAStatusResponse)
async def status_2fa(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    user = await _load_user(db, username)
    return TwoFAStatusResponse(
        enabled=bool(user.totp_enabled),
        has_secret=bool(user.totp_secret),
    )


@router.post("/setup", response_model=TwoFASetupResponse)
async def setup_2fa(
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    """Генерирует новый секрет. Секрет сохраняется, но 2FA остаётся выключенной,
    пока пользователь не подтвердит код через /enable."""
    user = await _load_user(db, username)
    secret = generate_totp_secret()
    user.totp_secret = secret
    user.totp_enabled = False
    await db.commit()

    uri = totp_provisioning_uri(secret, user.username)
    png = totp_qr_png(uri)
    return TwoFASetupResponse(
        secret=secret,
        otpauth_uri=uri,
        qr_png_base64=base64.b64encode(png).decode("ascii"),
    )


@router.post("/enable", response_model=TwoFAEnableResponse)
async def enable_2fa(
    payload: TwoFAEnableRequest,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    user = await _load_user(db, username)
    if not user.totp_secret:
        raise HTTPException(status_code=400, detail="Сначала вызовите /setup")
    if not verify_totp_code(user.totp_secret, payload.code):
        raise HTTPException(status_code=400, detail="Неверный код")

    codes = generate_recovery_codes()
    user.totp_recovery_codes = [hash_recovery_code(c) for c in codes]
    user.totp_enabled = True
    await db.commit()
    return TwoFAEnableResponse(enabled=True, recovery_codes=codes)


@router.post("/disable")
async def disable_2fa(
    payload: TwoFADisableRequest,
    username: str = Depends(verify_token),
    db: AsyncSession = Depends(get_db),
):
    user = await _load_user(db, username)
    if not user.totp_enabled or not user.totp_secret:
        raise HTTPException(status_code=400, detail="2FA не включена")
    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Неверный пароль")
    if not verify_totp_code(user.totp_secret, payload.code):
        raise HTTPException(status_code=400, detail="Неверный код")

    user.totp_secret = None
    user.totp_enabled = False
    user.totp_recovery_codes = None
    await db.commit()
    return {"disabled": True}


@router.post("/verify")
@limiter.limit(AUTH_2FA_RATE_LIMIT)
async def verify_2fa(
    request: Request,
    payload: TwoFAVerifyRequest,
    db: AsyncSession = Depends(get_db),
):
    """Второй шаг логина: после /login, если в ответе `two_factor_required`.

    Возвращает access_token.
    """
    user = await _load_user(db, payload.username)
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Учётная запись отключена")
    if user.locked_until and user.locked_until > datetime.now(timezone.utc):
        raise HTTPException(status_code=423, detail="Учётная запись временно заблокирована")
    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Неверный пароль")
    if not user.totp_enabled or not user.totp_secret:
        raise HTTPException(status_code=400, detail="2FA не настроена")

    ok = verify_totp_code(user.totp_secret, payload.code)
    if not ok:
        recovery_hashed = hash_recovery_code(payload.code)
        codes = user.totp_recovery_codes or []
        if recovery_hashed in codes:
            user.totp_recovery_codes = [c for c in codes if c != recovery_hashed]
            ok = True
        else:
            raise HTTPException(status_code=400, detail="Неверный код 2FA")

    user.last_login = datetime.now(timezone.utc)
    user.failed_login_count = 0
    await db.commit()

    token = create_access_token(
        data={"sub": user.username, "role": user.role, "amr": ["pwd", "totp"]},
        expires_delta=timedelta(minutes=60 * 24),
    )
    return {"access_token": token, "token_type": "bearer", "role": user.role}
