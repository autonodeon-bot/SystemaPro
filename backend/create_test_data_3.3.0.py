"""
Скрипт для создания тестовых данных версии 3.3.0
Создает: предприятия, филиалы, цеха, 20 единиц оборудования и инженеров
"""
import asyncio
from sqlalchemy import select
from database import engine, AsyncSessionLocal
from models import (
    Enterprise, Branch, Workshop, EquipmentType, Equipment,
    User, Engineer
)
from auth import hash_password
from datetime import date, datetime
import uuid

async def create_test_data_3_3_0():
    """Создать тестовые данные для версии 3.3.0"""
    async with AsyncSessionLocal() as db:
        try:
            print("=" * 60)
            print("Создание тестовых данных версии 3.3.0")
            print("=" * 60)
            print()
            
            # 1. Создаем предприятия
            print("1. Создание предприятий...")
            enterprises_data = [
                {"name": "ООО ГазНефть", "code": "GN001"},
                {"name": "ПАО НефтеГаз", "code": "NG002"},
                {"name": "ООО ЭнергоПром", "code": "EP003"},
                {"name": "ООО ПромСервис", "code": "PS004"},
            ]
            
            enterprises = []
            for ent_data in enterprises_data:
                result = await db.execute(
                    select(Enterprise).where(Enterprise.name == ent_data["name"])
                )
                existing = result.scalar_one_or_none()
                if not existing:
                    enterprise = Enterprise(
                        name=ent_data["name"],
                        code=ent_data["code"]
                    )
                    db.add(enterprise)
                    await db.flush()
                    enterprises.append(enterprise)
                    print(f"   ✅ Создано предприятие: {ent_data['name']}")
                else:
                    enterprises.append(existing)
                    print(f"   ⚠️  Предприятие уже существует: {ent_data['name']}")
            
            await db.commit()
            
            # 2. Создаем филиалы
            print("\n2. Создание филиалов...")
            branches_data = [
                {"enterprise": 0, "name": "НГДУ-1", "code": "NGDU1"},
                {"enterprise": 0, "name": "НГДУ-2", "code": "NGDU2"},
                {"enterprise": 1, "name": "Филиал Северный", "code": "NORTH"},
                {"enterprise": 1, "name": "Филиал Южный", "code": "SOUTH"},
                {"enterprise": 2, "name": "Производственный участок", "code": "PROD"},
                {"enterprise": 3, "name": "Сервисный центр", "code": "SERVICE"},
            ]
            
            branches = []
            for branch_data in branches_data:
                enterprise = enterprises[branch_data["enterprise"]]
                result = await db.execute(
                    select(Branch).where(
                        Branch.name == branch_data["name"],
                        Branch.enterprise_id == enterprise.id
                    )
                )
                existing = result.scalar_one_or_none()
                if not existing:
                    branch = Branch(
                        enterprise_id=enterprise.id,
                        name=branch_data["name"],
                        code=branch_data["code"]
                    )
                    db.add(branch)
                    await db.flush()
                    branches.append(branch)
                    print(f"   ✅ Создан филиал: {branch_data['name']} ({enterprise.name})")
                else:
                    branches.append(existing)
                    print(f"   ⚠️  Филиал уже существует: {branch_data['name']}")
            
            await db.commit()
            
            # 3. Создаем цеха
            print("\n3. Создание цехов...")
            workshops_data = [
                {"branch": 0, "name": "Цех подготовки нефти", "code": "CPN1"},
                {"branch": 0, "name": "Цех переработки", "code": "CPN2"},
                {"branch": 1, "name": "Цех добычи", "code": "CD1"},
                {"branch": 2, "name": "Цех компрессорный", "code": "CK1"},
                {"branch": 3, "name": "Цех очистки", "code": "CO1"},
                {"branch": 4, "name": "Цех энергетики", "code": "CE1"},
                {"branch": 5, "name": "Цех ремонта", "code": "CR1"},
            ]
            
            workshops = []
            for workshop_data in workshops_data:
                branch = branches[workshop_data["branch"]]
                result = await db.execute(
                    select(Workshop).where(
                        Workshop.name == workshop_data["name"],
                        Workshop.branch_id == branch.id
                    )
                )
                existing = result.scalar_one_or_none()
                if not existing:
                    workshop = Workshop(
                        branch_id=branch.id,
                        name=workshop_data["name"],
                        code=workshop_data["code"]
                    )
                    db.add(workshop)
                    await db.flush()
                    workshops.append(workshop)
                    print(f"   ✅ Создан цех: {workshop_data['name']} ({branch.name})")
                else:
                    workshops.append(existing)
                    print(f"   ⚠️  Цех уже существует: {workshop_data['name']}")
            
            await db.commit()
            
            # 4. Создаем типы оборудования
            print("\n4. Создание типов оборудования...")
            equipment_types_data = [
                {"name": "Сосуд под давлением", "code": "VESSEL"},
                {"name": "Трубопровод", "code": "PIPELINE"},
                {"name": "Резервуар", "code": "TANK"},
                {"name": "Компрессор", "code": "COMPRESSOR"},
                {"name": "Насос", "code": "PUMP"},
            ]
            
            equipment_types = []
            for type_data in equipment_types_data:
                result = await db.execute(
                    select(EquipmentType).where(EquipmentType.code == type_data["code"])
                )
                existing = result.scalar_one_or_none()
                if not existing:
                    eq_type = EquipmentType(
                        name=type_data["name"],
                        code=type_data["code"]
                    )
                    db.add(eq_type)
                    await db.flush()
                    equipment_types.append(eq_type)
                    print(f"   ✅ Создан тип: {type_data['name']}")
                else:
                    equipment_types.append(existing)
                    print(f"   ⚠️  Тип уже существует: {type_data['name']}")
            
            await db.commit()
            
            # 5. Создаем 20 единиц оборудования
            print("\n5. Создание 20 единиц оборудования...")
            equipment_list = [
                {"workshop": 0, "type": 0, "name": "Сосуд В-101", "serial": "V-101-2020", "code": "EQ-V-101"},
                {"workshop": 0, "type": 0, "name": "Сосуд В-102", "serial": "V-102-2020", "code": "EQ-V-102"},
                {"workshop": 0, "type": 1, "name": "Трубопровод ТП-1", "serial": "TP-001", "code": "EQ-TP-001"},
                {"workshop": 1, "type": 0, "name": "Сосуд В-201", "serial": "V-201-2019", "code": "EQ-V-201"},
                {"workshop": 1, "type": 2, "name": "Резервуар Р-301", "serial": "R-301-2021", "code": "EQ-R-301"},
                {"workshop": 1, "type": 3, "name": "Компрессор К-401", "serial": "K-401-2018", "code": "EQ-K-401"},
                {"workshop": 2, "type": 0, "name": "Сосуд В-103", "serial": "V-103-2022", "code": "EQ-V-103"},
                {"workshop": 2, "type": 1, "name": "Трубопровод ТП-2", "serial": "TP-002", "code": "EQ-TP-002"},
                {"workshop": 2, "type": 4, "name": "Насос Н-501", "serial": "N-501-2020", "code": "EQ-N-501"},
                {"workshop": 3, "type": 0, "name": "Сосуд В-202", "serial": "V-202-2019", "code": "EQ-V-202"},
                {"workshop": 3, "type": 2, "name": "Резервуар Р-302", "serial": "R-302-2021", "code": "EQ-R-302"},
                {"workshop": 3, "type": 3, "name": "Компрессор К-402", "serial": "K-402-2018", "code": "EQ-K-402"},
                {"workshop": 4, "type": 0, "name": "Сосуд В-104", "serial": "V-104-2022", "code": "EQ-V-104"},
                {"workshop": 4, "type": 1, "name": "Трубопровод ТП-3", "serial": "TP-003", "code": "EQ-TP-003"},
                {"workshop": 4, "type": 4, "name": "Насос Н-502", "serial": "N-502-2020", "code": "EQ-N-502"},
                {"workshop": 5, "type": 0, "name": "Сосуд В-203", "serial": "V-203-2019", "code": "EQ-V-203"},
                {"workshop": 5, "type": 2, "name": "Резервуар Р-303", "serial": "R-303-2021", "code": "EQ-R-303"},
                {"workshop": 6, "type": 0, "name": "Сосуд В-105", "serial": "V-105-2022", "code": "EQ-V-105"},
                {"workshop": 6, "type": 1, "name": "Трубопровод ТП-4", "serial": "TP-004", "code": "EQ-TP-004"},
                {"workshop": 6, "type": 3, "name": "Компрессор К-403", "serial": "K-403-2018", "code": "EQ-K-403"},
            ]
            
            created_equipment = []
            for eq_data in equipment_list:
                workshop = workshops[eq_data["workshop"]]
                eq_type = equipment_types[eq_data["type"]]
                
                # Проверяем, существует ли оборудование с таким кодом
                result = await db.execute(
                    select(Equipment).where(Equipment.equipment_code == eq_data["code"])
                )
                existing = result.scalar_one_or_none()
                
                if not existing:
                    # Получаем филиал для location
                    branch_result = await db.execute(
                        select(Branch).where(Branch.id == workshop.branch_id)
                    )
                    branch = branch_result.scalar_one_or_none()
                    branch_name = branch.name if branch else "Неизвестный филиал"
                    
                    equipment = Equipment(
                        equipment_code=eq_data["code"],
                        type_id=eq_type.id,
                        workshop_id=workshop.id,
                        name=eq_data["name"],
                        serial_number=eq_data["serial"],
                        location=f"{workshop.name}, {branch_name}",
                        commissioning_date=date(2020, 1, 1),
                        attributes={
                            "pressure": "1.6 МПа",
                            "temperature": "150°C",
                            "volume": "50 м³"
                        }
                    )
                    db.add(equipment)
                    await db.flush()
                    created_equipment.append(equipment)
                    print(f"   ✅ Создано оборудование: {eq_data['name']} ({eq_data['code']})")
                else:
                    created_equipment.append(existing)
                    print(f"   ⚠️  Оборудование уже существует: {eq_data['name']}")
            
            await db.commit()
            
            # 6. Создаем инженеров
            print("\n6. Создание инженеров...")
            engineers_data = [
                {
                    "full_name": "Иванов Иван Иванович",
                    "email": "engineer1@example.com",
                    "phone": "+7 (999) 123-45-67",
                    "username": "engineer1",
                    "password": "engineer123",
                },
                {
                    "full_name": "Петров Петр Петрович",
                    "email": "engineer2@example.com",
                    "phone": "+7 (999) 234-56-78",
                    "username": "engineer2",
                    "password": "engineer123",
                },
                {
                    "full_name": "Сидоров Сидор Сидорович",
                    "email": "engineer3@example.com",
                    "phone": "+7 (999) 345-67-89",
                    "username": "engineer3",
                    "password": "engineer123",
                },
                {
                    "full_name": "Кузнецов Алексей Владимирович",
                    "email": "engineer4@example.com",
                    "phone": "+7 (999) 456-78-90",
                    "username": "engineer4",
                    "password": "engineer123",
                },
            ]
            
            created_engineers = []
            for eng_data in engineers_data:
                # Проверяем, существует ли пользователь
                result = await db.execute(
                    select(User).where(User.username == eng_data["username"])
                )
                existing_user = result.scalar_one_or_none()
                
                if not existing_user:
                    # Создаем инженера
                    engineer = Engineer(
                        id=uuid.uuid4(),
                        full_name=eng_data["full_name"],
                        position="Инженер по неразрушающему контролю",
                        email=eng_data["email"],
                        phone=eng_data["phone"],
                        qualifications=["ВИК", "УЗК", "РК"],
                        equipment_types=["vessel", "pipeline"]
                    )
                    db.add(engineer)
                    await db.flush()
                    
                    # Создаем пользователя
                    user = User(
                        id=uuid.uuid4(),
                        username=eng_data["username"],
                        email=eng_data["email"],
                        full_name=eng_data["full_name"],
                        password_hash=hash_password(eng_data["password"]),
                        role="engineer",
                        engineer_id=engineer.id,
                        is_active=1
                    )
                    db.add(user)
                    await db.flush()
                    
                    created_engineers.append({"engineer": engineer, "user": user})
                    print(f"   ✅ Создан инженер: {eng_data['full_name']} ({eng_data['username']})")
                else:
                    print(f"   ⚠️  Инженер уже существует: {eng_data['username']}")
            
            await db.commit()
            
            print("\n" + "=" * 60)
            print("✅ Тестовые данные успешно созданы!")
            print("=" * 60)
            print(f"\nСоздано:")
            print(f"  - Предприятий: {len(enterprises)}")
            print(f"  - Филиалов: {len(branches)}")
            print(f"  - Цехов: {len(workshops)}")
            print(f"  - Типов оборудования: {len(equipment_types)}")
            print(f"  - Единиц оборудования: {len(created_equipment)}")
            print(f"  - Инженеров: {len(created_engineers)}")
            print(f"\nУчетные данные инженеров:")
            for eng_data in engineers_data:
                print(f"  - {eng_data['username']} / {eng_data['password']}")
            print()
            
        except Exception as e:
            await db.rollback()
            print(f"\n❌ Ошибка при создании тестовых данных: {e}")
            import traceback
            traceback.print_exc()
            raise

if __name__ == "__main__":
    asyncio.run(create_test_data_3_3_0())

