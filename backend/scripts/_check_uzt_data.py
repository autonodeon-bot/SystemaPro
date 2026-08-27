# quick prod check: latest inspections with UZT points
import asyncio, json, sys
sys.path.insert(0, "/app")
from sqlalchemy import text
from database import AsyncSessionLocal

async def main():
    async with AsyncSessionLocal() as db:
        r = await db.execute(text("""
            SELECT i.id::text, i.data
            FROM inspections i
            ORDER BY i.updated_at DESC NULLS LAST
            LIMIT 15
        """))
        for iid, data in r.fetchall():
            d = data if isinstance(data, dict) else {}
            tm = d.get("thickness_measurements") or []
            schemes = d.get("uzt_schemes") or []
            sm = 0
            for s in schemes if isinstance(schemes, list) else []:
                if isinstance(s, dict):
                    sm += len(s.get("measurements") or [])
            ndt = d.get("ndt_methods") or []
            print(iid[:8], "tm", len(tm) if isinstance(tm, list) else type(tm), "scheme_pts", sm, "ndt", len(ndt) if isinstance(ndt, list) else 0)

asyncio.run(main())
