"""
Скрипт для создания тестовых данных: предприятия, филиалы, цеха и 20 единиц оборудования
"""
import asyncio
from sqlalchemy import select
from database import engine, AsyncSessionLocal
from models import Enterprise, Branch, Workshop, EquipmentType, Equipment
from datetime import date
import uuid

async def init_test_hierarchy_data():
    """Создать тестовые данные для иерархии"""
    async with AsyncSessionLocal() as db:
        try:
            # Создаем предприятия
            enterprises_data = [
                {"name": "ООО ГазНефть", "code": "GN001"},
                {"name": "ПАО НефтеГаз", "code": "NG002"},
                {"name": "ООО ЭнергоПром", "code": "EP003"},
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
                    print(f"✅ Создано предприятие: {ent_data['name']}")
                else:
                    enterprises.append(existing)
                    print(f"⚠️  Предприятие уже существует: {ent_data['name']}")
            
            await db.commit()
            
            # Создаем филиалы
            branches_data = [
                {"enterprise": 0, "name": "НГДУ-1", "code": "NGDU1"},
                {"enterprise": 0, "name": "НГДУ-2", "code": "NGDU2"},
                {"enterprise": 1, "name": "Филиал Северный", "code": "NORTH"},
                {"enterprise": 1, "name": "Филиал Южный", "code": "SOUTH"},
                {"enterprise": 2, "name": "Производственный участок", "code": "PROD"},
            ]
            
            branches = []
            for branch_data in branches_data:
                enterprise = enterprises[branch_data["enterprise"]]
                result = await db.execute(
                    select(Branch).where(
                        Branch.enterprise_id == enterprise.id,
                        Branch.name == branch_data["name"]
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
                    print(f"✅ Создан филиал: {branch_data['name']} (предприятие: {enterprise.name})")
                else:
                    branches.append(existing)
                    print(f"⚠️  Филиал уже существует: {branch_data['name']}")
            
            await db.commit()
            
            # Создаем цеха
            workshops_data = [
                {"branch": 0, "name": "Цех подготовки нефти", "code": "CPN1"},
                {"branch": 0, "name": "Цех переработки", "code": "CPR1"},
                {"branch": 1, "name": "Цех добычи", "code": "CD1"},
                {"branch": 2, "name": "Цех компрессорный", "code": "CK1"},
                {"branch": 2, "name": "Цех насосный", "code": "CN1"},
                {"branch": 3, "name": "Цех очистки", "code": "CO1"},
                {"branch": 4, "name": "Цех энергетический", "code": "CE1"},
            ]
            
            workshops = []
            for workshop_data in workshops_data:
                branch = branches[workshop_data["branch"]]
                result = await db.execute(
                    select(Workshop).where(
                        Workshop.branch_id == branch.id,
                        Workshop.name == workshop_data["name"]
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
                    print(f"✅ Создан цех: {workshop_data['name']} (филиал: {branch.name})")
                else:
                    workshops.append(existing)
                    print(f"⚠️  Цех уже существует: {workshop_data['name']}")
            
            await db.commit()
            
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
                existing = result.scalar_one_or_none()
                if not existing:
                    eq_type = EquipmentType(
                        name=type_data["name"],
                        code=type_data["code"]
                    )
                    db.add(eq_type)
                    await db.flush()
                    equipment_types.append(eq_type)
                    print(f"✅ Создан тип оборудования: {type_data['name']}")
                else:
                    equipment_types.append(existing)
                    print(f"⚠️  Тип оборудования уже существует: {type_data['name']}")
            
            await db.commit()
            
            # Создаем 20 единиц оборудования
            equipment_data = [
                {"workshop": 0, "type": 0, "name": "Сосуд В-101", "serial": "SN001", "location": "НГДУ-1, Цех подготовки нефти"},
                {"workshop": 0, "type": 0, "name": "Сосуд В-102", "serial": "SN002", "location": "НГДУ-1, Цех подготовки нефти"},
                {"workshop": 0, "type": 1, "name": "Трубопровод ТП-201", "serial": "TP201", "location": "НГДУ-1, Цех подготовки нефти"},
                {"workshop": 1, "type": 0, "name": "Сосуд В-201", "serial": "SN003", "location": "НГДУ-1, Цех переработки"},
                {"workshop": 1, "type": 2, "name": "Резервуар РВС-5000", "serial": "RVS5000", "location": "НГДУ-1, Цех переработки"},
                {"workshop": 1, "type": 4, "name": "Насос Н-301", "serial": "N301", "location": "НГДУ-1, Цех переработки"},
                {"workshop": 2, "type": 0, "name": "Сосуд В-301", "serial": "SN004", "location": "НГДУ-2, Цех добычи"},
                {"workshop": 2, "type": 1, "name": "Трубопровод ТП-302", "serial": "TP302", "location": "НГДУ-2, Цех добычи"},
                {"workshop": 2, "type": 3, "name": "Компрессор К-401", "serial": "K401", "location": "НГДУ-2, Цех добычи"},
                {"workshop": 3, "type": 0, "name": "Сосуд В-401", "serial": "SN005", "location": "Филиал Северный, Цех компрессорный"},
                {"workshop": 3, "type": 3, "name": "Компрессор К-501", "serial": "K501", "location": "Филиал Северный, Цех компрессорный"},
                {"workshop": 3, "type": 1, "name": "Трубопровод ТП-401", "serial": "TP401", "location": "Филиал Северный, Цех компрессорный"},
                {"workshop": 4, "type": 4, "name": "Насос Н-501", "serial": "N501", "location": "Филиал Северный, Цех насосный"},
                {"workshop": 4, "type": 4, "name": "Насос Н-502", "serial": "N502", "location": "Филиал Северный, Цех насосный"},
                {"workshop": 4, "type": 0, "name": "Сосуд В-501", "serial": "SN006", "location": "Филиал Северный, Цех насосный"},
                {"workshop": 5, "type": 0, "name": "Сосуд В-601", "serial": "SN007", "location": "Филиал Южный, Цех очистки"},
                {"workshop": 5, "type": 2, "name": "Резервуар РВС-3000", "serial": "RVS3000", "location": "Филиал Южный, Цех очистки"},
                {"workshop": 5, "type": 1, "name": "Трубопровод ТП-501", "serial": "TP501", "location": "Филиал Южный, Цех очистки"},
                {"workshop": 6, "type": 0, "name": "Сосуд В-701", "serial": "SN008", "location": "Производственный участок, Цех энергетический"},
                {"workshop": 6, "type": 3, "name": "Компрессор К-601", "serial": "K601", "location": "Производственный участок, Цех энергетический"},
            ]
            
            created_count = 0
            for eq_data in equipment_data:
                workshop = workshops[eq_data["workshop"]]
                eq_type = equipment_types[eq_data["type"]]
                
                result = await db.execute(
                    select(Equipment).where(
                        Equipment.name == eq_data["name"],
                        Equipment.workshop_id == workshop.id
                    )
                )
                existing = result.first()
                if not existing:
                    equipment = Equipment(
                        workshop_id=workshop.id,
                        type_id=eq_type.id,
                        name=eq_data["name"],
                        serial_number=eq_data["serial"],
                        location=eq_data["location"],
                        commissioning_date=date(2020, 1, 1)
                    )
                    db.add(equipment)
                    created_count += 1
                    print(f"✅ Создано оборудование: {eq_data['name']} (цех: {workshop.name})")
                else:
                    print(f"⚠️  Оборудование уже существует: {eq_data['name']}")
            
            await db.commit()
            print(f"\n✅ Всего создано оборудования: {created_count}")
            print("✅ Тестовые данные успешно добавлены!")
            
        except Exception as e:
            await db.rollback()
            print(f"❌ Ошибка при создании тестовых данных: {e}")
            import traceback
            traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(init_test_hierarchy_data())

