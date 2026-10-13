#!/bin/bash
set -euo pipefail
cd /opt/es-td-ngo
release="visio-$(date +%Y%m%d-%H%M%S)"
backup="backups/$release"
mkdir -p "$backup/stage/backend" "$backup/stage/frontend"
cp .env "$backup/env"
docker tag systemapro-backend:vessel-v2-3.7.32 "systemapro-backend:$release"
docker tag systemapro-frontend:vessel-v2-3.7.32 "systemapro-frontend:$release"
tar -xzf visio-reference-deploy.tar.gz -C "$backup/stage"
cp "$backup/stage/backend/"*.py backend/
printf 'FROM systemapro-backend:%s\nCOPY *.py /app/\n' "$release" > "$backup/stage/backend/Dockerfile"
docker build -t systemapro-backend:vessel-v2-3.7.32 "$backup/stage/backend"
cp -a "$backup/stage/dist" "$backup/stage/frontend/dist"
printf 'FROM systemapro-frontend:%s\nCOPY dist/ /usr/share/nginx/html/\n' "$release" > "$backup/stage/frontend/Dockerfile"
docker build -t systemapro-frontend:vessel-v2-3.7.32 "$backup/stage/frontend"
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend frontend
for i in $(seq 1 25); do
 if docker exec es_td_ngo_backend python -c 'import urllib.request; assert b"healthy" in urllib.request.urlopen("http://127.0.0.1:8000/health",timeout=3).read()' 2>/dev/null; then
   docker exec es_td_ngo_frontend nginx -t
   echo "DEPLOYED $release"
   exit 0
 fi
 sleep 2
done
docker tag "systemapro-backend:$release" systemapro-backend:vessel-v2-3.7.32
docker tag "systemapro-frontend:$release" systemapro-frontend:vessel-v2-3.7.32
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend frontend
exit 1
