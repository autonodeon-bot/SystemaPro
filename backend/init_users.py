"""
Скрипт для инициализации пользователей в системе
"""
import asyncio
from database import engine, Base, AsyncSessionLocal
from models import User, Engineer
from auth import hash_password
from sqlalchemy import select
import uuid

async def init_users():
    """Создать тестовых пользователей"""
    async with AsyncSessionLocal() as db:
        try:
            # Проверяем, есть ли уже пользователи
            result = await db.execute(select(User))
            existing_users = result.scalars().all()
            if existing_users:
                print("⚠️  Пользователи уже существуют. Пропускаем инициализацию.")
                return
            
            # Создаем инженеров
            engineer1 = Engineer(
                id=uuid.uuid4(),
                full_name="Иванов Иван Иванович",
                position="Инженер по неразрушающему контролю",
                email="engineer1@example.com",
                phone="+7 (999) 123-45-67",
                qualifications=["ВИК", "УЗК", "РК"],
                certifications=[],
                equipment_types=["vessel", "pipeline"]
            )
            engineer2 = Engineer(
                id=uuid.uuid4(),
                full_name="Петров Петр Петрович",
                position="Инженер по неразрушающему контролю",
                email="engineer2@example.com",
                phone="+7 (999) 234-56-78",
                qualifications=["ВИК", "РК"],
                certifications=[],
                equipment_types=["vessel"]
            )
            db.add(engineer1)
            db.add(engineer2)
            await db.flush()
            
            # Создаем пользователей
            users_data = [
                {
                    "username": "admin",
                    "email": "admin@example.com",
                    "password": "admin123",
                    "full_name": "Администратор системы",
                    "role": "admin",
                    "engineer_id": None
                },
                {
                    "username": "chief_operator",
                    "email": "chief@example.com",
                    "password": "chief123",
                    "full_name": "Главный оператор",
                    "role": "chief_operator",
                    "engineer_id": None
                },
                {
                    "username": "operator",
                    "email": "operator@example.com",
                    "password": "operator123",
                    "full_name": "Оператор",
                    "role": "operator",
                    "engineer_id": None
                },
                {
                    "username": "engineer1",
                    "email": "engineer1@example.com",
                    "password": "engineer123",
                    "full_name": "Иванов Иван Иванович",
                    "role": "engineer",
                    "engineer_id": engineer1.id
                },
                {
                    "username": "engineer2",
                    "email": "engineer2@example.com",
                    "password": "engineer123",
                    "full_name": "Петров Петр Петрович",
                    "role": "engineer",
                    "engineer_id": engineer2.id
                }
            ]
            
            for user_data in users_data:
                user = User(
                    username=user_data["username"],
                    email=user_data["email"],
                    password_hash=hash_password(user_data["password"]),
                    full_name=user_data["full_name"],
                    role=user_data["role"],
                    engineer_id=user_data["engineer_id"],
                    is_active=True
                )
                db.add(user)
            
            await db.commit()
            print("✅ Пользователи успешно созданы!")
            print("\nТестовые учетные записи:")
            print("  admin / admin123 (Администратор)")
            print("  chief_operator / chief123 (Главный оператор)")
            print("  operator / operator123 (Оператор)")
            print("  engineer1 / engineer123 (Инженер)")
            print("  engineer2 / engineer123 (Инженер)")
            
        except Exception as e:
            await db.rollback()
            print(f"❌ Ошибка при создании пользователей: {e}")
            import traceback
            traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(init_users())


























