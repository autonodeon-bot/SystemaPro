"""
Миграция: добавление полей группировки обследований в таблицу inspections.
"""

from sqlalchemy import text

from database import engine


async def run():
    async with engine.begin() as conn:
        await conn.execute(
            text(
                """
                ALTER TABLE inspections
                ADD COLUMN IF NOT EXISTS inspection_type VARCHAR(50);
                """
            )
        )
        await conn.execute(
            text(
                """
                ALTER TABLE inspections
                ADD COLUMN IF NOT EXISTS inspection_method VARCHAR(50);
                """
            )
        )
        await conn.execute(
            text(
                """
                ALTER TABLE inspections
                ADD COLUMN IF NOT EXISTS inspection_category VARCHAR(100);
                """
            )
        )
        await conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_inspections_grouping_type
                ON inspections(inspection_type);
                """
            )
        )
        await conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_inspections_grouping_method
                ON inspections(inspection_method);
                """
            )
        )
        await conn.execute(
            text(
                """
                CREATE INDEX IF NOT EXISTS idx_inspections_grouping_category
                ON inspections(inspection_category);
                """
            )
        )
    print("OK: added inspection grouping columns/indexes")


if __name__ == "__main__":
    import asyncio

    asyncio.run(run())
