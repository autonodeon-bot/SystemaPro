"""
Скрипт для создания таблицы questionnaire_document_files в базе данных
"""
import asyncio
from sqlalchemy import text
from database import engine

async def create_questionnaire_document_files_table():
    """Создать таблицу questionnaire_document_files если её нет"""
    async with engine.begin() as conn:
        try:
            # Проверяем, существует ли таблица
            result = await conn.execute(
                text("""
                    SELECT EXISTS (
                        SELECT FROM information_schema.tables 
                        WHERE table_schema = 'public' 
                        AND table_name = 'questionnaire_document_files'
                    );
                """)
            )
            table_exists = result.scalar()
            
            if table_exists:
                print("⚠️  Таблица questionnaire_document_files уже существует. Пропускаем создание.")
                return
            
            # Создаем таблицу
            await conn.execute(text("""
                CREATE TABLE questionnaire_document_files (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    questionnaire_id UUID NOT NULL REFERENCES questionnaires(id) ON DELETE CASCADE,
                    document_number VARCHAR(10) NOT NULL,
                    file_name VARCHAR(255) NOT NULL,
                    file_path VARCHAR(500) NOT NULL,
                    file_size INTEGER NOT NULL,
                    file_type VARCHAR(50),
                    mime_type VARCHAR(100),
                    uploaded_by UUID REFERENCES users(id),
                    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                    updated_at TIMESTAMP WITH TIME ZONE
                );
            """))
            
            # Создаем индексы
            await conn.execute(text("""
                CREATE INDEX idx_questionnaire_document_files_questionnaire_id 
                ON questionnaire_document_files(questionnaire_id);
            """))
            
            await conn.execute(text("""
                CREATE INDEX idx_questionnaire_document_files_document_number 
                ON questionnaire_document_files(questionnaire_id, document_number);
            """))
            
            print("✅ Таблица questionnaire_document_files успешно создана!")
            
        except Exception as e:
            print(f"❌ Ошибка при создании таблицы: {e}")
            import traceback
            traceback.print_exc()
            raise

if __name__ == "__main__":
    asyncio.run(create_questionnaire_document_files_table())












