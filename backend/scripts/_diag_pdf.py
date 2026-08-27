# -*- coding: utf-8 -*-
"""Fill to-1 with full context, convert to PDF, check strings in both."""
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, "/app")

from sqlalchemy import text
from database import AsyncSessionLocal
from form_template_filler import fill_vessel_form_to1
from report_org_settings import load_report_org_settings
from report_forms_registry import load_forms_catalog
from docx_to_pdf import convert_docx_to_pdf, libreoffice_available


async def main():
    load_forms_catalog.cache_clear()
    insp_id = "45dcdf9a-aef7-44cc-9846-a2d6a7ef3acd"
    async with AsyncSessionLocal() as db:
        r = await db.execute(
            text(
                """
                SELECT i.data, e.name, e.serial_number, e.attributes, e.id::text
                FROM inspections i JOIN equipment e ON e.id=i.equipment_id
                WHERE i.id=CAST(:iid AS uuid)
                """
            ),
            {"iid": insp_id},
        )
        data, eq_name, serial, attrs, eq_id = r.first()
        data = data if isinstance(data, dict) else {}

        ve = []
        vr = await db.execute(
            text(
                """
                SELECT ve.name, ve.serial_number, ve.equipment_type,
                       ve.verification_certificate_number, ve.next_verification_date
                FROM inspection_equipment ie
                JOIN verification_equipment ve ON ve.id = ie.verification_equipment_id
                WHERE ie.inspection_id = CAST(:iid AS uuid)
                """
            ),
            {"iid": insp_id},
        )
        for v in vr.fetchall():
            ve.append(
                {
                    "name": v[0],
                    "serial_number": v[1],
                    "equipment_type": v[2],
                    "verification_certificate_number": v[3],
                    "next_verification_date": str(v[4]) if v[4] else None,
                }
            )

        # specialist docs like API
        specialist_docs = []
        ures = await db.execute(
            text(
                """
                SELECT u.full_name, u.engineer_id::text
                FROM users u
                WHERE u.full_name = 'Коровин Александр Сергеевич'
                LIMIT 1
                """
            )
        )
        u = ures.first()
        if u and u[1]:
            cres = await db.execute(
                text(
                    """
                    SELECT certificate_number, method_code, expiry_date, certification_type
                    FROM certifications WHERE engineer_id = CAST(:eid AS uuid)
                    """
                ),
                {"eid": u[1]},
            )
            items = []
            for c in cres.fetchall():
                items.append(
                    {
                        "certificate_number": c[0],
                        "method_code": c[1],
                        "expiry_date": str(c[2]) if c[2] else None,
                        "certification_type": c[3],
                    }
                )
            specialist_docs.append({"inspector_name": u[0], "certifications": items})
            print("certs", items)

        out = Path("/app/reports/_diag_full.docx")
        fill_vessel_form_to1(
            inspection_data={"id": insp_id, "data": data, "report_form_id": "to-1"},
            equipment_data={
                "id": eq_id,
                "name": eq_name,
                "serial_number": serial,
                "attributes": attrs if isinstance(attrs, dict) else {},
                "type_code": "VESSEL",
            },
            output_path=str(out),
            org_settings=load_report_org_settings(),
            verification_equipment=ve,
            specialist_docs=specialist_docs,
        )
        print("docx", out, out.stat().st_size)
        print("libreoffice", libreoffice_available())
        pdf = convert_docx_to_pdf(str(out), "/app/reports/_diag_full.pdf")
        print("pdf", pdf)
        if pdf:
            import fitz

            doc = fitz.open(pdf)
            text_all = "\n".join(page.get_text() for page in doc)
            for needle in (
                "Коровин",
                "Федоров",
                "Сепаратор нефтегазовый",
                "Не предоставлено",
                "09Г2С",
                "обечайка",
                "СВ-2023",
                "1075",
                "СОДЕРЖАНИЕ",
                "Таблица № 6",
                "Таблица № 7",
            ):
                print(f"PDF[{needle}]", needle in text_all)
            print("pages", doc.page_count)
            # first page snippet
            print("--- page1 ---")
            print(doc[0].get_text()[:800])


if __name__ == "__main__":
    asyncio.run(main())
