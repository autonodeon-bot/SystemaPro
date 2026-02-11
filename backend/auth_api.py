"""
Роутер аутентификации: /api/auth/login, /api/auth/me
"""
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_
from datetime import timedelta

from database import get_db
from models import User
from auth import (
    USERS_DB,
    create_access_token,
    verify_token,
    verify_password,
    hash_password,
    ROLE_PERMISSIONS,
)

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/login")
async def login(form_data: OAuth2PasswordRequestForm = Depends(), db: AsyncSession = Depends(get_db)):
    """Вход в систему"""
    # Поддерживаем вход как по username, так и по email (в UI часто вводят email)
    result = await db.execute(
        select(User).where(or_(User.username == form_data.username, User.email == form_data.username))
    )
    db_user = result.scalar_one_or_none()

    if db_user:
        if not db_user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Учётная запись отключена",
            )
        if not verify_password(form_data.password, db_user.password_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Неверный логин или пароль",
                headers={"WWW-Authenticate": "Bearer"},
            )
        user_role = db_user.role
    else:
        user = USERS_DB.get(form_data.username)
        if not user or user["password"] != form_data.password:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Неверный логин или пароль",
                headers={"WWW-Authenticate": "Bearer"},
            )
        user_role = user["role"]

    access_token_expires = timedelta(minutes=60 * 24)
    # В sub кладём канонический username из БД, чтобы все эндпоинты работали стабильно
    token_subject = db_user.username if db_user else form_data.username
    access_token = create_access_token(
        data={"sub": token_subject, "role": user_role},
        expires_delta=access_token_expires
    )

    password_hash = None
    if db_user:
        password_hash = db_user.password_hash
    else:
        password_hash = hash_password(form_data.password)

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "role": user_role,
        "password_hash": password_hash
    }


@router.get("/me")
async def get_current_user(username: str = Depends(verify_token), db: AsyncSession = Depends(get_db)):
    """Получить информацию о текущем пользователе"""
    # Совместимость: username в токене может быть email (старые токены)
    result = await db.execute(select(User).where(or_(User.username == username, User.email == username)))
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
            "engineer_id": str(db_user.engineer_id) if db_user.engineer_id else None
        }

    user = USERS_DB.get(username)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "id": None,
        "username": username,
        "role": user["role"],
        "permissions": user["permissions"]
    }
