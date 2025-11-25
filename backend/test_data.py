"""
Скрипт для добавления тестовых данных в базу данных
"""
import asyncio
import os
from datetime import datetime, timedelta
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy import select
import uuid

# Импортируем модели
from models import (
    Client, Project, Equipment, EquipmentType, Inspection,
    EquipmentResource, RegulatoryDocument, Engineer, Certification
)
from database import DATABASE_URL
import ssl

def get_ssl_context():
    """Create SSL context for database connection"""
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE
    return ssl_context

async def create_test_data():
    """Создание тестовых данных"""
    
    # Создаем подключение
    connect_args = {}
    if os.getenv("DB_SSLMODE", "require") in ["verify-full", "require", "prefer"]:
        connect_args["ssl"] = get_ssl_context()
    else:
        connect_args["ssl"] = "require"
    
    engine = create_async_engine(DATABASE_URL, echo=False, connect_args=connect_args)
    
    # Используем тот же подход, что и в database.py
    AsyncSessionLocal = async_sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
        autocommit=False,
        autoflush=False,
    )
    
    async with AsyncSessionLocal() as session:
        try:
            print("🔄 Создание тестовых данных...")
            
            # 1. Типы оборудования
            print("  📦 Создание типов оборудования...")
            vessel_type = EquipmentType(
                id=uuid.uuid4(),
                name="Сосуд под давлением",
                description="Сосуды, работающие под давлением",
                code="VESSEL",
                is_active=1
            )
            crane_type = EquipmentType(
                id=uuid.uuid4(),
                name="Кран грузоподъемный",
                description="Краны различных типов",
                code="CRANE",
                is_active=1
            )
            transformer_type = EquipmentType(
                id=uuid.uuid4(),
                name="Трансформатор",
                description="Силовые трансформаторы",
                code="TRANSFORMER",
                is_active=1
            )
            session.add_all([vessel_type, crane_type, transformer_type])
            await session.flush()
            print(f"    ✅ Создано 3 типа оборудования")
            
            # 2. Клиенты
            print("  🏢 Создание клиентов...")
            client1 = Client(
                id=uuid.uuid4(),
                name="ООО \"ГазНефть\"",
                inn="7701234567",
                address="г. Москва, ул. Примерная, д. 1",
                contact_person="Иванов Иван Иванович",
                contact_phone="+7 (495) 123-45-67",
                contact_email="ivanov@gazneft.ru",
                notes="Основной клиент",
                is_active=1
            )
            client2 = Client(
                id=uuid.uuid4(),
                name="ПАО \"НефтеГаз\"",
                inn="7707654321",
                address="г. Санкт-Петербург, пр. Невский, д. 100",
                contact_person="Петров Петр Петрович",
                contact_phone="+7 (812) 234-56-78",
                contact_email="petrov@neftegaz.ru",
                is_active=1
            )
            session.add_all([client1, client2])
            await session.flush()
            print(f"    ✅ Создано 2 клиента")
            
            # 3. Оборудование
            print("  ⚙️ Создание оборудования...")
            equipment1 = Equipment(
                id=uuid.uuid4(),
                type_id=vessel_type.id,
                name="Сосуд Р-101",
                serial_number="SN-2024-001",
                location="НГДУ-1, Цех №2, Установка УПН",
                commissioning_date=datetime(2020, 1, 15).date(),
                attributes={
                    "regNumber": "Р-101",
                    "pressure": "1.6 МПа",
                    "volume": "50 м³",
                    "diameter": "2000 мм"
                }
            )
            equipment2 = Equipment(
                id=uuid.uuid4(),
                type_id=crane_type.id,
                name="Кран КБ-403",
                serial_number="SN-2023-045",
                location="НГДУ-2, Склад",
                commissioning_date=datetime(2019, 5, 20).date(),
                attributes={
                    "regNumber": "КБ-403",
                    "lifting_capacity": "25 тонн",
                    "span": "20 м"
                }
            )
            equipment3 = Equipment(
                id=uuid.uuid4(),
                type_id=transformer_type.id,
                name="Трансформатор ТМ-1000",
                serial_number="SN-2022-078",
                location="НГДУ-1, Подстанция ПС-1",
                commissioning_date=datetime(2018, 3, 10).date(),
                attributes={
                    "regNumber": "ТМ-1000",
                    "power": "1000 кВА",
                    "voltage": "10/0.4 кВ"
                }
            )
            session.add_all([equipment1, equipment2, equipment3])
            await session.flush()
            print(f"    ✅ Создано 3 единицы оборудования")
            
            # 4. Проекты
            print("  📋 Создание проектов...")
            project1 = Project(
                id=uuid.uuid4(),
                client_id=client1.id,
                name="Диагностика оборудования НГДУ-1",
                description="Комплексная диагностика сосудов и кранов на объекте НГДУ-1",
                status="IN_PROGRESS",
                start_date=datetime.now().date() - timedelta(days=10),
                deadline=datetime.now().date() + timedelta(days=20),
                budget=500000.00
            )
            project2 = Project(
                id=uuid.uuid4(),
                client_id=client2.id,
                name="Экспертиза ПБ трансформаторов",
                description="Экспертиза промышленной безопасности трансформаторов",
                status="PLANNED",
                start_date=datetime.now().date() + timedelta(days=5),
                deadline=datetime.now().date() + timedelta(days=30),
                budget=300000.00
            )
            session.add_all([project1, project2])
            await session.flush()
            print(f"    ✅ Создано 2 проекта")
            
            # 5. Инженеры
            print("  👷 Создание инженеров...")
            engineer1 = Engineer(
                id=uuid.uuid4(),
                full_name="Смирнов Алексей Владимирович",
                position="Ведущий инженер-диагност",
                email="smirnov@company.ru",
                phone="+7 (495) 111-22-33",
                qualifications=["Эксперт по сосудам", "Специалист по кранам"],
                equipment_types=["VESSEL", "CRANE"],
                is_active=1
            )
            engineer2 = Engineer(
                id=uuid.uuid4(),
                full_name="Козлова Мария Сергеевна",
                position="Инженер-диагност",
                email="kozlova@company.ru",
                phone="+7 (495) 222-33-44",
                qualifications=["Эксперт по трансформаторам"],
                equipment_types=["TRANSFORMER"],
                is_active=1
            )
            session.add_all([engineer1, engineer2])
            await session.flush()
            print(f"    ✅ Создано 2 инженера")
            
            # 6. Сертификаты
            print("  🎓 Создание сертификатов...")
            cert1 = Certification(
                id=uuid.uuid4(),
                engineer_id=engineer1.id,
                certification_type="Допуск к диагностике сосудов",
                number="CERT-2024-001",
                issued_by="Ростехнадзор",
                issue_date=datetime(2024, 1, 15).date(),
                expiry_date=datetime(2027, 1, 15).date(),
                is_active=1
            )
            cert2 = Certification(
                id=uuid.uuid4(),
                engineer_id=engineer2.id,
                certification_type="Допуск к диагностике электрооборудования",
                number="CERT-2024-002",
                issued_by="Ростехнадзор",
                issue_date=datetime(2024, 2, 20).date(),
                expiry_date=datetime(2027, 2, 20).date(),
                is_active=1
            )
            session.add_all([cert1, cert2])
            await session.flush()
            print(f"    ✅ Создано 2 сертификата")
            
            # 7. Диагностики
            print("  🔍 Создание диагностик...")
            inspection1 = Inspection(
                id=uuid.uuid4(),
                equipment_id=equipment1.id,
                project_id=project1.id,
                inspector_id=engineer1.id,
                date_performed=datetime.now() - timedelta(days=5),
                data={
                    "executors": "Смирнов А.В.",
                    "organization": "НГДУ-1",
                    "vesselName": "Сосуд Р-101",
                    "serialNumber": "SN-2024-001",
                    "regNumber": "Р-101",
                    "workingPressure": "1.6 МПа",
                    "documents": {
                        "1": True,
                        "2": True,
                        "3": False
                    }
                },
                conclusion="Оборудование в работоспособном состоянии. Рекомендуется провести ремонт изоляции.",
                status="SIGNED",
                next_inspection_date=datetime.now().date() + timedelta(days=365)
            )
            inspection2 = Inspection(
                id=uuid.uuid4(),
                equipment_id=equipment2.id,
                project_id=project1.id,
                inspector_id=engineer1.id,
                date_performed=datetime.now() - timedelta(days=3),
                data={
                    "executors": "Смирнов А.В.",
                    "organization": "НГДУ-2",
                    "craneName": "Кран КБ-403",
                    "serialNumber": "SN-2023-045"
                },
                conclusion="Кран в исправном состоянии. Все узлы работают нормально.",
                status="DRAFT",
                next_inspection_date=datetime.now().date() + timedelta(days=180)
            )
            session.add_all([inspection1, inspection2])
            await session.flush()
            print(f"    ✅ Создано 2 диагностики")
            
            # 8. Ресурс оборудования
            print("  ⏱️ Создание записей о ресурсе...")
            resource1 = EquipmentResource(
                id=uuid.uuid4(),
                equipment_id=equipment1.id,
                inspection_id=inspection1.id,
                initial_resource_years=20.0,
                remaining_resource_years=15.5,
                resource_end_date=datetime.now().date() + timedelta(days=365*15),
                extension_years=5.0,
                extension_date=datetime.now().date() + timedelta(days=365*20),
                calculation_method="РД 03-421-01",
                calculation_data={
                    "thickness": 12.5,
                    "corrosion_rate": 0.1,
                    "safety_factor": 1.5
                },
                document_number="EXT-2024-001",
                document_date=datetime.now().date(),
                status="EXTENDED"
            )
            resource2 = EquipmentResource(
                id=uuid.uuid4(),
                equipment_id=equipment2.id,
                inspection_id=inspection2.id,
                initial_resource_years=25.0,
                remaining_resource_years=20.0,
                resource_end_date=datetime.now().date() + timedelta(days=365*20),
                calculation_method="ГОСТ 27584-88",
                calculation_data={
                    "load_cycles": 50000,
                    "safety_factor": 2.0
                },
                status="ACTIVE"
            )
            session.add_all([resource1, resource2])
            await session.flush()
            print(f"    ✅ Создано 2 записи о ресурсе")
            
            # 9. Нормативные документы
            print("  📚 Создание нормативных документов...")
            doc1 = RegulatoryDocument(
                id=uuid.uuid4(),
                document_type="RD",
                number="РД 03-421-01",
                name="Методика оценки остаточного ресурса сосудов и аппаратов",
                description="Методика расчета остаточного ресурса сосудов, работающих под давлением",
                equipment_types=["VESSEL"],
                requirements={
                    "min_thickness": "Расчет минимальной толщины стенки",
                    "corrosion_rate": "Определение скорости коррозии",
                    "safety_factor": "Коэффициент запаса прочности"
                },
                effective_date=datetime(2001, 1, 1).date(),
                is_active=1
            )
            doc2 = RegulatoryDocument(
                id=uuid.uuid4(),
                document_type="GOST",
                number="ГОСТ 14249-89",
                name="Сосуды и аппараты. Нормы и методы расчета на прочность",
                description="Нормы и методы расчета сосудов и аппаратов на прочность",
                equipment_types=["VESSEL"],
                requirements={
                    "design_pressure": "Расчетное давление",
                    "wall_thickness": "Толщина стенки",
                    "welding": "Требования к сварным соединениям"
                },
                effective_date=datetime(1990, 1, 1).date(),
                is_active=1
            )
            doc3 = RegulatoryDocument(
                id=uuid.uuid4(),
                document_type="FNP",
                number="ФНП 032-2021",
                name="Правила промышленной безопасности опасных производственных объектов",
                description="Правила промышленной безопасности для ОПО",
                equipment_types=["VESSEL", "CRANE", "TRANSFORMER"],
                requirements={
                    "inspection_frequency": "Периодичность обследований",
                    "documentation": "Требования к документации",
                    "personnel": "Требования к персоналу"
                },
                effective_date=datetime(2021, 1, 1).date(),
                is_active=1
            )
            session.add_all([doc1, doc2, doc3])
            await session.flush()
            print(f"    ✅ Создано 3 нормативных документа")
            
            # Сохраняем все изменения
            await session.commit()
            print("\n✅ Все тестовые данные успешно созданы!")
            print("\n📊 Сводка:")
            print(f"  - Типы оборудования: 3")
            print(f"  - Клиенты: 2")
            print(f"  - Оборудование: 3")
            print(f"  - Проекты: 2")
            print(f"  - Инженеры: 2")
            print(f"  - Сертификаты: 2")
            print(f"  - Диагностики: 2")
            print(f"  - Ресурсы оборудования: 2")
            print(f"  - Нормативные документы: 3")
            
        except Exception as e:
            await session.rollback()
            print(f"\n❌ Ошибка при создании тестовых данных: {e}")
            import traceback
            traceback.print_exc()
            raise

if __name__ == "__main__":
    asyncio.run(create_test_data())

