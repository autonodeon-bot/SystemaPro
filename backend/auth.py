"""
Базовая система аутентификации и авторизации
"""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from datetime import datetime, timedelta
from typing import Optional
import os
from passlib.context import CryptContext
import bcrypt

# Конфигурация JWT
_SECRET_DEFAULT = "your-secret-key-change-in-production"
SECRET_KEY = os.getenv("JWT_SECRET_KEY", _SECRET_DEFAULT)
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 24 часа

_INSECURE_JWT_SECRETS = frozenset({
    "",
    _SECRET_DEFAULT,
    "your-jwt-secret-key",
    "change-me",
    "changeme",
    "secret",
    "test-secret-key",
    "test-secret-key-for-pytest",
})


def assert_production_secrets() -> None:
    """Запрет слабого JWT в production (вызывается из main.startup)."""
    env = os.getenv("APP_ENV", os.getenv("SENTRY_ENVIRONMENT", "production")).lower()
    if env in ("local", "development", "dev", "test"):
        return
    key = os.getenv("JWT_SECRET_KEY", "")
    if key in _INSECURE_JWT_SECRETS or len(key) < 24:
        raise RuntimeError(
            "JWT_SECRET_KEY должен быть задан и содержать не менее 24 символов в production"
        )

security = HTTPBearer()

# Контекст для хеширования паролей
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Функции для работы с паролями
def hash_password(password: str) -> str:
    """Хеширование пароля с использованием bcrypt"""
    # bcrypt имеет ограничение в 72 байта для пароля
    # Используем bcrypt напрямую для обхода проблем с passlib
    password_bytes = password.encode('utf-8')
    if len(password_bytes) > 72:
        password_bytes = password_bytes[:72]
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Проверка пароля"""
    try:
        # Сначала пробуем через passlib
        return pwd_context.verify(plain_password, hashed_password)
    except:
        # Если не получилось, пробуем через bcrypt напрямую
        try:
            password_bytes = plain_password.encode('utf-8')
            if len(password_bytes) > 72:
                password_bytes = password_bytes[:72]
            hashed_bytes = hashed_password.encode('utf-8')
            return bcrypt.checkpw(password_bytes, hashed_bytes)
        except:
            return False

# Роли и их права (источник прав — только БД + ROLE_PERMISSIONS, без fallback-паролей)
ROLE_PERMISSIONS = {
    "admin": ["read", "write", "delete", "admin"],
    "chief_operator": ["read", "write", "delete", "admin"],
    "engineer": ["read", "write"],
    "operator": ["read", "write"],
    "client": ["read"],
}


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    """Создание JWT токена"""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def verify_token(credentials: Optional[HTTPAuthorizationCredentials] = Depends(security)):
    """Проверка JWT токена (обязательная авторизация)"""
    try:
        if credentials is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication credentials",
                headers={"WWW-Authenticate": "Bearer"},
            )
        token = credentials.credentials
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication credentials",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return username
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

def verify_token_optional(credentials: Optional[HTTPAuthorizationCredentials] = Depends(HTTPBearer(auto_error=False))):
    """Проверка JWT токена (опциональная авторизация - как в версии 3.2.8)"""
    try:
        if credentials is None:
            return None
        token = credentials.credentials
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            return None
        return username
    except (JWTError, Exception):
        return None

def get_user_permissions(username: str, role: Optional[str] = None) -> list:
    """Получить права пользователя по роли (legacy helper для тестов)."""
    if role:
        return ROLE_PERMISSIONS.get(role, [])
    return []

def require_permission(permission: str, role: str):
    """Проверка права по роли (legacy helper для тестов)."""
    permissions = ROLE_PERMISSIONS.get(role, [])
    if permission not in permissions and "admin" not in permissions:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Permission '{permission}' required",
        )
    return role
