import os, requests, pyotp
assert os.environ.get('APP_ENV')=='test' and os.environ.get('DB_NAME')=='systemapro_upgrade_test'
s=requests.Session(); base='http://127.0.0.1:8000/api/auth'
credentials={'username':'upgrade-smoke','password':'Upgrade-test-only-2026!'}
r=s.post(base+'/login',data=credentials); r.raise_for_status()
s.headers['Authorization']='Bearer '+r.json()['access_token']
r=s.post(base+'/2fa/setup'); r.raise_for_status(); secret=r.json()['secret']
r=s.post(base+'/2fa/enable',json={'code':pyotp.TOTP(secret).now()}); r.raise_for_status()
recovery=r.json()['recovery_codes'][0]
assert s.post(base+'/2fa/setup').status_code==409
r=s.post(base+'/login',data=credentials); r.raise_for_status()
assert r.json()['two_factor_required'] and 'access_token' not in r.json()
for code in (pyotp.TOTP(secret).now(),recovery):
    r=s.post(base+'/2fa/verify',json={**credentials,'code':code}); r.raise_for_status()
    assert r.json()['access_token']
assert s.post(base+'/2fa/verify',json={**credentials,'code':recovery}).status_code==400
print('PASS: MFA setup, enable, login challenge, TOTP, recovery code consumed once, setup reset blocked')
