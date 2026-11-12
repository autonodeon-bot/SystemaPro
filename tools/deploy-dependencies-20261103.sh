#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/es-td-ngo
stage=/opt/es-td-ngo/dependency-stage-20261103
backup=/opt/es-td-ngo/dependency-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$backup"
cp docker-compose.audit.yml "$backup/"
reload_frontend() {
  for n in {1..30}; do
    if docker exec es_td_ngo_frontend test -s /run/nginx.pid; then docker exec es_td_ngo_frontend nginx -s reload; return; fi
    sleep 1
  done
  return 1
}
files=(backend/auth.py backend/security.py backend/requirements.txt backend/requirements.lock backend/requirements-test.txt backend/Dockerfile backend/report_forms/epb_vessel_layout.docx backend/report_forms/report_fields.json package.json package-lock.json frontend.Dockerfile .node-version .dockerignore)
for file in "${files[@]}"; do
  if [ -f "$file" ]; then mkdir -p "$backup/$(dirname "$file")"; cp "$file" "$backup/$file"; else echo "$file" >> "$backup/previously-absent.txt"; fi
done
rollback() {
  trap - ERR
  echo "Deployment failed; restoring previous images and source from $backup"
  cp "$backup/docker-compose.audit.yml" docker-compose.audit.yml
  for file in "${files[@]}"; do if [ -f "$backup/$file" ]; then cp "$backup/$file" "$file"; fi; done
  if [ -f "$backup/previously-absent.txt" ]; then while IFS= read -r file; do rm -f -- "/opt/es-td-ngo/$file"; done < "$backup/previously-absent.txt"; fi
  docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend frontend
  reload_frontend
  exit 1
}
trap rollback ERR
for file in "${files[@]}"; do cp "$stage/$file" "$file"; done
python3 - <<'PY'
from pathlib import Path
p=Path('docker-compose.audit.yml')
s=p.read_text()
assert 'systemapro-backend:security-20261103' in s and 'systemapro-frontend:vessel-v2-3.7.32' in s
p.write_text(s.replace('systemapro-backend:security-20261103','systemapro-backend:dependencies-20261103').replace('systemapro-frontend:vessel-v2-3.7.32','systemapro-frontend:dependencies-20261103'))
PY
docker compose -f docker-compose.yml -f docker-compose.audit.yml config --quiet
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend frontend
reload_frontend
curl --fail --silent http://127.0.0.1:8000/health
curl --fail --silent https://neftcontrol.ru/ -o "$backup/after-index.html"
curl --fail --silent https://neftcontrol.ru/api/mobile/version
docker inspect --format '{{.Name}} {{.Config.Image}} {{.State.Status}}' es_td_ngo_backend es_td_ngo_frontend
echo "Rollback files: $backup"
