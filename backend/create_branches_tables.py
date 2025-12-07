"""
Скрипт для создания таблиц branches и таблиц доступа для всех уровней иерархии
"""
import asyncio
from sqlalchemy import text
from database import engine, AsyncSessionLocal

async def create_branches_tables():
    """Создать таблицы для филиалов и многоуровневого доступа"""
    async with engine.begin() as conn:
        try:
            # Создаем таблицу branches
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS branches (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    name VARCHAR(255) NOT NULL,
                    code VARCHAR(50),
                    client_id UUID NOT NULL REFERENCES clients(id),
                    location VARCHAR(500),
                    description TEXT,
                    is_active INTEGER DEFAULT 1,
                    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE
                );
            """))
            print("✅ Таблица branches создана!")
            
            # Добавляем branch_id в workshops, если его нет
            await conn.execute(text("""
                DO $$ 
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns 
                        WHERE table_name = 'workshops' AND column_name = 'branch_id'
                    ) THEN
                        ALTER TABLE workshops ADD COLUMN branch_id UUID REFERENCES branches(id);
                    END IF;
                END $$;
            """))
            print("✅ Колонка branch_id добавлена в workshops")
            
            # Создаем таблицу client_engineer_access
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS client_engineer_access (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    client_id UUID NOT NULL REFERENCES clients(id),
                    engineer_id UUID NOT NULL REFERENCES engineers(id),
                    access_type VARCHAR(50) DEFAULT 'read_write',
                    granted_by UUID REFERENCES users(id),
                    granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                    is_active BOOLEAN DEFAULT TRUE
                );
            """))
            print("✅ Таблица client_engineer_access создана!")
            
            # Создаем таблицу branch_engineer_access
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS branch_engineer_access (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    branch_id UUID NOT NULL REFERENCES branches(id),
                    engineer_id UUID NOT NULL REFERENCES engineers(id),
                    access_type VARCHAR(50) DEFAULT 'read_write',
                    granted_by UUID REFERENCES users(id),
                    granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                    is_active BOOLEAN DEFAULT TRUE
                );
            """))
            print("✅ Таблица branch_engineer_access создана!")
            
            # Создаем таблицу equipment_type_engineer_access
            await conn.execute(text("""
                CREATE TABLE IF NOT EXISTS equipment_type_engineer_access (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    equipment_type_id UUID NOT NULL REFERENCES equipment_types(id),
                    engineer_id UUID NOT NULL REFERENCES engineers(id),
                    access_type VARCHAR(50) DEFAULT 'read_write',
                    granted_by UUID REFERENCES users(id),
                    granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                    is_active BOOLEAN DEFAULT TRUE
                );
            """))
            print("✅ Таблица equipment_type_engineer_access создана!")
            
            # Добавляем inspection_ids в reports, если его нет
            await conn.execute(text("""
                DO $$ 
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns 
                        WHERE table_name = 'reports' AND column_name = 'inspection_ids'
                    ) THEN
                        ALTER TABLE reports ADD COLUMN inspection_ids JSONB;
                        -- Делаем inspection_id nullable, так как отчет может объединять несколько обследований
                        ALTER TABLE reports ALTER COLUMN inspection_id DROP NOT NULL;
                    END IF;
                END $$;
            """))
            print("✅ Колонка inspection_ids добавлена в reports")
            
            print("\n✅ Все таблицы успешно созданы!")
            
        except Exception as e:
            print(f"❌ Ошибка при создании таблиц: {e}")
            import traceback
            traceback.print_exc()
            raise

if __name__ == "__main__":
    asyncio.run(create_branches_tables())



