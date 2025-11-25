import os
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
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
def get_ssl_context():
    """Create SSL context for database connection"""
    if DB_SSLCERT and os.path.exists(DB_SSLCERT):
        ssl_context = ssl.create_default_context(cafile=DB_SSLCERT)
        ssl_context.check_hostname = True
        ssl_context.verify_mode = ssl.CERT_REQUIRED
        return ssl_context
    else:
        # Fallback to require SSL without certificate verification
        ssl_context = ssl.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE
        return ssl_context

# Create async engine with SSL configuration
connect_args = {}
if DB_SSLMODE == "verify-full" and DB_SSLCERT and os.path.exists(DB_SSLCERT):
    connect_args["ssl"] = get_ssl_context()
else:
    # Require SSL but don't verify certificate
    connect_args["ssl"] = "require"

engine = create_async_engine(
    DATABASE_URL,
    echo=True,
    poolclass=NullPool,
    connect_args=connect_args
)

# Create session factory
AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
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
