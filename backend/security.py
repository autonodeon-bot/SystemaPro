"""Security helpers: rate limiting, password policy, TOTP 2FA, RBAC matrix.

Модуль держит все security-примитивы в одном месте, чтобы не разбрасывать
логику по десяткам роутеров.
"""
from __future__ import annotations

import hashlib
import os
import re
import secrets
from dataclasses import dataclass
from io import BytesIO
from typing import Optional, Set

import pyotp
import qrcode
from fastapi import HTTPException, Request, status
from slowapi import Limiter
from slowapi.util import get_remote_address

# ─── Rate limiter (slowapi) ───────────────────────────────────────────────────
# Используем in-memory storage: для single-instance backend этого достаточно.
# При горизонтальном масштабировании перевести на Redis через `storage_uri`.
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[],  # лимиты навешиваются точечно на чувствительные endpoint'ы
    # headers_enabled=False: endpoint'ы возвращают dict (JSON), а не Response —
    # slowapi в этом случае не может дописать x-ratelimit-* заголовки.
    headers_enabled=False,
)

AUTH_RATE_LIMIT = os.getenv("AUTH_RATE_LIMIT", "10/minute")
AUTH_2FA_RATE_LIMIT = os.getenv("AUTH_2FA_RATE_LIMIT", "5/minute")
VERIFY_RATE_LIMIT = os.getenv("VERIFY_RATE_LIMIT", "60/minute")


# ─── Password policy ──────────────────────────────────────────────────────────
MIN_PASSWORD_LEN = int(os.getenv("MIN_PASSWORD_LEN", "10"))
_UPPER = re.compile(r"[A-ZА-ЯЁ]")
_LOWER = re.compile(r"[a-zа-яё]")
_DIGIT = re.compile(r"\d")
_SPECIAL = re.compile(r"[^A-Za-zА-Яа-яЁё0-9]")

# Топ слабых паролей (короткий список, основной щит — длина+классы+sha-1 если подключить HIBP).
_COMMON_PASSWORDS: Set[str] = {
    "password", "qwerty", "123456", "admin", "admin123", "welcome",
    "letmein", "monitor", "systema", "neftcontrol", "passw0rd",
}


@dataclass(frozen=True)
class PasswordValidationResult:
    ok: bool
    errors: tuple[str, ...]


def validate_password(password: str, *, username: Optional[str] = None) -> PasswordValidationResult:
    """Проверка политики пароля. Возвращает все найденные нарушения."""
    errs: list[str] = []
    if not password:
        return PasswordValidationResult(False, ("Пароль обязателен",))

    if len(password) < MIN_PASSWORD_LEN:
        errs.append(f"Минимальная длина пароля: {MIN_PASSWORD_LEN} символов")

    classes = sum(bool(rx.search(password)) for rx in (_UPPER, _LOWER, _DIGIT, _SPECIAL))
    if classes < 3:
        errs.append("Пароль должен содержать минимум 3 класса: буквы верхнего регистра, нижнего, цифры, спецсимволы")

    if password.lower() in _COMMON_PASSWORDS:
        errs.append("Пароль слишком простой — подберите менее распространённый")

    if username and username.lower() in password.lower():
        errs.append("Пароль не должен содержать ваш логин")

    return PasswordValidationResult(ok=not errs, errors=tuple(errs))


def enforce_password_policy(password: str, *, username: Optional[str] = None) -> None:
    """FastAPI-friendly обёртка: поднимает 400, если пароль слабый."""
    result = validate_password(password, username=username)
    if not result.ok:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "WEAK_PASSWORD",
                "message": "Пароль не соответствует политике безопасности",
                "errors": list(result.errors),
            },
        )


# ─── TOTP 2FA ─────────────────────────────────────────────────────────────────
TOTP_ISSUER = os.getenv("TOTP_ISSUER", "SystemaPro")


def generate_totp_secret() -> str:
    """Новый base32-секрет для TOTP."""
    return pyotp.random_base32()


def totp_provisioning_uri(secret: str, username: str) -> str:
    """otpauth://-URI для QR-кода Google/Yandex Authenticator."""
    return pyotp.TOTP(secret).provisioning_uri(name=username, issuer_name=TOTP_ISSUER)


def totp_qr_png(uri: str) -> bytes:
    """PNG QR-код (для отправки клиенту как image/png или base64)."""
    img = qrcode.make(uri)
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def verify_totp_code(secret: str, code: str, *, valid_window: int = 1) -> bool:
    """Проверка 6-значного кода (valid_window допускает ±N шагов, 1 шаг = 30 сек)."""
    if not secret or not code:
        return False
    try:
        return pyotp.TOTP(secret).verify(code.strip(), valid_window=valid_window)
    except Exception:
        return False


def hash_recovery_code(code: str) -> str:
    """Sha256 recovery-кода для хранения в БД (оригинал не хранится)."""
    return hashlib.sha256(code.strip().upper().encode("utf-8")).hexdigest()


def generate_recovery_codes(n: int = 8) -> list[str]:
    """Одноразовые recovery-коды: XXXX-XXXX (Crockford base32 без похожих символов)."""
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # без 0/1/I/O
    codes = []
    for _ in range(n):
        raw = "".join(secrets.choice(alphabet) for _ in range(8))
        codes.append(f"{raw[:4]}-{raw[4:]}")
    return codes


# ─── Unified RBAC matrix ──────────────────────────────────────────────────────
# Карта permission → список ролей, которым он выдан.
# Центральная точка — любые новые endpoint'ы должны указывать permission отсюда.
PERMISSION_MATRIX: dict[str, Set[str]] = {
    # Users / RBAC
    "users.read": {"admin", "chief_operator"},
    "users.write": {"admin"},
    "users.delete": {"admin"},
    # Assignments
    "assignments.read": {"admin", "chief_operator", "engineer", "client"},
    "assignments.write": {"admin", "chief_operator"},
    "assignments.perform": {"engineer"},
    # Equipment
    "equipment.read": {"admin", "chief_operator", "engineer", "client"},
    "equipment.write": {"admin", "chief_operator"},
    "equipment.delete": {"admin"},
    # Reports
    "reports.read": {"admin", "chief_operator", "engineer", "client"},
    "reports.write": {"admin", "chief_operator", "engineer"},
    "reports.sign": {"admin", "chief_operator"},  # только подписанты
    "reports.delete": {"admin"},
    # Dictionaries (оператору нужны клиенты/проекты в UI)
    "dictionaries.read": {"admin", "chief_operator", "engineer", "client", "operator"},
    "dictionaries.write": {"admin", "chief_operator", "operator"},
    # Admin
    "admin.panel": {"admin"},
    "admin.audit": {"admin"},
    "admin.metrics": {"admin"},
}


def role_has_permission(role: Optional[str], permission: str) -> bool:
    if not role:
        return False
    allowed = PERMISSION_MATRIX.get(permission)
    if allowed is None:
        # Unknown permission → считаем, что только admin допущен (fail-closed).
        return role == "admin"
    return role in allowed or role == "admin"


def require_rbac(permission: str):
    """Dependency-фабрика: проверяет, что текущая роль имеет permission.

    Использование:
        @router.get("/secret")
        async def secret(user=Depends(require_rbac("admin.panel"))):
            ...
    """
    # Импорт локальный — чтобы избежать циклических зависимостей (auth.py → security.py).
    from fastapi import Depends
    from jose import JWTError, jwt
    from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

    from auth import ALGORITHM, SECRET_KEY

    bearer = HTTPBearer()

    async def _checker(
        credentials: HTTPAuthorizationCredentials = Depends(bearer),
    ) -> dict:
        try:
            payload = jwt.decode(
                credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM]
            )
        except JWTError:
            raise HTTPException(status_code=401, detail="Invalid token")

        username = payload.get("sub")
        role = payload.get("role")
        if not username or not role:
            raise HTTPException(status_code=401, detail="Invalid token payload")

        if not role_has_permission(role, permission):
            raise HTTPException(
                status_code=403,
                detail={
                    "code": "FORBIDDEN",
                    "message": f"Требуется право '{permission}'",
                },
            )
        return {"username": username, "role": role}

    return _checker


# ─── Client IP (для аудита, rate-limit) ───────────────────────────────────────
def client_ip(request: Request) -> str:
    """Берёт X-Forwarded-For (первый hop) или client.host."""
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else "0.0.0.0"
