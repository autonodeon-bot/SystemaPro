"""Добавляет колонку certification_area (область аттестации) в таблицу certifications."""
import asyncio
import sys
from sqlalchemy import text

from database import AsyncSessionLocal


async def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    async with AsyncSessionLocal() as session:
        await session.execute(text("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='certifications' AND column_name='certification_area'
                ) THEN
                    ALTER TABLE certifications ADD COLUMN certification_area varchar(255) NULL;
                END IF;
            END$$;
        """))
        await session.commit()
        print("Колонка certification_area добавлена в certifications (или уже существует).")


if __name__ == "__main__":
    asyncio.run(main())
