"""
Миграция для создания единой системы оборудования версии 3.3.0
Создает:
1. Единую таблицу equipment с уникальными кодами
2. Таблицу assignments (задания на диагностику/экспертизу)
3. Таблицу inspection_history (история обследований)
4. Таблицу repair_journal (журнал ремонта)
"""

import asyncio
import os
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
import ssl

# Database configuration
DB_USER = os.getenv("DB_USER", "gen_user")
DB_PASS = os.getenv("DB_PASS", "#BeH)(rn;Cl}7a")
DB_HOST = os.getenv("DB_HOST", "99f541abb57e364deed82c1d.twc1.net")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "default_db")

DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

def get_ssl_context():
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE
    return ssl_context

engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    connect_args={"ssl": get_ssl_context()}
)

async def create_unified_equipment_system():
    """Создание новой структуры для единой системы оборудования"""
    
    async with AsyncSession(engine) as session:
        try:
            # 1. Добавляем уникальный код оборудования в таблицу equipment
            await session.execute(text("""
                ALTER TABLE equipment 
                ADD COLUMN IF NOT EXISTS equipment_code VARCHAR(100) UNIQUE;
            """))
            
            # Создаем индекс для быстрого поиска по коду
            await session.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_equipment_code 
                ON equipment(equipment_code);
            """))
            
            # 2. Создаем таблицу заданий (assignments)
            await session.execute(text("""
                CREATE TABLE IF NOT EXISTS assignments (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    equipment_id UUID NOT NULL REFERENCES equipment(id) ON DELETE CASCADE,
                    assignment_type VARCHAR(50) NOT NULL, -- 'DIAGNOSTICS', 'EXPERTISE', 'INSPECTION'
                    assigned_by UUID REFERENCES users(id),
                    assigned_to UUID NOT NULL REFERENCES users(id),
                    status VARCHAR(50) DEFAULT 'PENDING', -- 'PENDING', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'
                    priority VARCHAR(20) DEFAULT 'NORMAL', -- 'LOW', 'NORMAL', 'HIGH', 'URGENT'
                    due_date TIMESTAMP WITH TIME ZONE,
                    description TEXT,
                    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                    completed_at TIMESTAMP WITH TIME ZONE,
                    CONSTRAINT chk_assignment_type CHECK (assignment_type IN ('DIAGNOSTICS', 'EXPERTISE', 'INSPECTION'))
                );
            """))
            
            await session.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_assignments_equipment 
                ON assignments(equipment_id);
            """))
            
            await session.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_assignments_assigned_to 
                ON assignments(assigned_to);
            """))
            
            await session.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_assignments_status 
                ON assignments(status);
            """))
            
            # 3. Создаем таблицу истории обследований
            await session.execute(text("""
                CREATE TABLE IF NOT EXISTS inspection_history (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    equipment_id UUID NOT NULL REFERENCES equipment(id) ON DELETE CASCADE,
                    assignment_id UUID REFERENCES assignments(id) ON DELETE SET NULL,
                    inspection_type VARCHAR(50) NOT NULL, -- 'QUESTIONNAIRE', 'NDT', 'VISUAL', 'EXPERTISE'
                    inspector_id UUID REFERENCES users(id),
                    inspection_date TIMESTAMP WITH TIME ZONE NOT NULL,
                    data JSONB NOT NULL DEFAULT '{}',
                    conclusion TEXT,
                    next_inspection_date DATE,
                    status VARCHAR(50) DEFAULT 'DRAFT', -- 'DRAFT', 'SIGNED', 'APPROVED'
                    report_path VARCHAR(500),
                    word_report_path VARCHAR(500),
                    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
                );
            """))
            
            await session.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_inspection_history_equipment 
                ON inspection_history(equipment_id);
            """))
            
            await session.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_inspection_history_date 
                ON inspection_history(inspection_date DESC);
            """))
            
            # 4. Создаем таблицу журнала ремонта
            await session.execute(text("""
                CREATE TABLE IF NOT EXISTS repair_journal (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    equipment_id UUID NOT NULL REFERENCES equipment(id) ON DELETE CASCADE,
                    repair_date TIMESTAMP WITH TIME ZONE NOT NULL,
                    repair_type VARCHAR(100) NOT NULL, -- 'MAINTENANCE', 'REPAIR', 'REPLACEMENT', 'MODIFICATION'
                    description TEXT NOT NULL,
                    performed_by UUID REFERENCES users(id),
                    cost NUMERIC(15, 2),
                    documents JSONB DEFAULT '[]', -- Массив путей к документам
                    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
                );
            """))
            
            await session.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_repair_journal_equipment 
                ON repair_journal(equipment_id);
            """))
            
            await session.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_repair_journal_date 
                ON repair_journal(repair_date DESC);
            """))
            
            # 5. Создаем функцию для автоматической генерации кода оборудования
            await session.execute(text("""
                CREATE OR REPLACE FUNCTION generate_equipment_code()
                RETURNS TRIGGER AS $$
                DECLARE
                    new_code VARCHAR(100);
                    code_exists BOOLEAN;
                BEGIN
                    -- Генерируем код на основе ID (первые 8 символов UUID)
                    new_code := 'EQ-' || UPPER(SUBSTRING(NEW.id::TEXT FROM 1 FOR 8));
                    
                    -- Проверяем уникальность
                    SELECT EXISTS(SELECT 1 FROM equipment WHERE equipment_code = new_code) INTO code_exists;
                    
                    -- Если код существует, добавляем суффикс
                    IF code_exists THEN
                        new_code := new_code || '-' || EXTRACT(EPOCH FROM NOW())::BIGINT::TEXT;
                    END IF;
                    
                    NEW.equipment_code := new_code;
                    RETURN NEW;
                END;
                $$ LANGUAGE plpgsql;
            """))
            
            # Удаляем триггер, если существует
            await session.execute(text("""
                DROP TRIGGER IF EXISTS trg_generate_equipment_code ON equipment;
            """))
            
            # Создаем триггер для автоматической генерации кода
            await session.execute(text("""
                CREATE TRIGGER trg_generate_equipment_code
                BEFORE INSERT ON equipment
                FOR EACH ROW
                WHEN (NEW.equipment_code IS NULL)
                EXECUTE FUNCTION generate_equipment_code();
            """))
            
            # 6. Обновляем существующие записи оборудования, добавляя коды
            await session.execute(text("""
                UPDATE equipment 
                SET equipment_code = 'EQ-' || UPPER(SUBSTRING(id::TEXT FROM 1 FOR 8)) || '-' || EXTRACT(EPOCH FROM created_at)::BIGINT::TEXT
                WHERE equipment_code IS NULL;
            """))
            
            await session.commit()
            print("[OK] Единая система оборудования успешно создана!")
            print("   - Добавлено поле equipment_code в таблицу equipment")
            print("   - Создана таблица assignments (задания)")
            print("   - Создана таблица inspection_history (история обследований)")
            print("   - Создана таблица repair_journal (журнал ремонта)")
            print("   - Созданы индексы для оптимизации запросов")
            print("   - Создан триггер для автоматической генерации кодов оборудования")
            
        except Exception as e:
            await session.rollback()
            print(f"[ERROR] Ошибка при создании структуры: {e}")
            import traceback
            traceback.print_exc()
            raise

if __name__ == "__main__":
    asyncio.run(create_unified_equipment_system())

