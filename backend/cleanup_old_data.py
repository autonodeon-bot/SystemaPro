"""
Скрипт для очистки старых отчетов, генераций и заданий инженеров
"""
import asyncio
import os
from pathlib import Path
from sqlalchemy import text, delete
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from database import DATABASE_URL, get_ssl_context

async def cleanup_old_data():
    """Очистить все старые отчеты, генерации и задания"""
    
    # Подключение к БД
    connect_args = {"ssl": get_ssl_context()}
    engine = create_async_engine(DATABASE_URL, echo=True, connect_args=connect_args)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as db:
        try:
            print("=" * 60)
            print("ОЧИСТКА СТАРЫХ ДАННЫХ")
            print("=" * 60)
            
            # 1. Удаляем все отчеты
            print("\n[1] Удаление всех отчетов из таблицы reports...")
            result = await db.execute(text("DELETE FROM reports"))
            deleted_reports = result.rowcount
            print(f"   ✓ Удалено отчетов: {deleted_reports}")
            
            # 2. Удаляем физические файлы отчетов
            print("\n[2] Удаление физических файлов отчетов...")
            reports_dir = Path("/app/reports")
            deleted_files = 0
            if reports_dir.exists():
                for file_path in reports_dir.rglob("*"):
                    if file_path.is_file() and file_path.suffix in ['.pdf', '.docx', '.doc']:
                        try:
                            file_path.unlink()
                            deleted_files += 1
                        except Exception as e:
                            print(f"   ⚠️  Не удалось удалить {file_path}: {e}")
            print(f"   ✓ Удалено файлов: {deleted_files}")
            
            # 3. Удаляем связи inspection_equipment
            print("\n[3] Удаление связей обследований с оборудованием для поверок...")
            result = await db.execute(text("DELETE FROM inspection_equipment"))
            deleted_links = result.rowcount
            print(f"   ✓ Удалено связей: {deleted_links}")
            
            # 4. Удаляем историю обследований
            print("\n[4] Удаление истории обследований...")
            result = await db.execute(text("DELETE FROM inspection_history"))
            deleted_history = result.rowcount
            print(f"   ✓ Удалено записей истории: {deleted_history}")
            
            # 5. Удаляем все обследования (inspections)
            print("\n[5] Удаление всех обследований (inspections)...")
            result = await db.execute(text("DELETE FROM inspections"))
            deleted_inspections = result.rowcount
            print(f"   ✓ Удалено обследований: {deleted_inspections}")
            
            # 6. Удаляем опросные листы (questionnaires)
            print("\n[6] Удаление опросных листов (questionnaires)...")
            result = await db.execute(text("DELETE FROM questionnaires"))
            deleted_questionnaires = result.rowcount
            print(f"   ✓ Удалено опросных листов: {deleted_questionnaires}")
            
            # 7. Удаляем файлы документов опросных листов
            print("\n[7] Удаление файлов документов опросных листов...")
            documents_dir = Path("/app/uploads/questionnaire_documents")
            deleted_doc_files = 0
            if documents_dir.exists():
                for dir_path in documents_dir.iterdir():
                    if dir_path.is_dir():
                        try:
                            import shutil
                            shutil.rmtree(dir_path)
                            deleted_doc_files += 1
                        except Exception as e:
                            print(f"   ⚠️  Не удалось удалить {dir_path}: {e}")
            print(f"   ✓ Удалено директорий с документами: {deleted_doc_files}")
            
            # 8. Удаляем все задания (assignments)
            print("\n[8] Удаление всех заданий (assignments)...")
            result = await db.execute(text("DELETE FROM assignments"))
            deleted_assignments = result.rowcount
            print(f"   ✓ Удалено заданий: {deleted_assignments}")
            
            # 9. Очищаем данные опросников ОПО (но не удаляем сами ОПО)
            print("\n[9] Очистка данных опросников ОПО...")
            result = await db.execute(text("UPDATE opos SET survey_data = NULL"))
            updated_opos = result.rowcount
            print(f"   ✓ Очищено ОПО: {updated_opos}")
            
            # Коммитим все изменения
            await db.commit()
            
            print("\n" + "=" * 60)
            print("ОЧИСТКА ЗАВЕРШЕНА УСПЕШНО!")
            print("=" * 60)
            print(f"\nИтого удалено:")
            print(f"  - Отчетов: {deleted_reports}")
            print(f"  - Файлов отчетов: {deleted_files}")
            print(f"  - Связей с оборудованием: {deleted_links}")
            print(f"  - Записей истории: {deleted_history}")
            print(f"  - Обследований: {deleted_inspections}")
            print(f"  - Опросных листов: {deleted_questionnaires}")
            print(f"  - Директорий с документами: {deleted_doc_files}")
            print(f"  - Заданий: {deleted_assignments}")
            print(f"  - Очищено ОПО: {updated_opos}")
            print("\nТеперь инженеры могут заново создать задания и заполнить чек-листы.")
            
        except Exception as e:
            await db.rollback()
            print(f"\n❌ ОШИБКА: {e}")
            import traceback
            traceback.print_exc()
            raise
    
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(cleanup_old_data())
