"""
Скрипт для исправления типа колонки is_active в таблице user_equipment_access
"""
import asyncio
from sqlalchemy import text
from database import engine

async def fix_is_active_column_type():
    """Исправить тип колонки is_active на INTEGER, если она BOOLEAN"""
    try:
        async with engine.begin() as conn:
            # Проверяем тип колонки
            result = await conn.execute(text("""
                SELECT data_type 
                FROM information_schema.columns 
                WHERE table_name = 'user_equipment_access' 
                AND column_name = 'is_active';
            """))
            column_type = result.scalar()
            
            if column_type == 'boolean':
                print("⚠️  Колонка is_active имеет тип BOOLEAN. Изменяем на INTEGER...")
                # Изменяем тип колонки на INTEGER
                await conn.execute(text("""
                    ALTER TABLE user_equipment_access 
                    ALTER COLUMN is_active TYPE INTEGER 
                    USING CASE WHEN is_active THEN 1 ELSE 0 END;
                """))
                print("✅ Тип колонки is_active успешно изменен на INTEGER!")
            elif column_type == 'integer':
                print("✅ Колонка is_active уже имеет тип INTEGER. Изменения не требуются.")
            else:
                print(f"⚠️  Неизвестный тип колонки: {column_type}")
                
    except Exception as e:
        print(f"❌ Ошибка при исправлении типа колонки: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(fix_is_active_column_type())












