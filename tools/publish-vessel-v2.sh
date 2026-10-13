#!/bin/bash
set -euo pipefail
cd /opt/es-td-ngo
apk=mobile-apk/es-td-ngo-3.7.32-69.apk
if [ -f "$apk.uploading" ]; then apk="$apk.uploading"; fi
test "$(sha256sum "$apk" | cut -d' ' -f1)" = bae5be0af631fe4189b9a98fae811dd0efdf37de509f837120d019010c3973e9
backup=$(cat vessel-v2-last-backup.txt)
test -f "$backup/docker-compose.audit.yml" || cp docker-compose.audit.yml "$backup/docker-compose.audit.yml"
test -f "$backup/environment.before" || cp .env "$backup/environment.before"
mkdir -p "$backup/final"
tar -xzf vessel-v2-final.tar.gz -C "$backup/final"
printf 'FROM systemapro-backend:audit-20260918\nCOPY backend/ /app/\n' > "$backup/final/Backend.Dockerfile"
printf 'FROM systemapro-frontend:audit-20260918\nCOPY dist/ /usr/share/nginx/html/\n' > "$backup/final/Frontend.Dockerfile"
docker build -t systemapro-backend:vessel-v2-3.7.32 -f "$backup/final/Backend.Dockerfile" "$backup/final"
docker build -t systemapro-frontend:vessel-v2-3.7.32 -f "$backup/final/Frontend.Dockerfile" "$backup/final"
cp "$backup/final/backend/"*.py backend/
cp -a "$backup/final/source/." ./
cp -a "$backup/final/dist/." dist/
python3 - <<'PY'
from pathlib import Path
import re
p=Path('docker-compose.audit.yml');s=p.read_text().replace('systemapro-backend:audit-20260918','systemapro-backend:vessel-v2-3.7.32').replace('systemapro-frontend:audit-20260918','systemapro-frontend:vessel-v2-3.7.32');p.write_text(s)
p=Path('.env');s=p.read_text()
for key,value in {'APP_VERSION':'3.7.32','MOBILE_APP_VERSION':'3.7.32','MOBILE_APP_BUILD':'69'}.items():
 pattern=r'^'+key+r'=.*$'
 s=re.sub(pattern,key+'='+value,s,flags=re.M) if re.search(pattern,s,re.M) else s+'\n'+key+'='+value+'\n'
p.write_text(s)
PY
if [ -f mobile-apk/es-td-ngo-3.7.32-69.apk.uploading ]; then mv mobile-apk/es-td-ngo-3.7.32-69.apk.uploading mobile-apk/es-td-ngo-3.7.32-69.apk; fi
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend frontend
healthy=0
for i in $(seq 1 25); do
 if docker exec es_td_ngo_backend python -c 'import urllib.request; assert b"healthy" in urllib.request.urlopen("http://127.0.0.1:8000/health",timeout=3).read()' 2>/dev/null; then healthy=1; break; fi
 sleep 2
done
if [ "$healthy" != 1 ]; then
 cp "$backup/docker-compose.audit.yml" docker-compose.audit.yml
 cp "$backup/environment.before" .env
 docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend frontend
 echo 'PUBLISH_FAILED_ROLLED_BACK'; exit 1
fi
cp mobile-apk/es-td-ngo-3.7.32-69.apk mobile-apk/app-release.apk
cp mobile-apk/es-td-ngo-3.7.32-69.apk mobile-apk/app.apk
docker exec es_td_ngo_backend python -c 'import urllib.request,json;d=json.load(urllib.request.urlopen("http://127.0.0.1:8000/api/mobile/version"));assert d["version"]=="3.7.32" and d["build"]=="69";print(d)'
docker exec es_td_ngo_frontend nginx -t
echo 'PUBLISHED_3.7.32_69'
