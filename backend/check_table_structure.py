import asyncio
import sys
from sqlalchemy import text
from database import get_db

async def check_table_structure():
    sys.stdout.reconfigure(encoding='utf-8')
    async for db in get_db():
        try:
            result = await db.execute(text("""
                SELECT column_name, data_type 
                FROM information_schema.columns 
                WHERE table_name = 'hierarchy_engineer_assignments' 
                ORDER BY ordinal_position
            """))
            cols = result.all()
            print("Колонки в таблице hierarchy_engineer_assignments:")
            for col_name, col_type in cols:
                print(f"  - {col_name} ({col_type})")
        except Exception as e:
            print(f"Ошибка: {e}")
            import traceback
            traceback.print_exc()
        break

if __name__ == "__main__":
    asyncio.run(check_table_structure())











