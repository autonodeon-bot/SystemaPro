"""
Скрипт для проверки подключения к базе данных и создания тестовых данных
"""
import asyncio
import os
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy import text, inspect
from sqlalchemy.orm import declarative_base
import ssl

# Database configuration
DB_USER = os.getenv("DB_USER", "gen_user")
DB_PASS = os.getenv("DB_PASS", "")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "default_db")
DB_SSLMODE = os.getenv("DB_SSLMODE", "require")
DB_SSLCERT = os.getenv("DB_SSLCERT", "/app/certs/root.crt")

# Construct database URL
DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# SSL configuration
def get_ssl_context():
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE
    return ssl_context

connect_args = {"ssl": get_ssl_context()}

engine = create_async_engine(
    DATABASE_URL,
    echo=True,
    connect_args=connect_args
)

AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

async def check_connection():
    """Проверка подключения к базе данных"""
    print("🔍 Проверка подключения к базе данных...")
    try:
        async with engine.begin() as conn:
            result = await conn.execute(text("SELECT version()"))
            version = result.scalar()
            print(f"✅ Подключение успешно!")
            print(f"   PostgreSQL версия: {version[:50]}...")
            return True
    except Exception as e:
        print(f"❌ Ошибка подключения: {e}")
        return False

async def check_tables():
    """Проверка наличия таблиц"""
    print("\n🔍 Проверка таблиц в базе данных...")
    try:
        async with engine.begin() as conn:
            result = await conn.execute(text("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public'
                ORDER BY table_name;
            """))
            tables = [row[0] for row in result.fetchall()]
            if tables:
                print(f"✅ Найдено таблиц: {len(tables)}")
                for table in tables:
                    print(f"   - {table}")
            else:
                print("⚠️  Таблицы не найдены. База данных пустая.")
            return tables
    except Exception as e:
        print(f"❌ Ошибка проверки таблиц: {e}")
        return []

async def check_equipment_table():
    """Проверка таблицы equipment"""
    print("\n🔍 Проверка таблицы equipment...")
    try:
        async with AsyncSessionLocal() as session:
            # Проверяем существование таблицы
            result = await session.execute(text("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    AND table_name = 'equipment'
                );
            """))
            exists = result.scalar()
            
            if not exists:
                print("❌ Таблица 'equipment' не существует!")
                return False
            
            # Проверяем количество записей
            result = await session.execute(text("SELECT COUNT(*) FROM equipment"))
            count = result.scalar()
            print(f"✅ Таблица 'equipment' существует")
            print(f"   Количество записей: {count}")
            return True, count
    except Exception as e:
        print(f"❌ Ошибка проверки таблицы equipment: {e}")
        return False, 0

async def create_tables():
    """Создание таблиц из models.py"""
    print("\n🔧 Создание таблиц...")
    try:
        from models import Base, Equipment, EquipmentType, PipelineSegment, Inspection
        
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        print("✅ Таблицы созданы успешно!")
        return True
    except Exception as e:
        print(f"❌ Ошибка создания таблиц: {e}")
        import traceback
        traceback.print_exc()
        return False

async def add_test_data():
    """Добавление тестовых данных"""
    print("\n🔧 Добавление тестовых данных...")
    try:
        from models import Equipment, EquipmentType
        import uuid
        
        async with AsyncSessionLocal() as session:
            # Проверяем, есть ли уже данные
            result = await session.execute(text("SELECT COUNT(*) FROM equipment"))
            count = result.scalar()
            
            if count > 0:
                print(f"⚠️  В таблице уже есть {count} записей. Пропускаем добавление.")
                return True
            
            # Создаем тестовый тип оборудования
            type_id = uuid.uuid4()
            equipment_type = EquipmentType(
                id=type_id,
                name="Сосуд под давлением",
                description="Сосуд для работы под давлением",
                code="VESSEL"
            )
            session.add(equipment_type)
            await session.flush()
            
            # Создаем тестовое оборудование
            test_equipment = Equipment(
                id=uuid.uuid4(),
                name="Сосуд В-101",
                type_id=type_id,
                serial_number="SN-001",
                attributes={"pressure": "1.6 МПа", "volume": "10 м³"}
            )
            session.add(test_equipment)
            
            # Добавляем еще несколько тестовых записей
            for i in range(2, 6):
                eq = Equipment(
                    id=uuid.uuid4(),
                    name=f"Сосуд В-10{i}",
                    type_id=type_id,
                    serial_number=f"SN-00{i}",
                    attributes={"pressure": f"{1.0 + i*0.1} МПа", "volume": f"{10 + i*5} м³"}
                )
                session.add(eq)
            
            await session.commit()
            print("✅ Тестовые данные добавлены успешно!")
            print("   Создано 5 единиц оборудования")
            return True
    except Exception as e:
        print(f"❌ Ошибка добавления тестовых данных: {e}")
        import traceback
        traceback.print_exc()
        return False

async def main():
    """Основная функция"""
    print("=" * 60)
    print("  ДИАГНОСТИКА БАЗЫ ДАННЫХ")
    print("=" * 60)
    print(f"\nПараметры подключения:")
    print(f"  Host: {DB_HOST}")
    print(f"  Port: {DB_PORT}")
    print(f"  Database: {DB_NAME}")
    print(f"  User: {DB_USER}")
    print(f"  SSL Mode: {DB_SSLMODE}")
    print()
    
    # 1. Проверка подключения
    if not await check_connection():
        print("\n❌ Не удалось подключиться к базе данных!")
        return
    
    # 2. Проверка таблиц
    tables = await check_tables()
    
    # 3. Проверка таблицы equipment
    if 'equipment' in tables:
        result = await check_equipment_table()
        if isinstance(result, tuple):
            exists, count = result
        else:
            exists = result
            count = 0
        if exists and count == 0:
            print("\n⚠️  Таблица equipment пустая. Добавляем тестовые данные...")
            await add_test_data()
    else:
        print("\n⚠️  Таблица equipment не найдена. Создаем таблицы...")
        if await create_tables():
            await add_test_data()
    
    print("\n" + "=" * 60)
    print("  ДИАГНОСТИКА ЗАВЕРШЕНА")
    print("=" * 60)

if __name__ == "__main__":
    asyncio.run(main())

