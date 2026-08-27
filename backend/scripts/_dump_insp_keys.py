# -*- coding: utf-8 -*-
"""Dump inspection data keys used for TO-1 fill diagnosis."""
import asyncio
import json
import sys

sys.path.insert(0, "/app")

from sqlalchemy import text
from database import AsyncSessionLocal


INTERESTING = [
    "vessel_name",
    "serial_number",
    "reg_number",
    "organization",
    "location",
    "working_pressure",
    "shell_material",
    "vessel_elements",
    "thickness_measurements",
    "uzt_schemes",
    "documents",
    "previous_inspections",
    "visual_defects",
    "vik_results",
    "hazard_class",
    "working_temperature",
    "calculation_result",
    "technical_state",
    "documentation_conclusion",
    "specialists",
    "report_form_id",
    "protocol_number",
    "contract_number",
    "purpose",
    "volume",
    "diameter",
    "manufacturer",
    "manufacture_year",
    "commissioning_year",
    "design_pressure",
    "test_pressure",
    "working_medium",
    "explosion_hazard",
    "fire_hazard",
    "service_life",
    "hydraulic_test_history",
    "hardness_tests",
    "weld_inspections",
    "operational_diagnostics",
    "vik_illumination",
    "vik_roughness",
    "vik_additional_lighting",
]


async def main():
    insp_id_arg = sys.argv[1] if len(sys.argv) > 1 else "45dcdf9a-aef7-44cc-9846-a2d6a7ef3acd"
    async with AsyncSessionLocal() as db:
        r = await db.execute(
            text(
                """
                SELECT i.id::text, i.data
                FROM inspections i
                WHERE i.id = CAST(:iid AS uuid)
                LIMIT 1
                """
            ),
            {"iid": insp_id_arg},
        )
        row = r.first()
        if not row:
            r = await db.execute(
                text(
                    """
                    SELECT i.id::text, i.data FROM inspections i
                    ORDER BY COALESCE(i.updated_at, i.created_at) DESC NULLS LAST
                    LIMIT 1
                    """
                )
            )
            row = r.first()
        if not row:
            print("NO INSPECTION")
            return
        insp_id, data = row
        d = data if isinstance(data, dict) else {}
        print("ID", insp_id)
        print("TOP_KEYS", sorted(d.keys()))
        for k in INTERESTING:
            v = d.get(k)
            if v is None:
                print(f"MISS {k}")
            elif isinstance(v, (list, dict)):
                print(f"OK {k} type={type(v).__name__} len={len(v)} sample={str(v)[:160]}")
            else:
                print(f"OK {k}={str(v)[:120]}")
        for nest in ("checklist", "checklist_data", "passport", "general", "survey"):
            if nest in d:
                nv = d[nest]
                print(
                    "NEST",
                    nest,
                    type(nv).__name__,
                    list(nv.keys())[:30] if isinstance(nv, dict) else "",
                )
        # also list ndt methods if any related table
        r2 = await db.execute(
            text(
                """
                SELECT method_code, method_name, equipment, conclusion,
                       LEFT(CAST(additional_data AS text), 200)
                FROM ndt_methods
                WHERE inspection_id = CAST(:iid AS uuid)
                """
            ),
            {"iid": insp_id},
        )
        rows = r2.fetchall()
        print("NDT_METHODS", len(rows))
        for row in rows:
            print(" ", row)


if __name__ == "__main__":
    asyncio.run(main())
