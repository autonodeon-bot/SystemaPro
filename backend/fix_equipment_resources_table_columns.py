"""
Одноразовый фикс схемы БД для таблицы equipment_resources.

Причина: в старых БД отсутствует колонка equipment_resources.resource_type,
но она используется в предпросмотре и генерации отчетов.
"""

import asyncio
from sqlalchemy import text
from database import engine


async def main():
    async with engine.begin() as conn:
        await conn.execute(
            text(
                "ALTER TABLE equipment_resources "
                "ADD COLUMN IF NOT EXISTS resource_type VARCHAR(50)"
            )
        )
    print("OK: equipment_resources.resource_type ensured")


if __name__ == "__main__":
    asyncio.run(main())








