"""
Скрипт для создания таблицы ndt_methods в базе данных
"""
import asyncio
from sqlalchemy import text
from database import engine, AsyncSessionLocal
from models import NDTMethod, Base

async def create_ndt_methods_table():
    """Создать таблицу ndt_methods если её нет"""
    async with engine.begin() as conn:
        try:
            # Проверяем, существует ли таблица
            result = await conn.execute(
                text("""
                    SELECT EXISTS (
                        SELECT FROM information_schema.tables 
                        WHERE table_schema = 'public' 
                        AND table_name = 'ndt_methods'
                    );
                """)
            )
            table_exists = result.scalar()
            
            if table_exists:
                print("⚠️  Таблица ndt_methods уже существует. Пропускаем создание.")
                return
            
            # Создаем таблицу через SQLAlchemy
            await conn.run_sync(Base.metadata.create_all)
            
            # Альтернативный способ - через прямой SQL
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS ndt_methods (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    inspection_id UUID REFERENCES inspections(id),
                    questionnaire_id UUID REFERENCES questionnaires(id),
                    report_id UUID REFERENCES reports(id),
                    equipment_id UUID NOT NULL REFERENCES equipment(id),
                    method_code VARCHAR(50) NOT NULL,
                    method_name VARCHAR(255) NOT NULL,
                    is_performed INTEGER DEFAULT 0,
                    standard VARCHAR(255),
                    equipment VARCHAR(255),
                    inspector_name VARCHAR(255),
                    inspector_level VARCHAR(10),
                    results TEXT,
                    defects TEXT,
                    conclusion TEXT,
                    photos JSONB,
                    additional_data JSONB,
                    performed_date TIMESTAMP WITH TIME ZONE,
                    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE
                );
            """))
            
            # Создаем индексы
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_ndt_methods_equipment_id 
                ON ndt_methods(equipment_id);
            """))
            
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_ndt_methods_questionnaire_id 
                ON ndt_methods(questionnaire_id);
            """))
            
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_ndt_methods_inspection_id 
                ON ndt_methods(inspection_id);
            """))
            
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_ndt_methods_method_code 
                ON ndt_methods(method_code);
            """))
            
            print("✅ Таблица ndt_methods успешно создана!")
            print("   - Основная таблица")
            print("   - Индексы по equipment_id, questionnaire_id, inspection_id, method_code")
            
        except Exception as e:
            print(f"❌ Ошибка при создании таблицы: {e}")
            import traceback
            traceback.print_exc()
            raise

if __name__ == "__main__":
    asyncio.run(create_ndt_methods_table())













