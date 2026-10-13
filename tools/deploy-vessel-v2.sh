#!/bin/bash
set -euo pipefail
cd /opt/es-td-ngo
release="vessel-v2-$(date +%Y%m%d-%H%M%S)"
backup="/opt/es-td-ngo/backups/$release"
mkdir -p "$backup/backend" "$backup/frontend" "$backup/stage"
cp backend/*.py "$backup/backend/"
docker cp es_td_ngo_frontend:/usr/share/nginx/html/. "$backup/frontend/"
tar -xzf vessel-v2-deploy.tar.gz -C "$backup/stage"
for f in "$backup/stage/backend/"*.py; do
  python3 -m py_compile "$f"
done
for f in "$backup/stage/backend/"*.py; do
  name=$(basename "$f")
  cp "$f" "backend/$name"
  docker cp "$f" "es_td_ngo_backend:/app/$name"
done
if ! docker exec es_td_ngo_backend python -c 'import main; from vessel_vector import export_pdf; print("IMPORT_OK")'; then
  for f in "$backup/backend/"*.py; do docker cp "$f" "es_td_ngo_backend:/app/$(basename "$f")"; done
  echo 'IMPORT_FAILED_ROLLED_BACK'; exit 1
fi
docker restart es_td_ngo_backend
healthy=0
for i in $(seq 1 20); do
  if docker exec es_td_ngo_backend python -c 'import urllib.request; assert b"healthy" in urllib.request.urlopen("http://127.0.0.1:8000/health",timeout=3).read()' 2>/dev/null; then healthy=1; break; fi
  sleep 2
done
if [ "$healthy" != 1 ]; then
  for f in "$backup/backend/"*.py; do cp "$f" backend/; docker cp "$f" "es_td_ngo_backend:/app/$(basename "$f")"; done
  docker restart es_td_ngo_backend
  echo 'HEALTH_FAILED_ROLLED_BACK'; exit 1
fi
mkdir -p dist
cp -a "$backup/stage/dist/." dist/
docker cp "$backup/stage/dist/." es_td_ngo_frontend:/usr/share/nginx/html/
docker exec es_td_ngo_frontend nginx -t
docker exec es_td_ngo_frontend nginx -s reload
printf '%s\n' "$backup" > /opt/es-td-ngo/vessel-v2-last-backup.txt
echo "DEPLOYED $release BACKUP=$backup"
