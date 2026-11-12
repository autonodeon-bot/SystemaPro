"""Destructive fixtures are restricted to the disposable upgrade test database."""
import asyncio, hashlib, io, json, os, time, uuid, zipfile
import requests
assert os.environ.get('APP_ENV') == 'test'
assert os.environ.get('DB_NAME') == 'systemapro_upgrade_test'
from database import AsyncSessionLocal
from models import User, Equipment
from auth import hash_password

async def seed():
    async with AsyncSessionLocal() as db:
        user = User(username='upgrade-smoke', password_hash=hash_password('Upgrade-test-only-2026!'), role='admin')
        eq = Equipment(name='Upgrade test vessel', serial_number='TEST-20261103', attributes={})
        db.add_all([user, eq])
        await db.commit()
        return str(eq.id)

equipment = asyncio.run(seed())
session = requests.Session()
base = 'http://127.0.0.1:8000'
def call(method, path, **kwargs):
    r = session.request(method, base+path, timeout=180, **kwargs)
    assert r.ok, (path, r.status_code, r.text[:1000])
    return r

login = call('POST', '/api/auth/login', data={'username':'upgrade-smoke','password':'Upgrade-test-only-2026!'}).json()
assert 'password_hash' not in json.dumps(login)
session.headers['Authorization'] = 'Bearer '+login['access_token']
assert call('GET','/api/auth/me').json()['username'] == 'upgrade-smoke'
bad = requests.post(base+'/api/auth/login', data={'username':'upgrade-smoke','password':'wrong'},timeout=30)
assert bad.status_code in (400,401,403)
print('PASS: login, JWT, current user, wrong password', flush=True)

data = {'report_form_id':'to-1','vessel_name':'Upgrade test vessel','serial_number':'TEST-20261103',
        'working_pressure':'1.6','design_pressure':'1.8','wall_thickness':'8','volume':'1.6',
        'working_medium':'air','documents':{},'thickness_measurements':[], 'defects':[]}
checklist = json.dumps({'equipment_id':equipment,'data':data,'status':'DRAFT'}).encode()
manifest = {'version':2,'equipment_id':equipment,'checksums':{'checklist.json':hashlib.sha256(checklist).hexdigest()}}
buf=io.BytesIO()
with zipfile.ZipFile(buf,'w') as z:
    z.writestr('manifest.json',json.dumps(manifest))
    z.writestr('checklist.json',checklist)
archive=buf.getvalue()
def upload():
    return call('POST','/api/inspections/upload-archive',files={'file':('inspection.zip',archive,'application/zip')}).json()
first=upload()
second=upload()
assert first['id'] == second['id'] and second['status']=='already_received', (first,second)
print('PASS: mobile ZIP v2 upload and idempotent retry',flush=True)
for fmt in ('docx','pdf'):
    job_id=str(uuid.uuid4())
    call('POST','/api/reports/jobs',json={'job_id':job_id,'request':{'inspection_id':first['id'],'report_type':'TECHNICAL_REPORT','format':fmt}})
    deadline=time.monotonic()+180
    while time.monotonic()<deadline:
        job=call('GET','/api/reports/jobs/'+job_id).json()
        if job['status'] in ('completed','failed'):break
        time.sleep(1)
    assert job['status']=='completed',job
    content=call('GET','/api/reports/'+job['result']['id']+'/download',params={'format':fmt}).content
    if fmt=='pdf':assert content.startswith(b'%PDF'),content[:100]
    else:
        with zipfile.ZipFile(io.BytesIO(content)) as z: assert 'word/document.xml' in z.namelist()
    print(f'PASS: asynchronous vessel report {fmt}, downloaded {len(content)} bytes',flush=True)
