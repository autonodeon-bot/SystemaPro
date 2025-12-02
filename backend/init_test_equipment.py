"""
Скрипт для создания тестовых единиц оборудования на нескольких предприятиях
"""
import asyncio
from database import AsyncSessionLocal
from models import Client, Workshop, Equipment, EquipmentType
from sqlalchemy import select
import uuid

async def init_test_equipment():
    """Создать тестовое оборудование"""
    async with AsyncSessionLocal() as db:
        try:
            # Создаем или получаем предприятия
            clients_data = [
                {"name": "ООО \"Нефтегаздобыча\"", "inn": "7701234567", "address": "г. Москва, ул. Нефтяная, д. 1"},
                {"name": "ПАО \"Газпром Нефть\"", "inn": "7702345678", "address": "г. Санкт-Петербург, ул. Газпромовская, д. 2"},
                {"name": "ООО \"Роснефть-Добыча\"", "inn": "7703456789", "address": "г. Тюмень, ул. Нефтяников, д. 3"},
            ]
            
            clients = []
            for client_data in clients_data:
                result = await db.execute(
                    select(Client).where(Client.name == client_data["name"])
                )
                client = result.scalar_one_or_none()
                if not client:
                    client = Client(
                        name=client_data["name"],
                        inn=client_data["inn"],
                        address=client_data["address"],
                        is_active=1
                    )
                    db.add(client)
                    await db.flush()
                clients.append(client)
            
            await db.commit()
            await db.refresh(clients[0])
            await db.refresh(clients[1])
            await db.refresh(clients[2])
            
            # Создаем цеха для каждого предприятия
            workshops_data = [
                # Предприятие 1
                {"name": "Цех подготовки нефти №1", "code": "CPN-1", "client_id": clients[0].id, "location": "Площадка А"},
                {"name": "Цех подготовки нефти №2", "code": "CPN-2", "client_id": clients[0].id, "location": "Площадка Б"},
                {"name": "Компрессорная станция", "code": "KS-1", "client_id": clients[0].id, "location": "Площадка В"},
                # Предприятие 2
                {"name": "Установка подготовки газа", "code": "UPG-1", "client_id": clients[1].id, "location": "Месторождение Северное"},
                {"name": "Цех переработки", "code": "CP-1", "client_id": clients[1].id, "location": "Месторождение Южное"},
                # Предприятие 3
                {"name": "Цех добычи №1", "code": "CD-1", "client_id": clients[2].id, "location": "Промплощадка 1"},
                {"name": "Цех добычи №2", "code": "CD-2", "client_id": clients[2].id, "location": "Промплощадка 2"},
            ]
            
            workshops = []
            for workshop_data in workshops_data:
                result = await db.execute(
                    select(Workshop).where(Workshop.code == workshop_data["code"])
                )
                workshop = result.scalar_one_or_none()
                if not workshop:
                    workshop = Workshop(
                        name=workshop_data["name"],
                        code=workshop_data["code"],
                        client_id=workshop_data["client_id"],
                        location=workshop_data["location"],
                        is_active=1
                    )
                    db.add(workshop)
                    await db.flush()
                workshops.append(workshop)
            
            await db.commit()
            for w in workshops:
                await db.refresh(w)
            
            # Получаем или создаем типы оборудования
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
                eq_type = result.scalar_one_or_none()
                if not eq_type:
                    eq_type = EquipmentType(
                        name=type_data["name"],
                        code=type_data["code"],
                        is_active=1
                    )
                    db.add(eq_type)
                    await db.flush()
                equipment_types.append(eq_type)
            
            await db.commit()
            for et in equipment_types:
                await db.refresh(et)
            
            # Создаем тестовое оборудование (25 единиц)
            equipment_list = [
                # Предприятие 1, Цех 1
                {"name": "Сепаратор С-101", "serial_number": "SN-001", "workshop_id": workshops[0].id, "type_id": equipment_types[0].id, "location": "Площадка А, линия 1"},
                {"name": "Сепаратор С-102", "serial_number": "SN-002", "workshop_id": workshops[0].id, "type_id": equipment_types[0].id, "location": "Площадка А, линия 2"},
                {"name": "Резервуар Р-201", "serial_number": "SN-003", "workshop_id": workshops[0].id, "type_id": equipment_types[2].id, "location": "Площадка А, парк резервуаров"},
                {"name": "Насос Н-301", "serial_number": "SN-004", "workshop_id": workshops[0].id, "type_id": equipment_types[4].id, "location": "Площадка А, насосная"},
                {"name": "Трубопровод ТП-401", "serial_number": "SN-005", "workshop_id": workshops[0].id, "type_id": equipment_types[1].id, "location": "Площадка А, магистраль"},
                
                # Предприятие 1, Цех 2
                {"name": "Сепаратор С-201", "serial_number": "SN-006", "workshop_id": workshops[1].id, "type_id": equipment_types[0].id, "location": "Площадка Б, линия 1"},
                {"name": "Резервуар Р-301", "serial_number": "SN-007", "workshop_id": workshops[1].id, "type_id": equipment_types[2].id, "location": "Площадка Б, парк резервуаров"},
                {"name": "Насос Н-401", "serial_number": "SN-008", "workshop_id": workshops[1].id, "type_id": equipment_types[4].id, "location": "Площадка Б, насосная"},
                
                # Предприятие 1, Цех 3
                {"name": "Компрессор К-501", "serial_number": "SN-009", "workshop_id": workshops[2].id, "type_id": equipment_types[3].id, "location": "Площадка В, компрессорная"},
                {"name": "Компрессор К-502", "serial_number": "SN-010", "workshop_id": workshops[2].id, "type_id": equipment_types[3].id, "location": "Площадка В, компрессорная"},
                
                # Предприятие 2, Цех 1
                {"name": "Сосуд В-101", "serial_number": "SN-011", "workshop_id": workshops[3].id, "type_id": equipment_types[0].id, "location": "Месторождение Северное, установка 1"},
                {"name": "Сосуд В-102", "serial_number": "SN-012", "workshop_id": workshops[3].id, "type_id": equipment_types[0].id, "location": "Месторождение Северное, установка 2"},
                {"name": "Трубопровод ТП-501", "serial_number": "SN-013", "workshop_id": workshops[3].id, "type_id": equipment_types[1].id, "location": "Месторождение Северное, магистраль"},
                {"name": "Резервуар Р-401", "serial_number": "SN-014", "workshop_id": workshops[3].id, "type_id": equipment_types[2].id, "location": "Месторождение Северное, парк"},
                
                # Предприятие 2, Цех 2
                {"name": "Сосуд В-201", "serial_number": "SN-015", "workshop_id": workshops[4].id, "type_id": equipment_types[0].id, "location": "Месторождение Южное, установка 1"},
                {"name": "Насос Н-501", "serial_number": "SN-016", "workshop_id": workshops[4].id, "type_id": equipment_types[4].id, "location": "Месторождение Южное, насосная"},
                
                # Предприятие 3, Цех 1
                {"name": "Сепаратор С-301", "serial_number": "SN-017", "workshop_id": workshops[5].id, "type_id": equipment_types[0].id, "location": "Промплощадка 1, линия 1"},
                {"name": "Резервуар Р-501", "serial_number": "SN-018", "workshop_id": workshops[5].id, "type_id": equipment_types[2].id, "location": "Промплощадка 1, парк"},
                {"name": "Трубопровод ТП-601", "serial_number": "SN-019", "workshop_id": workshops[5].id, "type_id": equipment_types[1].id, "location": "Промплощадка 1, магистраль"},
                
                # Предприятие 3, Цех 2
                {"name": "Сепаратор С-401", "serial_number": "SN-020", "workshop_id": workshops[6].id, "type_id": equipment_types[0].id, "location": "Промплощадка 2, линия 1"},
                
                # Дополнительные 5 единиц для тестирования доступа инженеров
                # Предприятие 1, Цех 1
                {"name": "Сепаратор С-103", "serial_number": "SN-021", "workshop_id": workshops[0].id, "type_id": equipment_types[0].id, "location": "Площадка А, линия 3"},
                # Предприятие 1, Цех 2
                {"name": "Трубопровод ТП-402", "serial_number": "SN-022", "workshop_id": workshops[1].id, "type_id": equipment_types[1].id, "location": "Площадка Б, магистраль"},
                # Предприятие 1, Цех 3
                {"name": "Компрессор К-503", "serial_number": "SN-023", "workshop_id": workshops[2].id, "type_id": equipment_types[3].id, "location": "Площадка В, компрессорная"},
                # Предприятие 2, Цех 1
                {"name": "Сосуд В-103", "serial_number": "SN-024", "workshop_id": workshops[3].id, "type_id": equipment_types[0].id, "location": "Месторождение Северное, установка 3"},
                # Предприятие 2, Цех 2
                {"name": "Резервуар Р-502", "serial_number": "SN-025", "workshop_id": workshops[4].id, "type_id": equipment_types[2].id, "location": "Месторождение Южное, парк"},
            ]
            
            created_count = 0
            for eq_data in equipment_list:
                # Проверяем, не существует ли уже такое оборудование
                result = await db.execute(
                    select(Equipment).where(Equipment.serial_number == eq_data["serial_number"])
                )
                existing = result.scalar_one_or_none()
                
                if not existing:
                    equipment = Equipment(
                        name=eq_data["name"],
                        serial_number=eq_data["serial_number"],
                        workshop_id=eq_data["workshop_id"],
                        type_id=eq_data["type_id"],
                        location=eq_data["location"],
                        attributes={
                            "inventory_number": eq_data["serial_number"],
                            "manufacturer": "Отечественный производитель",
                            "manufacture_year": "2020"
                        }
                    )
                    db.add(equipment)
                    created_count += 1
            
            await db.commit()
            print(f"✅ Создано {created_count} единиц оборудования!")
            print(f"   Предприятий: {len(clients)}")
            print(f"   Цехов: {len(workshops)}")
            print(f"   Типов оборудования: {len(equipment_types)}")
            
        except Exception as e:
            await db.rollback()
            print(f"❌ Ошибка при создании оборудования: {e}")
            import traceback
            traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(init_test_equipment())

