import asyncio
import sys
from sqlalchemy import select
from database import get_db
from models import Enterprise

async def check_enterprises():
    sys.stdout.reconfigure(encoding='utf-8')
    async for db in get_db():
        try:
            result = await db.execute(select(Enterprise))
            enterprises = result.scalars().all()
            print(f"Всего предприятий: {len(enterprises)}")
            for e in enterprises:
                print(f"  - {e.name} (is_active={e.is_active})")
        except Exception as e:
            print(f"Ошибка: {e}")
            import traceback
            traceback.print_exc()
        break

if __name__ == "__main__":
    asyncio.run(check_enterprises())











