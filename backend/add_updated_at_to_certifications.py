import asyncio
import sys
from sqlalchemy import text
from database import get_db

sys.stdout.reconfigure(encoding='utf-8')

async def add_updated_at():
    async for db in get_db():
        try:
            await db.execute(text("ALTER TABLE certifications ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE"))
            await db.commit()
            print("✅ Колонка updated_at добавлена")
            break
        except Exception as e:
            await db.rollback()
            print(f"❌ Ошибка: {e}")
            break

if __name__ == "__main__":
    asyncio.run(add_updated_at())











