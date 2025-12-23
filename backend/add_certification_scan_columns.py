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
        # scan_file_path
        await session.execute(text("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='certifications' AND column_name='scan_file_path'
                ) THEN
                    ALTER TABLE certifications ADD COLUMN scan_file_path varchar(500) NULL;
                END IF;
            END$$;
        """))

        # scan_file_name
        await session.execute(text("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='certifications' AND column_name='scan_file_name'
                ) THEN
                    ALTER TABLE certifications ADD COLUMN scan_file_name varchar(255) NULL;
                END IF;
            END$$;
        """))

        # scan_file_size
        await session.execute(text("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='certifications' AND column_name='scan_file_size'
                ) THEN
                    ALTER TABLE certifications ADD COLUMN scan_file_size integer NULL;
                END IF;
            END$$;
        """))

        # scan_mime_type
        await session.execute(text("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='certifications' AND column_name='scan_mime_type'
                ) THEN
                    ALTER TABLE certifications ADD COLUMN scan_mime_type varchar(100) NULL;
                END IF;
            END$$;
        """))

        await session.commit()
        print("✅ Миграция certifications: добавлены поля scan_file_* для сканов сертификатов.")


if __name__ == "__main__":
    asyncio.run(main())











