"""Grant the connected engineer access only to the marked acceptance vessel."""
import asyncio
import json
from pathlib import Path
from datetime import timedelta
import requests
from sqlalchemy import select
from database import AsyncSessionLocal, engine
from models import User
from auth import create_access_token

async def identities():
    async with AsyncSessionLocal() as db:
        admin=(await db.execute(select(User).where(User.role=='admin',User.is_active==True).limit(1))).scalar_one()
        engineer=(await db.execute(select(User).where(User.username=='engineer',User.role=='engineer',User.is_active==True))).scalar_one()
        result=(admin.username,str(engineer.id))
    await engine.dispose()
    return result

admin, engineer_id=asyncio.run(identities())
state=json.loads(Path('/app/uploads/vessel_v2_acceptance/state.json').read_text())
client=requests.Session()
client.headers['Authorization']='Bearer '+create_access_token({'sub':admin},timedelta(minutes=10))
r=client.post('http://127.0.0.1:8000/api/hierarchy/equipment/'+state['equipment_id']+'/assign-engineers',json={'user_ids':[engineer_id]},timeout=30)
assert r.ok, (r.status_code,r.text[:400])
print(json.dumps({'equipment_id':state['equipment_id'],'access_prepared':True}))
