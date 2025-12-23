"""
Скрипт для добавления недостающих колонок в таблицу questionnaires
"""
import asyncio
from sqlalchemy import text
from database import engine

async def fix_questionnaires_table_columns():
    """Добавить недостающие колонки в таблицу questionnaires"""
    async with engine.begin() as conn:
        try:
            # Проверяем существующие колонки
            result = await conn.execute(
                text("""
                    SELECT column_name 
                    FROM information_schema.columns 
                    WHERE table_name = 'questionnaires';
                """)
            )
            existing_columns = {row[0] for row in result.fetchall()}
            
            print(f"Существующие колонки: {existing_columns}")
            
            # Добавляем недостающие колонки
            columns_to_add = {
                'file_path': 'VARCHAR(500)',
                'file_size': 'INTEGER DEFAULT 0',
                'word_file_path': 'VARCHAR(500)',
                'word_file_size': 'INTEGER DEFAULT 0',
            }
            
            for column_name, column_type in columns_to_add.items():
                if column_name not in existing_columns:
                    print(f"Добавляем колонку {column_name}...")
                    await conn.execute(
                        text(f"""
                            ALTER TABLE questionnaires 
                            ADD COLUMN {column_name} {column_type};
                        """)
                    )
                    print(f"✅ Колонка {column_name} успешно добавлена!")
                else:
                    print(f"⚠️  Колонка {column_name} уже существует. Пропускаем.")
            
            print("✅ Все колонки проверены и добавлены при необходимости!")
            
        except Exception as e:
            print(f"❌ Ошибка при добавлении колонок: {e}")
            import traceback
            traceback.print_exc()
            raise

if __name__ == "__main__":
    asyncio.run(fix_questionnaires_table_columns())











