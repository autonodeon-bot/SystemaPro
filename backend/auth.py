"""
Базовая система аутентификации и авторизации
"""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from datetime import datetime, timedelta
from typing import Optional
import os

# Конфигурация JWT
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "your-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 24 часа

security = HTTPBearer()

# Простая база пользователей (в продакшене использовать БД)
USERS_DB = {
    "admin": {
        "password": "admin123",  # В продакшене использовать хеширование
        "role": "admin",
        "permissions": ["read", "write", "delete", "admin"]
    },
    "engineer": {
        "password": "engineer123",
        "role": "engineer",
        "permissions": ["read", "write"]
    },
    "client": {
        "password": "client123",
        "role": "client",
        "permissions": ["read"]
    }
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

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Проверка JWT токена"""
    try:
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

def get_user_permissions(username: str) -> list:
    """Получить права пользователя"""
    user = USERS_DB.get(username)
    if user:
        return user.get("permissions", [])
    return []

def require_permission(permission: str):
    """Декоратор для проверки прав доступа"""
    def permission_checker(username: str = Depends(verify_token)):
        user = USERS_DB.get(username)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="User not found"
            )
        permissions = user.get("permissions", [])
        if permission not in permissions and "admin" not in permissions:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Permission '{permission}' required"
            )
        return username
    return permission_checker

# Роли и их права
ROLE_PERMISSIONS = {
    "admin": ["read", "write", "delete", "admin"],
    "engineer": ["read", "write"],
    "client": ["read"]
}



