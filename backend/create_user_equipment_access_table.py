"""
Скрипт для создания таблицы user_equipment_access в базе данных
"""
import asyncio
from sqlalchemy import text
from database import engine, Base
from models import UserEquipmentAccess

async def create_user_equipment_access_table():
    """Создать таблицу user_equipment_access"""
    try:
        async with engine.begin() as conn:
            # Проверяем, существует ли таблица
            result = await conn.execute(text("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    AND table_name = 'user_equipment_access'
                );
            """))
            exists = result.scalar()
            
            if exists:
                print("⚠️  Таблица user_equipment_access уже существует. Пропускаем создание.")
                return
            
            # Создаем таблицу
            await conn.run_sync(Base.metadata.create_all, tables=[UserEquipmentAccess.__table__])
            print("✅ Таблица user_equipment_access успешно создана!")
            
            # Создаем индексы
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_user_equipment_access_user_id ON user_equipment_access(user_id);
                CREATE INDEX IF NOT EXISTS idx_user_equipment_access_equipment_id ON user_equipment_access(equipment_id);
                CREATE INDEX IF NOT EXISTS idx_user_equipment_access_is_active ON user_equipment_access(is_active);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_user_equipment_access_unique ON user_equipment_access(user_id, equipment_id) WHERE is_active = 1;
            """))
            print("✅ Индексы для таблицы user_equipment_access созданы!")
            
    except Exception as e:
        print(f"❌ Ошибка при создании таблицы user_equipment_access: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(create_user_equipment_access_table())












