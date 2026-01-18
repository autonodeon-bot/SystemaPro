#!/usr/bin/env python3
"""Скрипт для добавления столбца is_archived в таблицу inspections"""
import asyncio
from sqlalchemy import text
from database import engine

async def migrate():
    try:
        async with engine.begin() as conn:
            # Проверяем существование колонки
            result = await conn.execute(
                text("""
                    SELECT column_name 
                    FROM information_schema.columns 
                    WHERE table_name = 'inspections' 
                    AND column_name = 'is_archived'
                """)
            )
            column_exists = result.scalar() is not None
            
            if not column_exists:
                # Добавляем колонку с DEFAULT
                await conn.execute(
                    text(
                        "ALTER TABLE inspections "
                        "ADD COLUMN is_archived BOOLEAN DEFAULT FALSE NOT NULL"
                    )
                )
                print("✅ DB migration: inspections.is_archived added")
            else:
                print("✅ DB migration: inspections.is_archived already exists")
                # Проверяем, что она NOT NULL
                try:
                    await conn.execute(
                        text(
                            "ALTER TABLE inspections "
                            "ALTER COLUMN is_archived SET NOT NULL"
                        )
                    )
                    print("✅ DB migration: inspections.is_archived set to NOT NULL")
                except Exception as e:
                    print(f"✅ DB migration: inspections.is_archived already NOT NULL (or error: {e})")
    except Exception as e:
        print(f"❌ DB migration failed: {e}")
        import traceback
        traceback.print_exc()
        raise

if __name__ == "__main__":
    asyncio.run(migrate())
