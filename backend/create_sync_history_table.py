"""
Миграция: создание таблицы sync_history для истории синхронизаций
"""
import asyncio
from sqlalchemy import text
from database import engine
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def create_sync_history_table():
    """Создать таблицу sync_history"""
    async with engine.begin() as conn:
        try:
            logger.info("Создание таблицы sync_history...")
            
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS sync_history (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    inspection_ids UUID[] NOT NULL,
                    synced_count INTEGER NOT NULL,
                    failed_count INTEGER DEFAULT 0,
                    sync_type VARCHAR(50) DEFAULT 'offline',
                    created_at TIMESTAMPTZ DEFAULT NOW()
                );
            """))
            
            logger.info("✅ Таблица sync_history создана")
            
            # Создаем индексы
            logger.info("Создание индексов...")
            
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_sync_history_user_id
                ON sync_history(user_id);
            """))
            
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_sync_history_created_at
                ON sync_history(created_at DESC);
            """))
            
            logger.info("✅ Индексы созданы")
            
        except Exception as e:
            logger.error(f"Ошибка при создании таблицы sync_history: {e}", exc_info=True)
            raise


if __name__ == "__main__":
    asyncio.run(create_sync_history_table())

