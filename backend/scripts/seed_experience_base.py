"""
Загрузка архетипов опытной базы.

Запуск из каталога backend:
  python -m scripts.seed_experience_base
"""
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from database import AsyncSessionLocal
from experience_base_api import ensure_experience_archetype_seed


async def main() -> None:
    async with AsyncSessionLocal() as session:
        n = await ensure_experience_archetype_seed(session)
    print(f"OK: processed {n} archetype definitions")


if __name__ == "__main__":
    asyncio.run(main())
