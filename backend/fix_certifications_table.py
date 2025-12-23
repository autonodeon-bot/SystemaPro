"""
Миграция для исправления структуры таблицы certifications
"""
import asyncio
import sys
from sqlalchemy import text
from database import get_db

sys.stdout.reconfigure(encoding='utf-8')

async def fix_certifications_table():
    """Добавить недостающие колонки в таблицу certifications"""
    print("🔐 SSL Mode: require")
    print("✅ Using SSL without certificate verification (self-signed cert)")
    print("\n📋 Исправление структуры таблицы certifications...\n")
    
    async for db in get_db():
        try:
            # Сначала добавляем updated_at (если его нет) - выполняем в отдельной транзакции
            print("Добавляем колонку updated_at...")
            try:
                await db.execute(text("ALTER TABLE certifications ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE"))
                await db.commit()
                print("✅ Колонка updated_at добавлена")
            except Exception as e:
                await db.rollback()
                error_str = str(e).lower()
                if 'already exists' in error_str or 'duplicate' in error_str or ('column' in error_str and 'already' in error_str):
                    print("ℹ️  Колонка updated_at уже существует")
                else:
                    print(f"⚠️  Предупреждение при добавлении updated_at: {e}")
            
            # Проверяем существующие колонки
            result = await db.execute(text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name = 'certifications' 
                ORDER BY ordinal_position
            """))
            existing_columns = [row[0] for row in result.all()]
            print(f"Существующие колонки: {', '.join(existing_columns)}\n")
            
            # Добавляем недостающие колонки
            if 'certificate_number' not in existing_columns:
                print("Добавляем колонку certificate_number...")
                await db.execute(text("""
                    ALTER TABLE certifications 
                    ADD COLUMN certificate_number VARCHAR(100);
                """))
                print("✅ Колонка certificate_number добавлена")
            
            if 'issuing_organization' not in existing_columns:
                print("Добавляем колонку issuing_organization...")
                await db.execute(text("""
                    ALTER TABLE certifications 
                    ADD COLUMN issuing_organization VARCHAR(255);
                """))
                print("✅ Колонка issuing_organization добавлена")
            
            if 'document_number' not in existing_columns:
                print("Добавляем колонку document_number...")
                await db.execute(text("""
                    ALTER TABLE certifications 
                    ADD COLUMN document_number VARCHAR(100);
                """))
                print("✅ Колонка document_number добавлена")
            
            if 'document_date' not in existing_columns:
                print("Добавляем колонку document_date...")
                await db.execute(text("""
                    ALTER TABLE certifications 
                    ADD COLUMN document_date DATE;
                """))
                print("✅ Колонка document_date добавлена")
            
            # Если есть старые колонки number и issued_by, копируем данные
            if 'number' in existing_columns and 'certificate_number' in existing_columns:
                print("Копируем данные из number в certificate_number...")
                await db.execute(text("""
                    UPDATE certifications 
                    SET certificate_number = number 
                    WHERE certificate_number IS NULL AND number IS NOT NULL;
                """))
                print("✅ Данные скопированы")
            
            if 'issued_by' in existing_columns and 'issuing_organization' in existing_columns:
                print("Копируем данные из issued_by в issuing_organization...")
                await db.execute(text("""
                    UPDATE certifications 
                    SET issuing_organization = issued_by 
                    WHERE issuing_organization IS NULL AND issued_by IS NOT NULL;
                """))
                print("✅ Данные скопированы")
            
            await db.commit()
            print("\n✅ Структура таблицы certifications успешно обновлена!")
            
            break
            
        except Exception as e:
            await db.rollback()
            print(f"❌ Ошибка при исправлении таблицы: {e}")
            import traceback
            traceback.print_exc()
            break

if __name__ == "__main__":
    asyncio.run(fix_certifications_table())

