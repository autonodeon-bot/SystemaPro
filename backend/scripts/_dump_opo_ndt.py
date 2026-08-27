# -*- coding: utf-8 -*-
import asyncio
import json
import sys

sys.path.insert(0, "/app")
from sqlalchemy import text
from database import AsyncSessionLocal


async def main():
    async with AsyncSessionLocal() as db:
        r = await db.execute(
            text(
                """
                SELECT e.id::text, e.name, e.opo_id::text, o.name, o.code,
                       o.hazard_class, o.registration_number
                FROM equipment e
                LEFT JOIN opos o ON o.id = e.opo_id
                WHERE e.id = (
                  SELECT equipment_id FROM inspections
                  WHERE id='45dcdf9a-aef7-44cc-9846-a2d6a7ef3acd'
                )
                """
            )
        )
        print("EQUIP_OPO", r.first())

        r = await db.execute(
            text(
                """
                SELECT method_code, equipment, conclusion,
                       CAST(additional_data AS text), CAST(results AS text), CAST(defects AS text)
                FROM ndt_methods
                WHERE inspection_id='45dcdf9a-aef7-44cc-9846-a2d6a7ef3acd'
                """
            )
        )
        for row in r.fetchall():
            print("NDT", row[0], "eq=", row[1], "concl=", row[2])
            print("  ad=", (row[3] or "")[:300])
            print("  res=", (row[4] or "")[:200])

        r = await db.execute(
            text(
                """
                SELECT u.id::text, u.full_name, u.engineer_id::text, u.username
                FROM users u
                WHERE u.full_name ILIKE '%оровин%' OR u.username ILIKE '%korov%'
                   OR u.full_name ILIKE '%Korovin%'
                """
            )
        )
        users = r.fetchall()
        print("USERS", users)

        r = await db.execute(
            text(
                """
                SELECT c.certificate_number, c.method_code, c.expiry_date, c.engineer_id::text,
                       e.full_name
                FROM certifications c
                LEFT JOIN engineers e ON e.id = c.engineer_id
                ORDER BY c.created_at DESC NULLS LAST
                LIMIT 20
                """
            )
        )
        print("RECENT_CERTS", r.fetchall())

        # find V-201 inspection
        r = await db.execute(
            text(
                """
                SELECT i.id::text, e.name, e.serial_number,
                       i.data->>'vessel_name', i.data->>'executors',
                       CAST(i.data->'inspection_engineers' AS text)
                FROM inspections i
                JOIN equipment e ON e.id=i.equipment_id
                WHERE e.serial_number ILIKE '%V-201%' OR e.name ILIKE '%V-201%'
                   OR i.data->>'vessel_name' ILIKE '%V-201%'
                   OR i.data->>'serial_number' ILIKE '%V-201%'
                ORDER BY COALESCE(i.updated_at,i.created_at) DESC
                LIMIT 5
                """
            )
        )
        print("V201", r.fetchall())


if __name__ == "__main__":
    asyncio.run(main())
