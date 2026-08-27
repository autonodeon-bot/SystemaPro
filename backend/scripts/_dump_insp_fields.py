# -*- coding: utf-8 -*-
import asyncio
import json
import sys

sys.path.insert(0, "/app")

from sqlalchemy import text
from database import AsyncSessionLocal

KEYS = [
    "executors",
    "inspection_engineers",
    "ndt_methods",
    "additional_data",
    "medium_characteristics",
    "conclusion",
    "calculation_data",
    "heat_treatment_records",
    "ndt_control_history",
    "previous_inspections",
    "hydraulic_test_history",
    "vessel_elements",
    "documents_info",
    "include_opo_data",
]


async def main():
    async with AsyncSessionLocal() as db:
        r = await db.execute(
            text(
                "SELECT data FROM inspections WHERE id='45dcdf9a-aef7-44cc-9846-a2d6a7ef3acd'"
            )
        )
        d = r.scalar()
        for k in KEYS:
            print("====", k)
            print(json.dumps(d.get(k), ensure_ascii=False, indent=2)[:2000])


if __name__ == "__main__":
    asyncio.run(main())
