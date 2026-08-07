"""Список администраторов в БД (username, email, is_active)."""
import asyncio

from sqlalchemy import select

from database import AsyncSessionLocal
from models import User


async def main() -> None:
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(User.username, User.email, User.role, User.is_active).where(
                User.role == "admin"
            )
        )
        rows = result.all()
        if not rows:
            print("NO_ADMIN_USERS")
            return
        for username, email, role, is_active in rows:
            print(f"{username}\t{email}\t{role}\tactive={is_active}")


if __name__ == "__main__":
    asyncio.run(main())
