#!/usr/bin/env python3
"""
Скрипт для создания тестовых ОПО с данными по предприятиям
"""
import asyncio
import sys
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import select
from database import Base
from models import Enterprise, Branch, Workshop, Opo
import uuid

# Настройки подключения к БД (из переменных окружения или дефолтные)
import os
DB_USER = os.getenv("DB_USER", "gen_user")
DB_PASS = os.getenv("DB_PASS", "")
DB_HOST = os.getenv("DB_HOST", "db")  # В Docker используется имя сервиса
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "default_db")

DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

async def create_test_opos():
    """Создание тестовых ОПО"""
    engine = create_async_engine(DATABASE_URL, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as session:
        try:
            # Получаем первое предприятие
            enterprise_result = await session.execute(
                select(Enterprise).where(Enterprise.is_active == True).limit(1)
            )
            enterprise = enterprise_result.scalar_one_or_none()
            
            if not enterprise:
                print("❌ Не найдено ни одного предприятия. Создайте предприятие сначала.")
                return
            
            print(f"✅ Найдено предприятие: {enterprise.name}")
            
            # Получаем первый филиал предприятия
            branch_result = await session.execute(
                select(Branch).where(
                    Branch.enterprise_id == enterprise.id,
                    Branch.is_active == True
                ).limit(1)
            )
            branch = branch_result.scalar_one_or_none()
            
            if not branch:
                print("❌ Не найден филиал для предприятия. Создайте филиал сначала.")
                return
            
            print(f"✅ Найден филиал: {branch.name}")
            
            # Получаем первый цех филиала
            workshop_result = await session.execute(
                select(Workshop).where(
                    Workshop.branch_id == branch.id,
                    Workshop.is_active == True
                ).limit(1)
            )
            workshop = workshop_result.scalar_one_or_none()
            
            if not workshop:
                print("❌ Не найден цех для филиала. Создайте цех сначала.")
                return
            
            print(f"✅ Найден цех: {workshop.name}")
            
            # Создаем тестовые ОПО с полной информацией
            test_opos = [
                {
                    "name": "ОПО-001 - Резервуарный парк",
                    "code": "OPO-001",
                    "description": "Резервуарный парк для хранения нефтепродуктов. Включает резервуары различной емкости, системы налива и слива, системы безопасности.",
                    "survey_data": {
                        "organization": f"НГДУ {enterprise.name}",
                        "executors": "Иванов И.И., Петров П.П., Сидоров С.С.",
                        "documents": {
                            "1": True,
                            "2": True,
                            "3": True,
                            "4": True,
                            "5": True,
                            "6": True,
                            "7": True,
                            "8": True,
                            "9": True,
                        },
                        "documents_info": {
                            "1": {"number": "ЛИЦ-2024-001", "date": "2024-01-15"},
                            "2": {"number": "СВИД-2024-002", "date": "2024-02-20"},
                            "3": {"number": "ТР-2024-003", "date": "2024-03-10"},
                            "4": {"number": "ПМ-2024-004", "date": "2024-04-05"},
                            "5": {"number": "ППК-2024-005", "date": "2024-05-12"},
                            "6": {"number": "ЖУ-2024-006", "date": "2024-06-01"},
                            "7": {"number": "СТР-2024-007", "date": "2024-07-15"},
                            "8": {"number": "ПРИК-2024-008", "date": "2024-08-20"},
                            "9": {"number": "ПРИК-2024-009", "date": "2024-09-10"},
                        }
                    }
                },
                {
                    "name": "ОПО-002 - Компрессорная станция",
                    "code": "OPO-002",
                    "description": "Компрессорная станция для транспортировки газа. Оборудована компрессорами высокого давления, системами контроля и безопасности.",
                    "survey_data": {
                        "organization": f"НГДУ {enterprise.name}",
                        "executors": "Смирнов А.А., Козлов К.К., Волков В.В.",
                        "documents": {
                            "1": True,
                            "2": True,
                            "3": True,
                            "4": True,
                            "5": True,
                            "6": False,
                            "7": True,
                            "8": True,
                            "9": True,
                        },
                        "documents_info": {
                            "1": {"number": "ЛИЦ-2024-101", "date": "2024-01-20"},
                            "2": {"number": "СВИД-2024-102", "date": "2024-02-25"},
                            "3": {"number": "ТР-2024-103", "date": "2024-03-15"},
                            "4": {"number": "ПМ-2024-104", "date": "2024-04-10"},
                            "5": {"number": "ППК-2024-105", "date": "2024-05-18"},
                            "7": {"number": "СТР-2024-107", "date": "2024-07-20"},
                            "8": {"number": "ПРИК-2024-108", "date": "2024-08-25"},
                            "9": {"number": "ПРИК-2024-109", "date": "2024-09-15"},
                        }
                    }
                },
                {
                    "name": "ОПО-003 - Насосная станция",
                    "code": "OPO-003",
                    "description": "Насосная станция для перекачки нефти. Включает насосные агрегаты, системы управления, резервуары-отстойники.",
                    "survey_data": {
                        "organization": f"НГДУ {enterprise.name}",
                        "executors": "Новиков Н.Н., Морозов М.М., Лебедев Л.Л.",
                        "documents": {
                            "1": True,
                            "2": True,
                            "3": True,
                            "4": True,
                            "5": True,
                            "6": True,
                            "7": True,
                            "8": False,
                            "9": True,
                        },
                        "documents_info": {
                            "1": {"number": "ЛИЦ-2024-201", "date": "2024-01-25"},
                            "2": {"number": "СВИД-2024-202", "date": "2024-03-01"},
                            "3": {"number": "ТР-2024-203", "date": "2024-03-20"},
                            "4": {"number": "ПМ-2024-204", "date": "2024-04-15"},
                            "5": {"number": "ППК-2024-205", "date": "2024-05-22"},
                            "6": {"number": "ЖУ-2024-206", "date": "2024-06-05"},
                            "7": {"number": "СТР-2024-207", "date": "2024-07-25"},
                            "9": {"number": "ПРИК-2024-209", "date": "2024-09-20"},
                        }
                    }
                },
                {
                    "name": "ОПО-004 - Установка подготовки нефти",
                    "code": "OPO-004",
                    "description": "Установка подготовки и стабилизации нефти. Включает сепараторы, дегидраторы, системы контроля качества.",
                    "survey_data": {
                        "organization": f"НГДУ {enterprise.name}",
                        "executors": "Федоров Ф.Ф., Соколов С.С., Попов П.П.",
                        "documents": {
                            "1": True,
                            "2": True,
                            "3": True,
                            "4": False,
                            "5": True,
                            "6": True,
                            "7": True,
                            "8": True,
                            "9": True,
                        },
                        "documents_info": {
                            "1": {"number": "ЛИЦ-2024-301", "date": "2024-02-01"},
                            "2": {"number": "СВИД-2024-302", "date": "2024-03-05"},
                            "3": {"number": "ТР-2024-303", "date": "2024-03-25"},
                            "5": {"number": "ППК-2024-305", "date": "2024-05-28"},
                            "6": {"number": "ЖУ-2024-306", "date": "2024-06-10"},
                            "7": {"number": "СТР-2024-307", "date": "2024-08-01"},
                            "8": {"number": "ПРИК-2024-308", "date": "2024-08-30"},
                            "9": {"number": "ПРИК-2024-309", "date": "2024-09-25"},
                        }
                    }
                },
                {
                    "name": "ОПО-005 - Газоперерабатывающий завод",
                    "code": "OPO-005",
                    "description": "Газоперерабатывающий завод. Комплексная установка для переработки попутного нефтяного газа.",
                    "survey_data": {
                        "organization": f"НГДУ {enterprise.name}",
                        "executors": "Васильев В.В., Павлов П.П., Семенов С.С.",
                        "documents": {
                            "1": True,
                            "2": True,
                            "3": True,
                            "4": True,
                            "5": True,
                            "6": True,
                            "7": True,
                            "8": True,
                            "9": True,
                        },
                        "documents_info": {
                            "1": {"number": "ЛИЦ-2024-401", "date": "2024-02-05"},
                            "2": {"number": "СВИД-2024-402", "date": "2024-03-10"},
                            "3": {"number": "ТР-2024-403", "date": "2024-04-01"},
                            "4": {"number": "ПМ-2024-404", "date": "2024-04-20"},
                            "5": {"number": "ППК-2024-405", "date": "2024-06-01"},
                            "6": {"number": "ЖУ-2024-406", "date": "2024-06-15"},
                            "7": {"number": "СТР-2024-407", "date": "2024-08-05"},
                            "8": {"number": "ПРИК-2024-408", "date": "2024-09-05"},
                            "9": {"number": "ПРИК-2024-409", "date": "2024-09-30"},
                        }
                    }
                },
            ]
            
            created_count = 0
            for opo_data in test_opos:
                # Проверяем, существует ли уже ОПО с таким кодом
                existing_result = await session.execute(
                    select(Opo).where(Opo.code == opo_data["code"])
                )
                existing = existing_result.scalar_one_or_none()
                
                if existing:
                    print(f"⚠️  ОПО с кодом {opo_data['code']} уже существует, пропускаем")
                    continue
                
                new_opo = Opo(
                    id=uuid.uuid4(),
                    workshop_id=workshop.id,
                    name=opo_data["name"],
                    code=opo_data["code"],
                    description=opo_data["description"],
                    survey_data=opo_data.get("survey_data"),
                    is_active=1,
                )
                
                session.add(new_opo)
                created_count += 1
                print(f"✅ Создано ОПО: {opo_data['name']} ({opo_data['code']})")
                if opo_data.get("survey_data"):
                    survey = opo_data["survey_data"]
                    print(f"   Организация: {survey.get('organization', '—')}")
                    print(f"   Исполнители: {survey.get('executors', '—')}")
                    docs = survey.get('documents', {})
                    filled = sum(1 for v in docs.values() if v)
                    print(f"   Документов заполнено: {filled}/9")
            
            await session.commit()
            print(f"\n✅ Успешно создано {created_count} тестовых ОПО")
            print(f"   Предприятие: {enterprise.name}")
            print(f"   Филиал: {branch.name}")
            print(f"   Цех: {workshop.name}")
            
        except Exception as e:
            await session.rollback()
            print(f"❌ Ошибка при создании ОПО: {e}")
            import traceback
            traceback.print_exc()
        finally:
            await engine.dispose()

if __name__ == "__main__":
    asyncio.run(create_test_opos())
