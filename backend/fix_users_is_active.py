"""
Скрипт для исправления типа колонки is_active в таблице users
"""
import asyncio
from sqlalchemy import text
from database import engine

async def fix_users_is_active():
    """Исправить тип колонки is_active в таблице users"""
    try:
        async with engine.begin() as conn:
            # Проверяем тип колонки is_active
            result = await conn.execute(text("""
                SELECT data_type 
                FROM information_schema.columns 
                WHERE table_name = 'users' 
                AND column_name = 'is_active';
            """))
            data_type = result.scalar()
            
            print(f"Текущий тип колонки is_active: {data_type}")
            
            if data_type == 'boolean':
                print("⚠️  Колонка is_active имеет тип BOOLEAN, конвертируем в INTEGER...")
                # Конвертируем boolean в integer
                await conn.execute(text("""
                    ALTER TABLE users 
                    ALTER COLUMN is_active TYPE INTEGER 
                    USING CASE WHEN is_active THEN 1 ELSE 0 END;
                """))
                print("✅ Колонка is_active успешно конвертирована в INTEGER!")
            elif data_type == 'integer':
                print("✅ Колонка is_active уже имеет тип INTEGER.")
            else:
                print(f"⚠️  Неожиданный тип колонки: {data_type}")
                
    except Exception as e:
        print(f"❌ Ошибка при исправлении типа колонки: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(fix_users_is_active())












