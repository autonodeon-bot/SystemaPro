"""
Скрипт для создания таблицы users в базе данных
"""
import asyncio
from sqlalchemy import text
from database import engine, Base
from models import User

async def create_users_table():
    """Создать таблицу users"""
    try:
        async with engine.begin() as conn:
            # Проверяем, существует ли таблица
            result = await conn.execute(text("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    AND table_name = 'users'
                );
            """))
            exists = result.scalar()
            
            if exists:
                print("⚠️  Таблица users уже существует. Пропускаем создание.")
                return
            
            # Создаем таблицу
            await conn.run_sync(Base.metadata.create_all, tables=[User.__table__])
            print("✅ Таблица users успешно создана!")
            
            # Создаем индексы
            await conn.execute(text("""
                CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
                CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
                CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
            """))
            print("✅ Индексы для таблицы users созданы!")
            
    except Exception as e:
        print(f"❌ Ошибка при создании таблицы users: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(create_users_table())












