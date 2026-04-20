"""
Роутер аутентификации: /api/auth/login, /api/auth/me
"""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from auth import (
    ROLE_PERMISSIONS,
    USERS_DB,
    create_access_token,
    hash_password,
    verify_password,
    verify_token,
)
from database import get_db
from models import User
from observability import get_logger, record_login
from security import (
    AUTH_RATE_LIMIT,
    client_ip,
    limiter,
)

router = APIRouter(prefix="/api/auth", tags=["auth"])
log = get_logger("auth")


# Настройки временной блокировки
_MAX_FAILED = 5
_LOCK_MINUTES = 15


@router.post("/login")
@limiter.limit(AUTH_RATE_LIMIT)
async def login(
    request: Request,
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: AsyncSession = Depends(get_db),
):
    """Вход в систему.

    Поведение:
      1. Проверяем блокировку → 423.
      2. Сверяем пароль; при провале — инкремент счётчика, при достижении
         лимита — блокировка на 15 минут (`locked_until`).
      3. Если у пользователя включён 2FA — возвращаем 200 с флагом
         `two_factor_required=true` и без access_token; клиент должен вызвать
         /api/auth/2fa/verify.
      4. Иначе выдаём access_token.
    """
    ip = client_ip(request)

    result = await db.execute(
        select(User).where(
            or_(User.username == form_data.username, User.email == form_data.username)
        )
    )
    db_user = result.scalar_one_or_none()

    if db_user:
        if not db_user.is_active:
            record_login("fail")
            log.warning("Login blocked (inactive): {} from {}", db_user.username, ip)
            raise HTTPException(status_code=403, detail="Учётная запись отключена")

        now = datetime.now(timezone.utc)
        if db_user.locked_until and db_user.locked_until > now:
            record_login("locked")
            raise HTTPException(
                status_code=423,
                detail="Учётная запись временно заблокирована из-за частых ошибок входа",
            )

        if not verify_password(form_data.password, db_user.password_hash):
            db_user.failed_login_count = (db_user.failed_login_count or 0) + 1
            if db_user.failed_login_count >= _MAX_FAILED:
                db_user.locked_until = now + timedelta(minutes=_LOCK_MINUTES)
                db_user.failed_login_count = 0
                await db.commit()
                record_login("locked")
                log.warning("User locked: {} from {}", db_user.username, ip)
                raise HTTPException(
                    status_code=423,
                    detail=f"Учётная запись заблокирована на {_LOCK_MINUTES} минут",
                )
            await db.commit()
            record_login("fail")
            raise HTTPException(
                status_code=401,
                detail="Неверный логин или пароль",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # Успешная проверка пароля
        if db_user.totp_enabled:
            record_login("2fa_required")
            return {
                "two_factor_required": True,
                "username": db_user.username,
                "role": db_user.role,
            }

        db_user.failed_login_count = 0
        db_user.last_login = now
        user_role = db_user.role
        token_subject = db_user.username
        password_hash = db_user.password_hash
        await db.commit()
    else:
        user = USERS_DB.get(form_data.username)
        if not user or user["password"] != form_data.password:
            record_login("fail")
            raise HTTPException(
                status_code=401,
                detail="Неверный логин или пароль",
                headers={"WWW-Authenticate": "Bearer"},
            )
        user_role = user["role"]
        token_subject = form_data.username
        password_hash = hash_password(form_data.password)

    access_token = create_access_token(
        data={"sub": token_subject, "role": user_role, "amr": ["pwd"]},
        expires_delta=timedelta(minutes=60 * 24),
    )
    record_login("success")
    log.info("Login success: {} from {}", token_subject, ip)

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "role": user_role,
        "password_hash": password_hash,
    }


@router.get("/me")
async def get_current_user(
    username: str = Depends(verify_token), db: AsyncSession = Depends(get_db)
):
    """Получить информацию о текущем пользователе."""
    result = await db.execute(
        select(User).where(or_(User.username == username, User.email == username))
    )
    db_user = result.scalar_one_or_none()

    if db_user:
        permissions = ROLE_PERMISSIONS.get(db_user.role, [])
        return {
            "id": str(db_user.id),
            "username": db_user.username,
            "email": db_user.email,
            "full_name": db_user.full_name,
            "role": db_user.role,
            "permissions": permissions,
            "engineer_id": str(db_user.engineer_id) if db_user.engineer_id else None,
            "totp_enabled": bool(db_user.totp_enabled),
        }

    user = USERS_DB.get(username)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "id": None,
        "username": username,
        "role": user["role"],
        "permissions": user["permissions"],
        "totp_enabled": False,
    }
