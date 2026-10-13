#!/bin/bash
set -euo pipefail
cd /opt/es-td-ngo
expected="$1"
apk=mobile-apk/es-td-ngo-3.7.32-75.apk
test "$(sha256sum "$apk.uploading" | cut -d' ' -f1)" = "$expected"
cp .env phone-test-fixes/environment.before75
docker tag systemapro-backend:vessel-v2-3.7.32 systemapro-backend:before-phone-build75
cp backend/mobile_stats_api.py phone-test-fixes/
cp backend/vessel_geometry_v2.py phone-test-fixes/
printf 'FROM systemapro-backend:before-phone-build75\nCOPY *.py /app/\n' > phone-test-fixes/Dockerfile
docker build -t systemapro-backend:vessel-v2-3.7.32 phone-test-fixes
mv "$apk.uploading" "$apk"
python3 - <<'PY'
from pathlib import Path
import re
p=Path('.env');s=p.read_text();s=re.sub(r'^MOBILE_APP_BUILD=.*$', 'MOBILE_APP_BUILD=75',s,flags=re.M);p.write_text(s)
PY
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend
for i in $(seq 1 25); do
 if docker exec es_td_ngo_backend python -c 'import urllib.request,json; d=json.load(urllib.request.urlopen("http://127.0.0.1:8000/api/mobile/version",timeout=3)); assert str(d["build"])=="75"' 2>/dev/null; then
   cp "$apk" mobile-apk/app.apk
   cp "$apk" mobile-apk/app-release.apk
   echo PUBLISHED_PHONE_TESTED_75
   exit 0
 fi
 sleep 2
done
cp phone-test-fixes/environment.before75 .env
docker tag systemapro-backend:before-phone-build75 systemapro-backend:vessel-v2-3.7.32
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend
exit 1
