"""
Скрипт для запуска миграции на версию 3.3.0
Выполняет создание новой структуры базы данных
"""

import asyncio
import sys
from create_unified_equipment_system import create_unified_equipment_system

if __name__ == "__main__":
    print("=" * 60)
    print("Миграция на версию 3.3.0 - Единая система оборудования")
    print("=" * 60)
    print()
    
    try:
        asyncio.run(create_unified_equipment_system())
        print()
        print("[OK] Миграция успешно завершена!")
        print("   Версия системы: 3.3.0")
        print()
        print("Следующие шаги:")
        print("1. Перезапустите backend сервер")
        print("2. Обновите frontend до версии 3.3.0")
        print("3. Обновите mobile приложение до версии 3.3.0")
        sys.exit(0)
    except Exception as e:
        print()
        print(f"[ERROR] Ошибка при выполнении миграции: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

