#!/bin/bash
set -euo pipefail
cd /opt/es-td-ngo
apk=mobile-apk/es-td-ngo-3.7.33-76.apk
test "$(sha256sum "$apk.uploading" | cut -d' ' -f1)" = "$1"
cp .env backups/environment.before-build76
mv "$apk.uploading" "$apk"
python3 - <<'PY'
from pathlib import Path
import re
p=Path('.env');s=p.read_text()
for key,value in {'MOBILE_APP_VERSION':'3.7.33','MOBILE_APP_BUILD':'76','MOBILE_APP_DOWNLOAD_URL':'https://neftcontrol.ru/mobile/es-td-ngo-3.7.33-76.apk'}.items():
 line=f'{key}={value}'
 s=re.sub(r'^'+key+r'=.*$',line,s,flags=re.M) if re.search(r'^'+key+r'=',s,re.M) else s+'\n'+line+'\n'
p.write_text(s)
PY
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend
for i in $(seq 1 25); do
 if docker exec es_td_ngo_backend python -c 'import urllib.request,json; d=json.load(urllib.request.urlopen("http://127.0.0.1:8000/api/mobile/version",timeout=3)); assert str(d["build"])=="76" and d["version"]=="3.7.33"' 2>/dev/null; then
   cp "$apk" mobile-apk/app.apk
   cp "$apk" mobile-apk/app-release.apk
   echo PUBLISHED_3.7.33_76
   exit 0
 fi
 sleep 2
done
cp backups/environment.before-build76 .env
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend
exit 1
