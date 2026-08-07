# -*- coding: utf-8 -*-
import asyncio
import sys
sys.path.insert(0, "/app")
from sqlalchemy import text
from database import AsyncSessionLocal


async def main():
    async with AsyncSessionLocal() as db:
        r = await db.execute(
            text(
                "SELECT name, code, hazard_class, registration_number FROM opos "
                "WHERE code='OPO-004' OR name ILIKE '%004%' LIMIT 3"
            )
        )
        print("OPO", r.fetchall())

        r = await db.execute(
            text(
                "SELECT certificate_number FROM certifications "
                "WHERE engineer_id='5a777b6d-1125-4ab0-a1fb-c233dca2c76b'"
            )
        )
        print("KOROVIN_CERTS", r.fetchall())

        r = await db.execute(
            text("SELECT DISTINCT equipment_type FROM verification_equipment ORDER BY 1")
        )
        print("VE_TYPES", [x[0] for x in r.fetchall()])

        r = await db.execute(
            text(
                """
                SELECT jsonb_array_length(COALESCE(data->'thickness_measurements','[]'::jsonb)),
                       jsonb_array_length(COALESCE(data->'uzt_schemes','[]'::jsonb)),
                       jsonb_array_length(COALESCE(data->'hardness_tests','[]'::jsonb)),
                       jsonb_array_length(COALESCE(data->'weld_inspections','[]'::jsonb)),
                       data->>'opo_name', data->>'opo_hazard_class', data->>'opo_reg_number'
                FROM inspections WHERE id='45dcdf9a-aef7-44cc-9846-a2d6a7ef3acd'
                """
            )
        )
        print("MEAS", r.first())

        r = await db.execute(
            text(
                """
                SELECT column_name FROM information_schema.columns
                WHERE table_name='assignments'
                  AND column_name IN (
                    'contract_number','contract_date','work_period_from',
                    'work_period_to','tech_card_number','report_form_id','basis',
                    'tech_card_file_path'
                  )
                ORDER BY 1
                """
            )
        )
        print("ASSIGN_COLS", [x[0] for x in r.fetchall()])


if __name__ == "__main__":
    asyncio.run(main())
