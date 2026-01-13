"""
Скрипт для создания 20 тестовых поверок на разное оборудование
Использует прямое подключение к базе данных
"""
import sys
import os
from datetime import date, timedelta
import random
import uuid

# Добавляем путь к модулям
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from database import get_db
from models import VerificationEquipment
from sqlalchemy.ext.asyncio import AsyncSession
import asyncio

# Типы оборудования для НК
EQUIPMENT_TYPES = ["ВИК", "УЗК", "ПВК", "РК", "МК", "УЗК_СС", "ТК", "АК"]

# Производители
MANUFACTURERS = [
    "ООО 'НПО Спецтехника'",
    "ЗАО 'Ультразвуковые технологии'",
    "ООО 'Контроль-Прибор'",
    "АО 'НПК Энергомаш'",
    "ООО 'ТехноКонтроль'",
    "ЗАО 'Неразрушающий контроль'",
    "ООО 'ПромКонтроль'",
    "АО 'Спецприбор'"
]

# Модели по типам
MODELS_BY_TYPE = {
    "ВИК": ["ВИК-2020", "ВИК-Про", "ВИК-М", "ВИК-Стандарт", "ВИК-Эксперт"],
    "УЗК": ["УТ-93", "УТ-2000", "УЗК-М", "УЗК-Про", "УЗК-Эксперт"],
    "ПВК": ["ПВК-100", "ПВК-200", "ПВК-Про", "ПВК-М", "ПВК-Эксперт"],
    "РК": ["РК-50", "РК-100", "РК-Про", "РК-М", "РК-Эксперт"],
    "МК": ["МК-10", "МК-20", "МК-Про", "МК-М", "МК-Эксперт"],
    "УЗК_СС": ["УЗК-СС-100", "УЗК-СС-200", "УЗК-СС-Про"],
    "ТК": ["ТК-50", "ТК-100", "ТК-Про"],
    "АК": ["АК-10", "АК-20", "АК-Про"]
}

# Организации поверки
VERIFICATION_ORGS = [
    "ФБУ 'Ростест-Москва'",
    "ФБУ 'Ростест-СПб'",
    "ООО 'Центр поверки'",
    "АО 'Поверка-Сервис'",
    "ООО 'ТехПоверка'",
    "ФБУ 'Ростест-Екатеринбург'"
]

def generate_test_verification(index):
    """Генерировать данные для тестовой поверки"""
    equipment_type = random.choice(EQUIPMENT_TYPES)
    manufacturer = random.choice(MANUFACTURERS)
    model = random.choice(MODELS_BY_TYPE.get(equipment_type, ["Модель-1"]))
    
    # Генерируем даты
    # Дата последней поверки - от 6 месяцев до 1 года назад
    days_ago = random.randint(180, 365)
    verification_date = date.today() - timedelta(days=days_ago)
    
    # Следующая поверка - от 1 месяца до 1 года в будущем
    days_ahead = random.randint(30, 365)
    next_verification_date = date.today() + timedelta(days=days_ahead)
    
    # Серийный номер
    serial_number = f"SN-{equipment_type}-{random.randint(1000, 9999)}-{index:03d}"
    
    # Инвентарный номер
    inventory_number = f"ИНВ-{random.randint(10000, 99999)}"
    
    # Номер свидетельства
    cert_number = f"СВ-{random.randint(2023, 2024)}-{random.randint(1000, 9999)}"
    
    # Название
    name = f"{equipment_type} {model} №{serial_number}"
    
    return {
        "name": name,
        "equipment_type": equipment_type,
        "serial_number": serial_number,
        "manufacturer": manufacturer,
        "model": model,
        "inventory_number": inventory_number,
        "verification_date": verification_date,
        "next_verification_date": next_verification_date,
        "verification_certificate_number": cert_number,
        "verification_organization": random.choice(VERIFICATION_ORGS),
        "category": f"Категория {equipment_type}",
        "notes": f"Тестовая поверка #{index}. Оборудование для неразрушающего контроля."
    }

async def create_verification_in_db(db: AsyncSession, verification_data):
    """Создать поверку в базе данных"""
    new_equipment = VerificationEquipment(
        id=uuid.uuid4(),
        name=verification_data["name"],
        equipment_type=verification_data["equipment_type"],
        category=verification_data["category"],
        serial_number=verification_data["serial_number"],
        manufacturer=verification_data["manufacturer"],
        model=verification_data["model"],
        inventory_number=verification_data["inventory_number"],
        verification_date=verification_data["verification_date"],
        next_verification_date=verification_data["next_verification_date"],
        verification_certificate_number=verification_data["verification_certificate_number"],
        verification_organization=verification_data["verification_organization"],
        notes=verification_data["notes"],
        is_active=1
    )
    
    db.add(new_equipment)
    await db.commit()
    await db.refresh(new_equipment)
    
    return new_equipment

async def main():
    """Основная функция"""
    print("Начинаем создание 20 тестовых поверок...")
    
    created_count = 0
    failed_count = 0
    
    async for db in get_db():
        for i in range(1, 21):
            try:
                verification_data = generate_test_verification(i)
                print(f"\nСоздаем поверку #{i}: {verification_data['name']}")
                result = await create_verification_in_db(db, verification_data)
                created_count += 1
                print(f"Поверка #{i} создана успешно (ID: {result.id})")
            except Exception as e:
                failed_count += 1
                print(f"Ошибка при создании поверки #{i}: {e}")
                import traceback
                traceback.print_exc()
        break  # Используем только первую итерацию генератора
    
    print(f"\n{'='*60}")
    print(f"Итоги:")
    print(f"Успешно создано: {created_count}")
    print(f"Ошибок: {failed_count}")
    print(f"{'='*60}")

if __name__ == "__main__":
    asyncio.run(main())



