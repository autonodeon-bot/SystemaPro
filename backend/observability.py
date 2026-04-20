"""Observability: Sentry + Prometheus + structured logging (loguru).

Включается через переменные окружения — модуль не мешает локальной разработке,
если их нет.

Переменные:
- SENTRY_DSN                — URL DSN из проекта Sentry. Если пусто, Sentry не инициализируется.
- SENTRY_ENVIRONMENT        — production / staging / local. По умолчанию `local`.
- SENTRY_TRACES_SAMPLE_RATE — 0.0..1.0 (traces). По умолчанию 0.1.
- APP_VERSION               — версия релиза для Sentry (release).
- LOG_LEVEL                 — DEBUG / INFO / WARNING. По умолчанию INFO.
- LOG_JSON                  — "1" → JSON-логи (prod), иначе цветной текст (dev).

Использование:
    from observability import init_observability, metrics_router, record_request
    init_observability(app)
    app.include_router(metrics_router)
"""
from __future__ import annotations

import logging
import os
import sys
import time
from typing import Optional

from fastapi import APIRouter, FastAPI, Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

try:
    import sentry_sdk
    from sentry_sdk.integrations.asyncio import AsyncioIntegration
    from sentry_sdk.integrations.fastapi import FastApiIntegration
    from sentry_sdk.integrations.logging import LoggingIntegration
    from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration

    _SENTRY_AVAILABLE = True
except Exception:  # pragma: no cover - runtime env guard
    _SENTRY_AVAILABLE = False

try:
    from loguru import logger as _loguru_logger

    _LOGURU_AVAILABLE = True
except Exception:  # pragma: no cover
    _LOGURU_AVAILABLE = False


# ─── Prometheus registry ──────────────────────────────────────────────────────
_registry = CollectorRegistry()

http_requests_total = Counter(
    "http_requests_total",
    "HTTP-запросы по endpoint/method/status",
    ["method", "path", "status"],
    registry=_registry,
)

http_request_duration_seconds = Histogram(
    "http_request_duration_seconds",
    "Длительность HTTP-запросов",
    ["method", "path"],
    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
    registry=_registry,
)

report_generation_seconds = Histogram(
    "report_generation_seconds",
    "Время генерации отчётов (Word/PDF)",
    ["kind"],
    buckets=(0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0, 120.0),
    registry=_registry,
)

auth_login_total = Counter(
    "auth_login_total",
    "Попытки входа",
    ["result"],  # success | fail | locked
    registry=_registry,
)

active_users = Gauge(
    "active_users",
    "Количество активных пользователей за последние 5 минут",
    registry=_registry,
)

db_pool_size = Gauge(
    "db_pool_size",
    "Размер connection pool SQLAlchemy",
    registry=_registry,
)


# ─── Logging (loguru, если установлен) ────────────────────────────────────────
class InterceptHandler(logging.Handler):
    """Перенаправление stdlib logging → loguru."""

    def emit(self, record: logging.LogRecord) -> None:  # pragma: no cover
        try:
            level = _loguru_logger.level(record.levelname).name
        except ValueError:
            level = record.levelno
        frame, depth = logging.currentframe(), 2
        while frame.f_code.co_filename == logging.__file__:
            frame = frame.f_back  # type: ignore[assignment]
            depth += 1
        _loguru_logger.opt(depth=depth, exception=record.exc_info).log(
            level, record.getMessage()
        )


def _configure_logging() -> None:
    level = os.getenv("LOG_LEVEL", "INFO").upper()
    json_mode = os.getenv("LOG_JSON", "0") == "1"

    if not _LOGURU_AVAILABLE:
        logging.basicConfig(
            level=level,
            format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
        )
        return

    _loguru_logger.remove()
    if json_mode:
        _loguru_logger.add(
            sys.stdout,
            level=level,
            serialize=True,
            enqueue=True,
            backtrace=False,
            diagnose=False,
        )
    else:
        _loguru_logger.add(
            sys.stdout,
            level=level,
            enqueue=True,
            backtrace=True,
            diagnose=False,
            format=(
                "<green>{time:YYYY-MM-DD HH:mm:ss.SSS}</green> | "
                "<level>{level: <8}</level> | "
                "<cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> | "
                "<level>{message}</level>"
            ),
        )

    # Перенаправляем stdlib logging и uvicorn в loguru
    logging.basicConfig(handlers=[InterceptHandler()], level=level, force=True)
    for noisy in ("uvicorn", "uvicorn.access", "uvicorn.error", "fastapi"):
        _log = logging.getLogger(noisy)
        _log.handlers = [InterceptHandler()]
        _log.propagate = False


# ─── Sentry ───────────────────────────────────────────────────────────────────
def _init_sentry() -> None:
    if not _SENTRY_AVAILABLE:
        return
    dsn = os.getenv("SENTRY_DSN", "").strip()
    if not dsn:
        return

    env = os.getenv("SENTRY_ENVIRONMENT", "local")
    release = os.getenv("APP_VERSION", None)
    traces = float(os.getenv("SENTRY_TRACES_SAMPLE_RATE", "0.1"))

    sentry_sdk.init(
        dsn=dsn,
        environment=env,
        release=release,
        traces_sample_rate=max(0.0, min(1.0, traces)),
        send_default_pii=False,
        attach_stacktrace=True,
        integrations=[
            FastApiIntegration(transaction_style="endpoint"),
            SqlalchemyIntegration(),
            AsyncioIntegration(),
            LoggingIntegration(level=logging.INFO, event_level=logging.ERROR),
        ],
    )


# ─── HTTP middleware ──────────────────────────────────────────────────────────
def _path_template(request: Request) -> str:
    """Свести /api/users/<uuid> к /api/users/{id} для cardinality-safe метрик."""
    route = request.scope.get("route")
    if route and hasattr(route, "path"):
        return route.path
    return request.url.path


async def _metrics_middleware(request: Request, call_next):
    start = time.monotonic()
    try:
        response = await call_next(request)
        status = response.status_code
    except Exception:
        http_requests_total.labels(
            method=request.method, path=_path_template(request), status="500"
        ).inc()
        raise
    else:
        elapsed = time.monotonic() - start
        path = _path_template(request)
        http_requests_total.labels(
            method=request.method, path=path, status=str(status)
        ).inc()
        http_request_duration_seconds.labels(
            method=request.method, path=path
        ).observe(elapsed)
        return response


# ─── Public API ───────────────────────────────────────────────────────────────
metrics_router = APIRouter(tags=["observability"])


@metrics_router.get("/metrics", include_in_schema=False)
async def prometheus_metrics() -> Response:
    """Prometheus exposition format."""
    data = generate_latest(_registry)
    return Response(content=data, media_type=CONTENT_TYPE_LATEST)


def init_observability(app: FastAPI) -> None:
    """Включить Sentry, Prometheus-middleware и структурированное логирование."""
    _configure_logging()
    _init_sentry()
    app.middleware("http")(_metrics_middleware)


def record_report_generation(kind: str, seconds: float) -> None:
    """Хук из отчётных генераторов — измеряет длительность."""
    report_generation_seconds.labels(kind=kind).observe(seconds)


def record_login(result: str) -> None:
    """result: success | fail | locked | 2fa_required"""
    auth_login_total.labels(result=result).inc()


def get_logger(name: Optional[str] = None):
    """Единая точка получения логгера."""
    if _LOGURU_AVAILABLE:
        return _loguru_logger.bind(module=name or "app")
    return logging.getLogger(name or "app")
