"""
Скрипт для создания таблиц иерархии: enterprises, branches, workshops, hierarchy_engineer_assignments
"""
import asyncio
from sqlalchemy import text
from database import engine, Base
from models import Enterprise, Branch, Workshop, HierarchyEngineerAssignment

async def create_hierarchy_tables():
    """Создать таблицы иерархии"""
    try:
        async with engine.begin() as conn:
            # Проверяем и создаем таблицу enterprises
            result = await conn.execute(text("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    AND table_name = 'enterprises'
                );
            """))
            exists = result.scalar()
            
            if not exists:
                await conn.run_sync(Base.metadata.create_all, tables=[Enterprise.__table__])
                print("✅ Таблица enterprises создана!")
            else:
                print("⚠️  Таблица enterprises уже существует.")
            
            # Проверяем и создаем таблицу branches
            result = await conn.execute(text("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    AND table_name = 'branches'
                );
            """))
            exists = result.scalar()
            
            if not exists:
                await conn.run_sync(Base.metadata.create_all, tables=[Branch.__table__])
                print("✅ Таблица branches создана!")
            else:
                print("⚠️  Таблица branches уже существует.")
            
            # Проверяем и создаем таблицу workshops
            result = await conn.execute(text("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    AND table_name = 'workshops'
                );
            """))
            exists = result.scalar()
            
            if not exists:
                await conn.run_sync(Base.metadata.create_all, tables=[Workshop.__table__])
                print("✅ Таблица workshops создана!")
            else:
                print("⚠️  Таблица workshops уже существует.")
            
            # Проверяем и создаем таблицу hierarchy_engineer_assignments
            result = await conn.execute(text("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    AND table_name = 'hierarchy_engineer_assignments'
                );
            """))
            exists = result.scalar()
            
            if not exists:
                await conn.run_sync(Base.metadata.create_all, tables=[HierarchyEngineerAssignment.__table__])
                print("✅ Таблица hierarchy_engineer_assignments создана!")
            else:
                print("⚠️  Таблица hierarchy_engineer_assignments уже существует.")
            
            # Создаем индексы по одному
            indexes = [
                "CREATE INDEX IF NOT EXISTS idx_enterprises_code ON enterprises(code);",
                "CREATE INDEX IF NOT EXISTS idx_enterprises_is_active ON enterprises(is_active);",
                "CREATE INDEX IF NOT EXISTS idx_branches_enterprise_id ON branches(enterprise_id);",
                "CREATE INDEX IF NOT EXISTS idx_branches_code ON branches(code);",
                "CREATE INDEX IF NOT EXISTS idx_branches_is_active ON branches(is_active);",
                "CREATE INDEX IF NOT EXISTS idx_workshops_branch_id ON workshops(branch_id);",
                "CREATE INDEX IF NOT EXISTS idx_workshops_code ON workshops(code);",
                "CREATE INDEX IF NOT EXISTS idx_workshops_is_active ON workshops(is_active);",
                "CREATE INDEX IF NOT EXISTS idx_hierarchy_assignments_user_id ON hierarchy_engineer_assignments(user_id);",
                "CREATE INDEX IF NOT EXISTS idx_hierarchy_assignments_enterprise_id ON hierarchy_engineer_assignments(enterprise_id);",
                "CREATE INDEX IF NOT EXISTS idx_hierarchy_assignments_branch_id ON hierarchy_engineer_assignments(branch_id);",
                "CREATE INDEX IF NOT EXISTS idx_hierarchy_assignments_workshop_id ON hierarchy_engineer_assignments(workshop_id);",
                "CREATE INDEX IF NOT EXISTS idx_hierarchy_assignments_equipment_type_id ON hierarchy_engineer_assignments(equipment_type_id);",
                "CREATE INDEX IF NOT EXISTS idx_hierarchy_assignments_equipment_id ON hierarchy_engineer_assignments(equipment_id);",
                "CREATE INDEX IF NOT EXISTS idx_hierarchy_assignments_is_active ON hierarchy_engineer_assignments(is_active);",
            ]
            
            for index_sql in indexes:
                try:
                    await conn.execute(text(index_sql))
                except Exception as e:
                    print(f"⚠️  Предупреждение при создании индекса: {e}")
            
            print("✅ Индексы для таблиц иерархии созданы!")
            
            # Добавляем колонку workshop_id в equipment, если её нет
            result = await conn.execute(text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'equipment' 
                AND column_name = 'workshop_id';
            """))
            column_exists = result.scalar()
            
            if not column_exists:
                await conn.execute(text("""
                    ALTER TABLE equipment 
                    ADD COLUMN workshop_id UUID REFERENCES workshops(id);
                """))
                await conn.execute(text("""
                    CREATE INDEX IF NOT EXISTS idx_equipment_workshop_id ON equipment(workshop_id);
                """))
                print("✅ Колонка workshop_id добавлена в таблицу equipment!")
            else:
                print("⚠️  Колонка workshop_id уже существует в таблице equipment.")
                
    except Exception as e:
        print(f"❌ Ошибка при создании таблиц иерархии: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(create_hierarchy_tables())

