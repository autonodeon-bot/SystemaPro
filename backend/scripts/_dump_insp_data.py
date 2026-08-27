import json, os, sys
sys.path.insert(0, "/app")
os.chdir("/app")
import asyncio
from sqlalchemy import text
from database import AsyncSessionLocal

async def main():
    async with AsyncSessionLocal() as db:
        r = await db.execute(text("""
            SELECT i.data, e.name, e.serial_number, e.attributes, et.code, et.name
            FROM inspections i
            JOIN equipment e ON e.id = i.equipment_id
            LEFT JOIN equipment_types et ON et.id = e.type_id
            WHERE i.id = CAST('45dcdf9a-aef7-44cc-9846-a2d6a7ef3acd' AS uuid)
        """))
        row = r.first()
        data = row[0] if isinstance(row[0], dict) else {}
        print("equipment:", row[1], "serial:", row[2], "type:", row[4], row[5])
        print("attrs keys:", list((row[3] or {}).keys()) if isinstance(row[3], dict) else type(row[3]))
        print("data top keys:", sorted(data.keys()))
        # print nested interesting
        for k in sorted(data.keys()):
            v = data[k]
            if isinstance(v, dict):
                print(f"  {k}: dict keys={list(v.keys())[:30]} size={len(v)}")
            elif isinstance(v, list):
                print(f"  {k}: list len={len(v)} sample={json.dumps(v[:1], ensure_ascii=False, default=str)[:300]}")
            else:
                s = str(v)
                print(f"  {k}: {type(v).__name__}={s[:120]}")
        # dump full to file
        Path = __import__('pathlib').Path
        Path('/tmp/insp_data.json').write_text(json.dumps({
            'equipment_name': row[1],
            'serial': row[2],
            'attributes': row[3],
            'type_code': row[4],
            'data': data,
        }, ensure_ascii=False, default=str, indent=2), encoding='utf-8')
        print('wrote /tmp/insp_data.json', Path('/tmp/insp_data.json').stat().st_size)

asyncio.run(main())
