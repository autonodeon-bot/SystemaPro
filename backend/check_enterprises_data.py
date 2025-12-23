#!/usr/bin/env python3
"""Проверка данных предприятий в базе"""
import asyncio
import sys
sys.stdout.reconfigure(encoding='utf-8')

from database import get_db
from models import Enterprise, Branch, Workshop, Equipment
from sqlalchemy import select

async def check_data():
    async for db in get_db():
        # Проверяем предприятия
        result = await db.execute(
            select(Enterprise).order_by(Enterprise.name)
        )
        enterprises = result.scalars().all()
        print(f"\n=== ПРЕДПРИЯТИЯ ===")
        print(f"Всего: {len(enterprises)}")
        active = [e for e in enterprises if e.is_active == 1]
        print(f"Активных: {len(active)}")
        for e in active[:10]:
            print(f"  - {e.name} (ID: {e.id}, active: {e.is_active})")
        
        # Проверяем филиалы
        branch_result = await db.execute(select(Branch))
        branches = branch_result.scalars().all()
        print(f"\n=== ФИЛИАЛЫ ===")
        print(f"Всего: {len(branches)}")
        active_branches = [b for b in branches if b.is_active == 1]
        print(f"Активных: {len(active_branches)}")
        
        # Проверяем цеха
        workshop_result = await db.execute(select(Workshop))
        workshops = workshop_result.scalars().all()
        print(f"\n=== ЦЕХА ===")
        print(f"Всего: {len(workshops)}")
        active_workshops = [w for w in workshops if w.is_active == 1]
        print(f"Активных: {len(active_workshops)}")
        
        # Проверяем оборудование
        equipment_result = await db.execute(select(Equipment))
        equipment = equipment_result.scalars().all()
        print(f"\n=== ОБОРУДОВАНИЕ ===")
        print(f"Всего: {len(equipment)}")
        
        break

if __name__ == "__main__":
    asyncio.run(check_data())











