"""
Скрипт для добавления примерных специалистов неразрушающего контроля
"""
import asyncio
import uuid
from datetime import datetime, date, timedelta
from sqlalchemy.ext.asyncio import AsyncSession
from database import AsyncSessionLocal
from models import Engineer, Certification

async def init_specialists():
    """Добавление примерных специалистов НК с сертификатами"""
    async with AsyncSessionLocal() as session:
        try:
            print("=" * 60)
            print("Добавление специалистов неразрушающего контроля")
            print("=" * 60)
            
            # Список специалистов для добавления
            specialists_data = [
                {
                    "full_name": "Петров Иван Сергеевич",
                    "position": "Ведущий специалист по неразрушающему контролю",
                    "email": "petrov.ivan@nk-company.ru",
                    "phone": "+7 (495) 123-45-67",
                    "qualifications": {
                        "УЗК": "Эксперт",
                        "РК": "Специалист II уровня",
                        "ВИК": "Специалист III уровня"
                    },
                    "equipment_types": ["VESSEL", "PIPELINE", "CRANE"],
                    "certifications": [
                        {
                            "certification_type": "Допуск к ультразвуковому контролю",
                            "method": "УЗК",
                            "level": "III",
                            "number": "УЗК-2023-001",
                            "issued_by": "Ростехнадзор",
                            "issue_date": date(2023, 1, 15),
                            "expiry_date": date(2026, 1, 15)
                        },
                        {
                            "certification_type": "Допуск к радиографическому контролю",
                            "method": "РК",
                            "level": "II",
                            "number": "РК-2022-045",
                            "issued_by": "Центр сертификации НК",
                            "issue_date": date(2022, 6, 10),
                            "expiry_date": date(2025, 6, 10)
                        }
                    ]
                },
                {
                    "full_name": "Сидорова Елена Викторовна",
                    "position": "Специалист по визуальному и измерительному контролю",
                    "email": "sidorova.elena@nk-company.ru",
                    "phone": "+7 (495) 234-56-78",
                    "qualifications": {
                        "ВИК": "Специалист III уровня",
                        "ПВК": "Специалист II уровня"
                    },
                    "equipment_types": ["VESSEL", "TRANSFORMER"],
                    "certifications": [
                        {
                            "certification_type": "Допуск к визуальному и измерительному контролю",
                            "method": "ВИК",
                            "level": "III",
                            "number": "ВИК-2024-012",
                            "issued_by": "Ростехнадзор",
                            "issue_date": date(2024, 3, 20),
                            "expiry_date": date(2027, 3, 20)
                        },
                        {
                            "certification_type": "Допуск к пневматическому контролю",
                            "method": "ПВК",
                            "level": "II",
                            "number": "ПВК-2023-078",
                            "issued_by": "Центр сертификации НК",
                            "issue_date": date(2023, 9, 5),
                            "expiry_date": date(2026, 9, 5)
                        }
                    ]
                },
                {
                    "full_name": "Кузнецов Дмитрий Александрович",
                    "position": "Инженер по магнитному и пенетрантному контролю",
                    "email": "kuznetsov.dmitry@nk-company.ru",
                    "phone": "+7 (495) 345-67-89",
                    "qualifications": {
                        "МК": "Специалист II уровня",
                        "ПК": "Специалист II уровня",
                        "ВИК": "Специалист I уровня"
                    },
                    "equipment_types": ["PIPELINE", "CRANE"],
                    "certifications": [
                        {
                            "certification_type": "Допуск к магнитному контролю",
                            "method": "МК",
                            "level": "II",
                            "number": "МК-2023-156",
                            "issued_by": "Ростехнадзор",
                            "issue_date": date(2023, 5, 12),
                            "expiry_date": date(2026, 5, 12)
                        },
                        {
                            "certification_type": "Допуск к пенетрантному контролю",
                            "method": "ПК",
                            "level": "II",
                            "number": "ПК-2024-023",
                            "issued_by": "Центр сертификации НК",
                            "issue_date": date(2024, 2, 8),
                            "expiry_date": date(2027, 2, 8)
                        }
                    ]
                },
                {
                    "full_name": "Волкова Анна Петровна",
                    "position": "Специалист по тепловому контролю",
                    "email": "volkova.anna@nk-company.ru",
                    "phone": "+7 (495) 456-78-90",
                    "qualifications": {
                        "ТК": "Специалист III уровня",
                        "АК": "Специалист II уровня"
                    },
                    "equipment_types": ["TRANSFORMER", "VESSEL"],
                    "certifications": [
                        {
                            "certification_type": "Допуск к тепловому контролю",
                            "method": "ТК",
                            "level": "III",
                            "number": "ТК-2022-089",
                            "issued_by": "Ростехнадзор",
                            "issue_date": date(2022, 11, 20),
                            "expiry_date": date(2025, 11, 20)  # Истекает скоро!
                        },
                        {
                            "certification_type": "Допуск к акустико-эмиссионному контролю",
                            "method": "АК",
                            "level": "II",
                            "number": "АК-2023-034",
                            "issued_by": "Центр сертификации НК",
                            "issue_date": date(2023, 7, 15),
                            "expiry_date": date(2026, 7, 15)
                        }
                    ]
                },
                {
                    "full_name": "Морозов Сергей Николаевич",
                    "position": "Ведущий инженер по комплексному контролю",
                    "email": "morozov.sergey@nk-company.ru",
                    "phone": "+7 (495) 567-89-01",
                    "qualifications": {
                        "УЗК": "Специалист III уровня",
                        "РК": "Специалист III уровня",
                        "ВИК": "Специалист III уровня",
                        "МК": "Специалист II уровня"
                    },
                    "equipment_types": ["VESSEL", "PIPELINE", "CRANE", "TRANSFORMER"],
                    "certifications": [
                        {
                            "certification_type": "Допуск к ультразвуковому контролю",
                            "method": "УЗК",
                            "level": "III",
                            "number": "УЗК-2021-234",
                            "issued_by": "Ростехнадзор",
                            "issue_date": date(2021, 4, 10),
                            "expiry_date": date(2024, 4, 10)  # Уже истек!
                        },
                        {
                            "certification_type": "Допуск к радиографическому контролю",
                            "method": "РК",
                            "level": "III",
                            "number": "РК-2023-567",
                            "issued_by": "Ростехнадзор",
                            "issue_date": date(2023, 8, 22),
                            "expiry_date": date(2026, 8, 22)
                        },
                        {
                            "certification_type": "Допуск к визуальному и измерительному контролю",
                            "method": "ВИК",
                            "level": "III",
                            "number": "ВИК-2024-089",
                            "issued_by": "Центр сертификации НК",
                            "issue_date": date(2024, 1, 15),
                            "expiry_date": date(2027, 1, 15)
                        }
                    ]
                },
                {
                    "full_name": "Новикова Ольга Игоревна",
                    "position": "Специалист по неразрушающему контролю I уровня",
                    "email": "novikova.olga@nk-company.ru",
                    "phone": "+7 (495) 678-90-12",
                    "qualifications": {
                        "ВИК": "Специалист I уровня",
                        "ПК": "Специалист I уровня"
                    },
                    "equipment_types": ["VESSEL"],
                    "certifications": [
                        {
                            "certification_type": "Допуск к визуальному и измерительному контролю",
                            "method": "ВИК",
                            "level": "I",
                            "number": "ВИК-2024-145",
                            "issued_by": "Центр сертификации НК",
                            "issue_date": date(2024, 6, 1),
                            "expiry_date": date(2027, 6, 1)
                        },
                        {
                            "certification_type": "Допуск к пенетрантному контролю",
                            "method": "ПК",
                            "level": "I",
                            "number": "ПК-2024-067",
                            "issued_by": "Центр сертификации НК",
                            "issue_date": date(2024, 6, 1),
                            "expiry_date": date(2027, 6, 1)
                        }
                    ]
                }
            ]
            
            added_count = 0
            cert_count = 0
            
            for spec_data in specialists_data:
                # Проверяем, существует ли уже специалист с таким именем
                from sqlalchemy import select
                result = await session.execute(
                    select(Engineer).where(Engineer.full_name == spec_data["full_name"])
                )
                existing = result.scalar_one_or_none()
                
                if existing:
                    print(f"  ⚠ Специалист {spec_data['full_name']} уже существует, пропускаю")
                    continue
                
                # Создаем специалиста
                engineer = Engineer(
                    id=uuid.uuid4(),
                    full_name=spec_data["full_name"],
                    position=spec_data["position"],
                    email=spec_data["email"],
                    phone=spec_data["phone"],
                    qualifications=spec_data["qualifications"],
                    equipment_types=spec_data["equipment_types"],
                    is_active=1
                )
                session.add(engineer)
                await session.flush()
                
                # Добавляем сертификаты
                for cert_data in spec_data["certifications"]:
                    cert = Certification(
                        id=uuid.uuid4(),
                        engineer_id=engineer.id,
                        certification_type=cert_data["certification_type"],
                        method=cert_data["method"],
                        level=cert_data["level"],
                        number=cert_data["number"],
                        issued_by=cert_data["issued_by"],
                        issue_date=cert_data["issue_date"],
                        expiry_date=cert_data["expiry_date"],
                        is_active=1
                    )
                    session.add(cert)
                    cert_count += 1
                
                added_count += 1
                print(f"  ✓ Добавлен: {spec_data['full_name']} ({len(spec_data['certifications'])} сертификатов)")
            
            await session.commit()
            
            print("=" * 60)
            print(f"✅ Добавлено специалистов: {added_count}")
            print(f"✅ Добавлено сертификатов: {cert_count}")
            print("=" * 60)
            
        except Exception as e:
            await session.rollback()
            print(f"❌ Ошибка: {e}")
            import traceback
            traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(init_specialists())

