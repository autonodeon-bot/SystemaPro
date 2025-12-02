import os
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy.pool import NullPool
import ssl

# Database configuration
DB_USER = os.getenv("DB_USER", "gen_user")
DB_PASS = os.getenv("DB_PASS", "")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "default_db")
DB_SSLMODE = os.getenv("DB_SSLMODE", "verify-full")
DB_SSLCERT = os.getenv("DB_SSLCERT", "/app/certs/root.crt")

# Construct database URL
DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# SSL configuration for asyncpg
# Для самоподписанных сертификатов используем режим без строгой проверки
def get_ssl_context():
    """Create SSL context for database connection (without strict verification for self-signed certs)"""
    # Создаем контекст без проверки сертификата для самоподписанных сертификатов
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE
    return ssl_context

# Create async engine with SSL configuration
connect_args = {}
# Для самоподписанных сертификатов всегда используем режим без проверки
# asyncpg поддерживает либо строку "require" (SSL без проверки), либо SSLContext
# Используем SSLContext с отключенной проверкой для самоподписанных сертификатов
print(f"🔐 SSL Mode: {DB_SSLMODE}")
if DB_SSLMODE in ["verify-full", "require", "prefer"]:
    # Для самоподписанных сертификатов используем контекст без проверки
    connect_args["ssl"] = get_ssl_context()
    print("✅ Using SSL without certificate verification (self-signed cert)")
else:
    # Default: require SSL but don't verify certificate
    connect_args["ssl"] = "require"
    print("✅ Using SSL require mode")

engine = create_async_engine(
    DATABASE_URL,
    echo=True,
    poolclass=NullPool,
    connect_args=connect_args
)

# Create session factory
# Для SQLAlchemy 1.4 используем sessionmaker
try:
    from sqlalchemy.ext.asyncio import async_sessionmaker
    AsyncSessionLocal = async_sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )
except ImportError:
    # Fallback для старых версий SQLAlchemy
    from sqlalchemy.orm import sessionmaker
    AsyncSessionLocal = sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

# Base class for models
Base = declarative_base()

# Dependency to get DB session
async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
