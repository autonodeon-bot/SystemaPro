"""
Скрипт для создания таблицы questionnaires в базе данных
"""
import asyncio
from sqlalchemy import text
from database import engine, AsyncSessionLocal
from models import Questionnaire, Base

async def create_questionnaires_table():
    """Создать таблицу questionnaires если её нет"""
    async with engine.begin() as conn:
        try:
            # Проверяем, существует ли таблица
            result = await conn.execute(
                text("""
                    SELECT EXISTS (
                        SELECT FROM information_schema.tables 
                        WHERE table_schema = 'public' 
                        AND table_name = 'questionnaires'
                    );
                """)
            )
            table_exists = result.scalar()
            
            if table_exists:
                print("⚠️  Таблица questionnaires уже существует. Пропускаем создание.")
                return
            
            # Создаем таблицу через SQLAlchemy
            await conn.run_sync(Base.metadata.create_all)
            
            # Альтернативный способ - через прямой SQL
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS questionnaires (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    equipment_id UUID NOT NULL REFERENCES equipment(id),
                    equipment_inventory_number VARCHAR(100),
                    equipment_name VARCHAR(255),
                    inspection_date DATE,
                    inspector_name VARCHAR(255),
                    inspector_position VARCHAR(255),
                    questionnaire_data JSONB,
                    created_by UUID REFERENCES users(id),
                    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE
                );
            """))
            
            # Создаем индексы
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_questionnaires_equipment_id 
                ON questionnaires(equipment_id);
            """))
            
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_questionnaires_created_at 
                ON questionnaires(created_at DESC);
            """))
            
            print("✅ Таблица questionnaires успешно создана!")
            print("   - Основная таблица")
            print("   - Индекс по equipment_id")
            print("   - Индекс по created_at")
            
        except Exception as e:
            print(f"❌ Ошибка при создании таблицы: {e}")
            import traceback
            traceback.print_exc()
            raise

if __name__ == "__main__":
    asyncio.run(create_questionnaires_table())





