"""
Async Alembic environment (SQLAlchemy 2.0 + asyncpg).

URL и SSL совпадают с database.py (переменные DB_* / DATABASE_URL).
"""
from __future__ import annotations

import asyncio
import os
import sys
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context

# Корень backend в PYTHONPATH
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database import Base, DATABASE_URL, connect_args  # noqa: E402
import models  # noqa: F401, E402 — регистрация таблиц в metadata

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def get_async_url() -> str:
    """Тот же источник, что и у приложения: модуль database (DB_* в окружении)."""
    env_url = os.environ.get("DATABASE_URL")
    if env_url:
        if env_url.startswith("postgresql://") and "+asyncpg" not in env_url:
            return env_url.replace("postgresql://", "postgresql+asyncpg://", 1)
        if not env_url.startswith("postgresql+asyncpg://"):
            raise ValueError(
                "DATABASE_URL должен быть postgresql+asyncpg://... или postgresql://..."
            )
        return env_url
    return DATABASE_URL


def run_migrations_offline() -> None:
    """Режим `alembic upgrade head --sql` (без живого подключения)."""
    url = get_async_url()
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
    )

    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    section = config.get_section(config.config_ini_section) or {}
    section = dict(section)
    section["sqlalchemy.url"] = get_async_url()

    connectable = async_engine_from_config(
        section,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
        connect_args=connect_args,
    )

    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)

    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
