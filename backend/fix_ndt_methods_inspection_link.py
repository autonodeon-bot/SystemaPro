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
        # 1) inspection_id column
        await session.execute(text("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='ndt_methods' AND column_name='inspection_id'
                ) THEN
                    ALTER TABLE ndt_methods ADD COLUMN inspection_id uuid NULL;
                END IF;
            END$$;
        """))

        # 2) questionnaire_id nullable
        await session.execute(text("""
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='ndt_methods' AND column_name='questionnaire_id' AND is_nullable='NO'
                ) THEN
                    ALTER TABLE ndt_methods ALTER COLUMN questionnaire_id DROP NOT NULL;
                END IF;
            END$$;
        """))

        # 3) foreign keys (safe if already exist)
        await session.execute(text("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.table_constraints
                    WHERE table_name='ndt_methods' AND constraint_type='FOREIGN KEY'
                      AND constraint_name='ndt_methods_inspection_id_fkey'
                ) THEN
                    ALTER TABLE ndt_methods
                        ADD CONSTRAINT ndt_methods_inspection_id_fkey
                        FOREIGN KEY (inspection_id) REFERENCES inspections(id) ON DELETE SET NULL;
                END IF;
            END$$;
        """))

        # 4) index for inspection_id
        await session.execute(text("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_indexes
                    WHERE schemaname='public' AND tablename='ndt_methods' AND indexname='ix_ndt_methods_inspection_id'
                ) THEN
                    CREATE INDEX ix_ndt_methods_inspection_id ON ndt_methods (inspection_id);
                END IF;
            END$$;
        """))

        await session.commit()
        print("✅ Миграция ndt_methods: добавлен inspection_id, questionnaire_id теперь nullable, добавлены FK/индекс.")


if __name__ == "__main__":
    asyncio.run(main())











