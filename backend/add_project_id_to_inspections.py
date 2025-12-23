"""
Скрипт для добавления колонки project_id в таблицу inspections
"""
import asyncio
from sqlalchemy import text
from database import engine

async def add_project_id_column():
    """Добавить колонку project_id в таблицу inspections"""
    try:
        async with engine.begin() as conn:
            # Проверяем, существует ли колонка
            result = await conn.execute(text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'inspections' 
                AND column_name = 'project_id';
            """))
            exists = result.scalar()
            
            if exists:
                print("⚠️  Колонка project_id уже существует. Пропускаем создание.")
                return
            
            # Добавляем колонку
            await conn.execute(text("""
                ALTER TABLE inspections 
                ADD COLUMN project_id UUID REFERENCES projects(id);
            """))
            print("✅ Колонка project_id успешно добавлена в таблицу inspections!")
            
    except Exception as e:
        print(f"❌ Ошибка при добавлении колонки project_id: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(add_project_id_column())












