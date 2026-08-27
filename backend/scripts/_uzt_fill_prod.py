import asyncio, json, sys
sys.path.insert(0, "/app")
from pathlib import Path
from sqlalchemy import text
from database import AsyncSessionLocal
from form_template_filler import fill_vessel_form_to1, _enrich_inspection_data
from report_org_settings import load_report_org_settings
from docx import Document

async def main():
    async with AsyncSessionLocal() as db:
        r = await db.execute(text("""
            SELECT i.id::text, i.data, e.name, e.serial_number, e.attributes, e.id::text
            FROM inspections i JOIN equipment e ON e.id=i.equipment_id
            WHERE jsonb_typeof(i.data->'thickness_measurements')='array'
              AND jsonb_array_length(i.data->'thickness_measurements') > 0
            ORDER BY i.updated_at DESC NULLS LAST
            LIMIT 1
        """))
        row = r.first()
        if not row:
            print("no insp with thickness")
            return
        iid, data, eq_name, serial, attrs, eq_id = row
        data = data if isinstance(data, dict) else {}
        print("insp", iid)
        print("tm", json.dumps(data.get("thickness_measurements"), ensure_ascii=False)[:800])
        # ndt methods
        r2 = await db.execute(text("""
            SELECT method_code, additional_data FROM ndt_methods
            WHERE inspection_id=CAST(:iid AS uuid)
        """), {"iid": iid})
        ndt = []
        for code, ad in r2.fetchall():
            print("ndt", code, "ad_keys", list((ad or {}).keys()) if isinstance(ad, dict) else type(ad))
            if isinstance(ad, dict) and ad.get("measurement_points"):
                print("  points", ad.get("measurement_points"))
            ndt.append({"method_code": code, "additional_data": ad or {}, "method_name": code})
        out = Path("/app/reports/_uzt_test.docx")
        fill_vessel_form_to1(
            inspection_data={"id": iid, "data": data, "report_form_id": "to-1"},
            equipment_data={"id": eq_id, "name": eq_name, "serial_number": serial, "attributes": attrs or {}},
            output_path=str(out),
            org_settings=load_report_org_settings(),
            ndt_methods=ndt,
        )
        doc = Document(str(out))
        t = doc.tables[21]
        print("=== table 21 ===")
        for ri, rowt in enumerate(t.rows):
            print(ri, [(c.text or "").replace("\n"," ")[:40] for c in rowt.cells])

asyncio.run(main())
