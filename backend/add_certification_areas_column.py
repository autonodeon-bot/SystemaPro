"""Добавляет колонку certification_areas (JSONB — список областей аттестации) в таблицу certifications."""
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
                    WHERE table_name='certifications' AND column_name='certification_areas'
                ) THEN
                    ALTER TABLE certifications ADD COLUMN certification_areas jsonb NULL;
                END IF;
            END$$;
        """))
        await session.execute(text("""
            UPDATE certifications
            SET certification_areas = to_jsonb(ARRAY[certification_area]::text[])
            WHERE certification_area IS NOT NULL AND (certification_areas IS NULL OR certification_areas = 'null');
        """))
        await session.commit()
        print("Колонка certification_areas добавлена (или уже существует), старые данные перенесены.")


if __name__ == "__main__":
    asyncio.run(main())
