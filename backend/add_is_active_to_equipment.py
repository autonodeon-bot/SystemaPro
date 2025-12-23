"""
Добавление колонки is_active в таблицу equipment
"""
import asyncio
import os
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
import ssl

# Database configuration
DB_USER = os.getenv("DB_USER", "gen_user")
DB_PASS = os.getenv("DB_PASS", "#BeH)(rn;Cl}7a")
DB_HOST = os.getenv("DB_HOST", "99f541abb57e364deed82c1d.twc1.net")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "default_db")

DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

def get_ssl_context():
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE
    return ssl_context

engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    connect_args={"ssl": get_ssl_context()}
)

async def add_is_active_column():
    """Добавление колонки is_active в таблицу equipment"""
    
    async with AsyncSession(engine) as session:
        try:
            # Добавляем колонку is_active, если её нет
            await session.execute(text("""
                ALTER TABLE equipment 
                ADD COLUMN IF NOT EXISTS is_active INTEGER DEFAULT 1;
            """))
            
            # Обновляем существующие записи, устанавливая is_active = 1
            await session.execute(text("""
                UPDATE equipment 
                SET is_active = 1
                WHERE is_active IS NULL;
            """))
            
            await session.commit()
            print("[OK] Колонка is_active успешно добавлена в таблицу equipment!")
            
        except Exception as e:
            await session.rollback()
            print(f"[ERROR] Ошибка при добавлении колонки: {e}")
            import traceback
            traceback.print_exc()
            raise

if __name__ == "__main__":
    asyncio.run(add_is_active_column())











