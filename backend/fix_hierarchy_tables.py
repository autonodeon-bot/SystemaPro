"""
Скрипт для исправления структуры таблиц иерархии
"""
import asyncio
from sqlalchemy import text
from database import engine

async def fix_hierarchy_tables():
    """Исправить структуру таблиц иерархии"""
    try:
        async with engine.begin() as conn:
            # Проверяем и добавляем колонки в branches
            result = await conn.execute(text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'branches';
            """))
            branch_columns = [row[0] for row in result.all()]
            
            # Делаем client_id nullable, если он обязательный
            if 'client_id' in branch_columns:
                result = await conn.execute(text("""
                    SELECT is_nullable 
                    FROM information_schema.columns 
                    WHERE table_name = 'branches' 
                    AND column_name = 'client_id';
                """))
                is_nullable = result.scalar()
                if is_nullable == 'NO':
                    print("⚠️  Делаем client_id nullable в branches...")
                    await conn.execute(text("""
                        ALTER TABLE branches 
                        ALTER COLUMN client_id DROP NOT NULL;
                    """))
                    print("✅ client_id теперь nullable в branches!")
            
            if 'enterprise_id' not in branch_columns:
                print("⚠️  Добавляем колонку enterprise_id в branches...")
                await conn.execute(text("""
                    ALTER TABLE branches 
                    ADD COLUMN enterprise_id UUID REFERENCES enterprises(id);
                """))
                await conn.execute(text("""
                    CREATE INDEX IF NOT EXISTS idx_branches_enterprise_id ON branches(enterprise_id);
                """))
                print("✅ Колонка enterprise_id добавлена в branches!")
            
            # Проверяем и добавляем колонки в workshops
            result = await conn.execute(text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'workshops';
            """))
            workshop_columns = [row[0] for row in result.all()]
            
            if 'branch_id' not in workshop_columns:
                print("⚠️  Добавляем колонку branch_id в workshops...")
                await conn.execute(text("""
                    ALTER TABLE workshops 
                    ADD COLUMN branch_id UUID REFERENCES branches(id);
                """))
                await conn.execute(text("""
                    CREATE INDEX IF NOT EXISTS idx_workshops_branch_id ON workshops(branch_id);
                """))
                print("✅ Колонка branch_id добавлена в workshops!")
            
            # Проверяем и добавляем колонку workshop_id в equipment
            result = await conn.execute(text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'equipment' 
                AND column_name = 'workshop_id';
            """))
            column_exists = result.scalar()
            
            if not column_exists:
                print("⚠️  Добавляем колонку workshop_id в equipment...")
                await conn.execute(text("""
                    ALTER TABLE equipment 
                    ADD COLUMN workshop_id UUID REFERENCES workshops(id);
                """))
                await conn.execute(text("""
                    CREATE INDEX IF NOT EXISTS idx_equipment_workshop_id ON equipment(workshop_id);
                """))
                print("✅ Колонка workshop_id добавлена в equipment!")
            else:
                print("✅ Колонка workshop_id уже существует в equipment.")
            
            print("✅ Структура таблиц иерархии исправлена!")
                
    except Exception as e:
        print(f"❌ Ошибка при исправлении структуры таблиц: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(fix_hierarchy_tables())

