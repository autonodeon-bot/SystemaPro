"""
Скрипт для создания таблиц workshops и workshop_engineer_access
"""
import asyncio
from sqlalchemy import text
from database import engine, AsyncSessionLocal
from models import Workshop, WorkshopEngineerAccess, Base

async def create_workshops_tables():
    """Создать таблицы workshops и workshop_engineer_access если их нет"""
    async with engine.begin() as conn:
        try:
            # Проверяем, существует ли таблица workshops
            result = await conn.execute(
                text("""
                    SELECT EXISTS (
                        SELECT FROM information_schema.tables 
                        WHERE table_schema = 'public' 
                        AND table_name = 'workshops'
                    );
                """)
            )
            workshops_exists = result.scalar()
            
            if not workshops_exists:
                # Создаем таблицу через SQLAlchemy
                await conn.run_sync(Base.metadata.create_all)
                
                # Альтернативный способ - через прямой SQL
                await conn.execute(text("""
                    CREATE TABLE IF NOT EXISTS workshops (
                        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                        name VARCHAR(255) NOT NULL,
                        code VARCHAR(50),
                        client_id UUID REFERENCES clients(id),
                        location VARCHAR(500),
                        description TEXT,
                        is_active INTEGER DEFAULT 1,
                        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                        updated_at TIMESTAMP WITH TIME ZONE
                    );
                """))
                
                print("✅ Таблица workshops создана!")
            else:
                print("⚠️  Таблица workshops уже существует.")
            
            # Проверяем, существует ли таблица workshop_engineer_access
            result = await conn.execute(
                text("""
                    SELECT EXISTS (
                        SELECT FROM information_schema.tables 
                        WHERE table_schema = 'public' 
                        AND table_name = 'workshop_engineer_access'
                    );
                """)
            )
            access_exists = result.scalar()
            
            if not access_exists:
                await conn.execute(text("""
                    CREATE TABLE IF NOT EXISTS workshop_engineer_access (
                        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                        workshop_id UUID NOT NULL REFERENCES workshops(id),
                        engineer_id UUID NOT NULL REFERENCES engineers(id),
                        access_type VARCHAR(50) DEFAULT 'read_write',
                        granted_by UUID REFERENCES users(id),
                        granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                        is_active BOOLEAN DEFAULT TRUE
                    );
                """))
                
                # Создаем индексы
                await conn.execute(text("""
                    CREATE INDEX IF NOT EXISTS idx_workshop_engineer_access_workshop_id 
                    ON workshop_engineer_access(workshop_id);
                """))
                
                await conn.execute(text("""
                    CREATE INDEX IF NOT EXISTS idx_workshop_engineer_access_engineer_id 
                    ON workshop_engineer_access(engineer_id);
                """))
                
                print("✅ Таблица workshop_engineer_access создана!")
            else:
                print("⚠️  Таблица workshop_engineer_access уже существует.")
            
            # Обновляем таблицу equipment - добавляем workshop_id и location если их нет
            await conn.execute(text("""
                DO $$ 
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns 
                        WHERE table_name = 'equipment' AND column_name = 'workshop_id'
                    ) THEN
                        ALTER TABLE equipment ADD COLUMN workshop_id UUID REFERENCES workshops(id);
                    END IF;
                    
                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns 
                        WHERE table_name = 'equipment' AND column_name = 'location'
                    ) THEN
                        ALTER TABLE equipment ADD COLUMN location VARCHAR(500);
                    END IF;
                END $$;
            """))
            
            await conn.execute(text("""
                DO $$ 
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns 
                        WHERE table_name = 'equipment' AND column_name = 'created_by'
                    ) THEN
                        ALTER TABLE equipment ADD COLUMN created_by UUID REFERENCES users(id);
                    END IF;
                END $$;
            """))
            
            print("✅ Таблица equipment обновлена (добавлены workshop_id и created_by)")
            
        except Exception as e:
            print(f"❌ Ошибка при создании таблиц: {e}")
            import traceback
            traceback.print_exc()
            raise

if __name__ == "__main__":
    asyncio.run(create_workshops_tables())

