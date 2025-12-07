"""
Миграция: создание таблиц и полей для offline-first режима
"""
import asyncio
from sqlalchemy import text
from database import engine
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def create_offline_tables():
    """Создать таблицы и поля для offline-first режима"""
    async with engine.begin() as conn:
        try:
            # 1. Добавляем поля в таблицу inspections
            logger.info("Добавление полей в таблицу inspections...")
            
            # Проверяем, существует ли колонка client_id
            check_client_id = await conn.execute(text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'inspections' AND column_name = 'client_id'
            """))
            if check_client_id.rowcount == 0:
                await conn.execute(text("""
                    ALTER TABLE inspections 
                    ADD COLUMN client_id UUID
                """))
                logger.info("✅ Колонка client_id добавлена в inspections")
            else:
                logger.info("ℹ️  Колонка client_id уже существует")
            
            # Проверяем, существует ли колонка is_synced
            check_is_synced = await conn.execute(text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'inspections' AND column_name = 'is_synced'
            """))
            if check_is_synced.rowcount == 0:
                await conn.execute(text("""
                    ALTER TABLE inspections 
                    ADD COLUMN is_synced BOOLEAN DEFAULT FALSE
                """))
                logger.info("✅ Колонка is_synced добавлена в inspections")
            else:
                logger.info("ℹ️  Колонка is_synced уже существует")
            
            # Проверяем, существует ли колонка synced_at
            check_synced_at = await conn.execute(text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'inspections' AND column_name = 'synced_at'
            """))
            if check_synced_at.rowcount == 0:
                await conn.execute(text("""
                    ALTER TABLE inspections 
                    ADD COLUMN synced_at TIMESTAMPTZ
                """))
                logger.info("✅ Колонка synced_at добавлена в inspections")
            else:
                logger.info("ℹ️  Колонка synced_at уже существует")
            
            # Проверяем, существует ли колонка offline_task_id
            check_offline_task_id = await conn.execute(text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'inspections' AND column_name = 'offline_task_id'
            """))
            if check_offline_task_id.rowcount == 0:
                await conn.execute(text("""
                    ALTER TABLE inspections 
                    ADD COLUMN offline_task_id UUID
                """))
                logger.info("✅ Колонка offline_task_id добавлена в inspections")
            else:
                logger.info("ℹ️  Колонка offline_task_id уже существует")
            
            # 2. Создаем таблицу offline_tasks
            logger.info("Создание таблицы offline_tasks...")
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS offline_tasks (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    name VARCHAR(255) NOT NULL,
                    equipment_ids JSONB,
                    downloaded_at TIMESTAMPTZ,
                    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '95 days'),
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    updated_at TIMESTAMPTZ
                )
            """))
            logger.info("✅ Таблица offline_tasks создана")
            
            # Создаем индексы для производительности
            logger.info("Создание индексов...")
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_offline_tasks_user_id 
                ON offline_tasks(user_id)
            """))
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_inspections_client_id 
                ON inspections(client_id) WHERE client_id IS NOT NULL
            """))
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_inspections_is_synced 
                ON inspections(is_synced) WHERE is_synced = FALSE
            """))
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_inspections_offline_task_id 
                ON inspections(offline_task_id) WHERE offline_task_id IS NOT NULL
            """))
            logger.info("✅ Индексы созданы")
            
            # 3. Добавляем поле offline_pin_hash в таблицу users (для проверки PIN при синхронизации)
            logger.info("Добавление поля offline_pin_hash в таблицу users...")
            check_offline_pin_hash = await conn.execute(text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'users' AND column_name = 'offline_pin_hash'
            """))
            if check_offline_pin_hash.rowcount == 0:
                await conn.execute(text("""
                    ALTER TABLE users 
                    ADD COLUMN offline_pin_hash VARCHAR(64)
                """))
                logger.info("✅ Колонка offline_pin_hash добавлена в users")
            else:
                logger.info("ℹ️  Колонка offline_pin_hash уже существует")
            
            logger.info("✅ Все таблицы и поля для offline-first режима успешно созданы!")
            
        except Exception as e:
            logger.error(f"❌ Ошибка при создании таблиц: {e}")
            raise


if __name__ == "__main__":
    asyncio.run(create_offline_tables())

