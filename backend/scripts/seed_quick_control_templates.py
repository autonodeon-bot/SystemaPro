"""
Идемпотентная загрузка шаблонов протоколов «Быстрый контроль».

Запуск из каталога backend:
  python -m scripts.seed_quick_control_templates
"""
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from database import AsyncSessionLocal
from quick_control_protocol_templates import ensure_quick_control_templates


async def main() -> None:
    async with AsyncSessionLocal() as session:
        n = await ensure_quick_control_templates(session, created_by="seed_script")
    print(f"OK: {n} quick control templates")


if __name__ == "__main__":
    asyncio.run(main())
