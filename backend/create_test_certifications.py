"""
Скрипт для создания тестовых данных с сертификатами и удостоверениями НК для сотрудников
"""
import asyncio
import sys
from datetime import datetime, date, timedelta
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
import uuid as uuid_lib
from database import get_db
from models import Engineer, Certification, User

# Настройка вывода для поддержки UTF-8
sys.stdout.reconfigure(encoding='utf-8')

# Типы сертификатов и удостоверений НК
CERTIFICATION_TYPES = [
    "Ультразвуковая дефектоскопия (УЗК)",
    "Радиографический контроль (РК)",
    "Магнитопорошковая дефектоскопия (МПД)",
    "Капиллярная дефектоскопия (ПВК)",
    "Визуальный и измерительный контроль (ВИК)",
    "Вихретоковый контроль (ВТК)",
    "Толщинометрия",
    "Акустико-эмиссионный контроль (АЭК)",
    "Тепловой контроль (ТК)",
    "Ультразвуковая толщинометрия (УЗТ)"
]

ISSUING_ORGANIZATIONS = [
    "Ростехнадзор",
    "Центр сертификации НК",
    "АНО \"Центр сертификации и экспертизы\"",
    "ООО \"Центр неразрушающего контроля\"",
    "АНО \"Центр сертификации персонала\"",
    "ФГУП \"Центр сертификации\""
]

async def create_test_certifications():
    """Создание тестовых сертификатов для существующих инженеров"""
    print("🔐 SSL Mode: require")
    print("✅ Using SSL without certificate verification (self-signed cert)")
    print("\n📋 Создание тестовых сертификатов и удостоверений НК...\n")
    
    async for db in get_db():
        try:
            # Получаем всех инженеров
            engineers_result = await db.execute(
                select(Engineer).where(Engineer.is_active == 1)
            )
            engineers = engineers_result.scalars().all()
            
            if not engineers:
                print("⚠️  Инженеры не найдены. Сначала создайте инженеров.")
                return
            
            print(f"✅ Найдено инженеров: {len(engineers)}\n")
            
            created_count = 0
            
            for engineer in engineers:
                # Создаем 2-4 сертификата для каждого инженера
                num_certs = 2 + (hash(engineer.id) % 3)  # От 2 до 4 сертификатов
                
                for i in range(num_certs):
                    # Выбираем случайный тип сертификата
                    cert_type = CERTIFICATION_TYPES[hash(f"{engineer.id}{i}") % len(CERTIFICATION_TYPES)]
                    
                    # Генерируем даты
                    issue_date = date.today() - timedelta(days=365 * (1 + hash(f"{engineer.id}{i}") % 3))
                    expiry_date = issue_date + timedelta(days=365 * (2 + hash(f"{engineer.id}{i}") % 2))
                    
                    # Проверяем, не истек ли уже сертификат
                    if expiry_date < date.today():
                        # Продлеваем на 1-2 года
                        expiry_date = date.today() + timedelta(days=30 * (6 + hash(f"{engineer.id}{i}") % 12))
                    
                    # Генерируем номер сертификата
                    cert_number = f"СЕРТ-{issue_date.year}-{str(hash(f'{engineer.id}{i}'))[-6:].replace('-', '')}"
                    
                    # Выбираем организацию
                    org = ISSUING_ORGANIZATIONS[hash(f"{engineer.id}{i}") % len(ISSUING_ORGANIZATIONS)]
                    
                    # Проверяем, не существует ли уже такой сертификат (используем только доступные поля)
                    from sqlalchemy import text
                    check_result = await db.execute(
                        text("SELECT id FROM certifications WHERE engineer_id = :eng_id AND certificate_number = :cert_num"),
                        {"eng_id": engineer.id, "cert_num": cert_number}
                    )
                    if check_result.scalar_one_or_none():
                        continue
                    
                    # Создаем сертификат
                    certification = Certification(
                        engineer_id=engineer.id,
                        certification_type=cert_type,
                        certificate_number=cert_number,
                        issue_date=issue_date,
                        expiry_date=expiry_date,
                        issuing_organization=org,
                        document_number=f"ДОК-{issue_date.year}-{str(hash(f'{engineer.id}{i}'))[-4:].replace('-', '')}",
                        document_date=issue_date,
                        is_active=1
                    )
                    
                    db.add(certification)
                    created_count += 1
                    
                    # Определяем статус
                    days_until_expiry = (expiry_date - date.today()).days
                    if days_until_expiry < 0:
                        status = "❌ Истек"
                    elif days_until_expiry <= 90:
                        status = "⚠️  Истекает скоро"
                    else:
                        status = "✅ Действителен"
                    
                    print(f"  ✓ {engineer.full_name}: {cert_type}")
                    print(f"    Номер: {cert_number}, Действует до: {expiry_date.strftime('%d.%m.%Y')} ({status})")
            
            await db.commit()
            print(f"\n✅ Успешно создано сертификатов: {created_count}")
            
            # Статистика
            all_certs_result = await db.execute(
                select(Certification).where(Certification.is_active == 1)
            )
            all_certs = all_certs_result.scalars().all()
            
            expired = sum(1 for c in all_certs if c.expiry_date and c.expiry_date < date.today())
            expiring_soon = sum(1 for c in all_certs if c.expiry_date and 0 < (c.expiry_date - date.today()).days <= 90)
            valid = sum(1 for c in all_certs if c.expiry_date and (c.expiry_date - date.today()).days > 90)
            
            print(f"\n📊 Статистика сертификатов:")
            print(f"  ✅ Действительных: {valid}")
            print(f"  ⚠️  Истекающих скоро (≤90 дней): {expiring_soon}")
            print(f"  ❌ Истекших: {expired}")
            print(f"  📋 Всего: {len(all_certs)}")
            
            break
            
        except Exception as e:
            await db.rollback()
            print(f"❌ Ошибка при создании сертификатов: {e}")
            import traceback
            traceback.print_exc()
            break

if __name__ == "__main__":
    asyncio.run(create_test_certifications())

