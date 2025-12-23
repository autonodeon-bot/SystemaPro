"""
Скрипт для добавления недостающих колонок в таблицу reports.

Проблема: backend ожидает поля word_file_path / word_file_size,
но в БД их может не быть, из-за чего генерация PDF/DOCX отчетов падает.
"""

import asyncio
from sqlalchemy import text
from database import engine


async def fix_reports_table_columns():
    """Добавить недостающие колонки в таблицу reports"""
    async with engine.begin() as conn:
        try:
            result = await conn.execute(
                text(
                    """
                    SELECT column_name
                    FROM information_schema.columns
                    WHERE table_name = 'reports';
                    """
                )
            )
            existing_columns = {row[0] for row in result.fetchall()}
            print(f"Существующие колонки reports: {existing_columns}")

            columns_to_add = {
                # Word-версии отчетов
                "word_file_path": "VARCHAR(500)",
                "word_file_size": "INTEGER DEFAULT 0",
                # Автор генерации (совместимость с текущей моделью)
                "created_by": "UUID NULL",
            }

            for column_name, column_type in columns_to_add.items():
                if column_name not in existing_columns:
                    print(f"Добавляем колонку {column_name}...")
                    await conn.execute(
                        text(
                            f"""
                            ALTER TABLE reports
                            ADD COLUMN {column_name} {column_type};
                            """
                        )
                    )
                    print(f"✅ Колонка {column_name} успешно добавлена!")
                else:
                    print(f"⚠️  Колонка {column_name} уже существует. Пропускаем.")

            print("✅ Таблица reports проверена/обновлена.")
        except Exception as e:
            print(f"❌ Ошибка при добавлении колонок reports: {e}")
            import traceback

            traceback.print_exc()
            raise


if __name__ == "__main__":
    asyncio.run(fix_reports_table_columns())


