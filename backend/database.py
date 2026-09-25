import os
import logging
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from sqlalchemy.pool import AsyncAdaptedQueuePool
import ssl
from pathlib import Path

logger = logging.getLogger(__name__)

DB_USER = os.getenv("DB_USER", "gen_user")
DB_PASS = os.getenv("DB_PASS", "")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "default_db")
DB_SSLMODE = (os.getenv("DB_SSLMODE", "verify-full") or "verify-full").strip().lower()
DB_SSLCERT = os.getenv("DB_SSLCERT", "/app/certs/root.crt")

DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"


def get_ssl_context(mode=None):
    mode = mode or DB_SSLMODE
    cafile = DB_SSLCERT if Path(DB_SSLCERT).is_file() else None
    if os.getenv("DB_SSLCERT") and cafile is None:
        raise ValueError("DB_SSLCERT указывает на отсутствующий сертификат")
    ssl_context = ssl.create_default_context(cafile=cafile)
    if mode in ("require", "prefer", "disable", "off", "false", "no", "none"):
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE
    elif mode == "verify-ca":
        ssl_context.check_hostname = False
    elif mode != "verify-full":
        raise ValueError(f"Неподдерживаемый DB_SSLMODE: {mode}")
    return ssl_context


connect_args: dict = {}
if DB_SSLMODE in ("disable", "off", "false", "no", "none"):
    # Локальная БД без TLS и Alembic на машине разработчика
    logger.info("[DB] SSL: отключён (DB_SSLMODE=%s)", DB_SSLMODE)
elif DB_SSLMODE in ("verify-full", "verify-ca", "require", "prefer"):
    connect_args["ssl"] = get_ssl_context()
    logger.info("[DB] SSL: %s", DB_SSLMODE)
else:
    raise ValueError(f"Неподдерживаемый DB_SSLMODE: {DB_SSLMODE}")

engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    poolclass=AsyncAdaptedQueuePool,
    pool_size=10,
    max_overflow=20,
    pool_timeout=30,
    pool_recycle=1800,
    pool_pre_ping=True,
    connect_args=connect_args,
)

AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)

Base = declarative_base()


async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
