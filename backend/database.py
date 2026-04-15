import os
import logging
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from sqlalchemy.pool import AsyncAdaptedQueuePool
import ssl

logger = logging.getLogger(__name__)

DB_USER = os.getenv("DB_USER", "gen_user")
DB_PASS = os.getenv("DB_PASS", "")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "default_db")
DB_SSLMODE = (os.getenv("DB_SSLMODE", "verify-full") or "verify-full").strip().lower()
DB_SSLCERT = os.getenv("DB_SSLCERT", "/app/certs/root.crt")

DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"


def get_ssl_context():
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE
    return ssl_context


connect_args: dict = {}
if DB_SSLMODE in ("disable", "off", "false", "no", "none"):
    # Локальная БД без TLS и Alembic на машине разработчика
    logger.info("[DB] SSL: отключён (DB_SSLMODE=%s)", DB_SSLMODE)
elif DB_SSLMODE in ("verify-full", "require", "prefer"):
    connect_args["ssl"] = get_ssl_context()
    logger.info("[DB] SSL: self-signed cert mode")
else:
    connect_args["ssl"] = get_ssl_context()
    logger.info("[DB] SSL: нестандартный DB_SSLMODE=%s, используется контекст по умолчанию", DB_SSLMODE)

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
