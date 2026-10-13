#!/bin/bash
set -euo pipefail
cd /opt/es-td-ngo
docker tag systemapro-backend:vessel-v2-3.7.32 systemapro-backend:before-phone-test-fixes
mkdir -p /opt/es-td-ngo/phone-test-fixes
cp backend/hierarchy_management.py backend/form_template_filler.py phone-test-fixes/
printf 'FROM systemapro-backend:before-phone-test-fixes\nCOPY *.py /app/\n' > phone-test-fixes/Dockerfile
docker build -t systemapro-backend:vessel-v2-3.7.32 phone-test-fixes
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend
for i in $(seq 1 25); do
 if docker exec es_td_ngo_backend python -c 'import urllib.request; assert b"healthy" in urllib.request.urlopen("http://127.0.0.1:8000/health",timeout=3).read()' 2>/dev/null; then echo PHONE_FIXES_HEALTHY; exit 0; fi
 sleep 2
done
docker tag systemapro-backend:before-phone-test-fixes systemapro-backend:vessel-v2-3.7.32
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend
exit 1
