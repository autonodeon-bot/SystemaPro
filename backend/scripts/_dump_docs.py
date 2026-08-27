import json, os, sys
sys.path.insert(0, "/app")
os.chdir("/app")
import asyncio
from sqlalchemy import text
from database import AsyncSessionLocal

async def main():
    async with AsyncSessionLocal() as db:
        # document files for inspection
        r = await db.execute(text("""
            SELECT document_number, file_name, file_path, mime_type
            FROM document_files
            WHERE inspection_id = CAST('45dcdf9a-aef7-44cc-9846-a2d6a7ef3acd' AS uuid)
            ORDER BY document_number
        """))
        rows = r.fetchall()
        print("document_files", len(rows))
        for row in rows[:50]:
            print(row[0], row[1], row[2])
        # ndt methods table?
        r2 = await db.execute(text("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name='ndt_methods' ORDER BY ordinal_position
        """))
        cols = [x[0] for x in r2.fetchall()]
        print("ndt_methods cols", cols)
        if cols:
            r3 = await db.execute(text("""
                SELECT * FROM ndt_methods
                WHERE inspection_id = CAST('45dcdf9a-aef7-44cc-9846-a2d6a7ef3acd' AS uuid)
            """))
            for row in r3.mappings():
                print(dict(row))
        # questionnaire?
        r4 = await db.execute(text("""
            SELECT questionnaire_id FROM inspections
            WHERE id = CAST('45dcdf9a-aef7-44cc-9846-a2d6a7ef3acd' AS uuid)
        """))
        qid = r4.scalar()
        print("questionnaire_id", qid)
        if qid:
            r5 = await db.execute(text("""
                SELECT document_number, file_name, file_path FROM document_files
                WHERE questionnaire_id = CAST(:qid AS uuid)
                ORDER BY document_number
            """), {"qid": str(qid)})
            rows5 = r5.fetchall()
            print("q document_files", len(rows5))
            for row in rows5[:40]:
                print(row[0], row[1], row[2])

asyncio.run(main())
