#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/es-td-ngo
stage=/opt/es-td-ngo/report-correctness-stage-20261106
backup=/opt/es-td-ngo/report-correctness-backup-$(date +%Y%m%d-%H%M%S)
files=(backend/form_template_filler.py backend/reports_crud_api.py backend/mobile_stats_api.py pages/ReportGeneration.tsx components/report-generation/ReportPreviewModal.tsx components/report-generation/types.ts)
compose=(docker compose -f docker-compose.yml -f docker-compose.audit.yml)
apk=es-td-ngo-3.7.39-82.apk
echo "bf9af39a7b5e05d96ed1f14e962794a5b965b91e1c4eee5b45a9d8ae78d86dc3  $stage/$apk" | sha256sum -c -
mkdir -p "$backup/backend"
cp docker-compose.audit.yml "$backup/"
cp -p mobile-apk/app.apk mobile-apk/app-release.apk "$backup/"
for file in "${files[@]}"; do mkdir -p "$backup/$(dirname "$file")"; cp "$file" "$backup/$file"; done
wait_nginx() {
  for n in {1..25}; do
    if docker exec es_td_ngo_frontend test -s /run/nginx.pid; then docker exec es_td_ngo_frontend nginx -s reload; return; fi
    sleep 1
  done
  return 1
}
rollback() {
  trap - ERR
  cp "$backup/docker-compose.audit.yml" .
  cp "$backup/app.apk" "$backup/app-release.apk" mobile-apk/
  for file in "${files[@]}"; do cp "$backup/$file" "$file"; done
  "${compose[@]}" up -d --no-build --wait --wait-timeout 120 backend frontend
  wait_nginx
  exit 1
}
trap rollback ERR
for name in "$apk" app.apk app-release.apk; do
  cp "$stage/$apk" "mobile-apk/$name.new"
  chmod 644 "mobile-apk/$name.new"
  mv "mobile-apk/$name.new" "mobile-apk/$name"
done
python3 - <<'PY'
from pathlib import Path
path = Path('docker-compose.audit.yml')
text = path.read_text()
old = 'image: systemapro-backend:report-layout-20261106'
assert text.count(old) == 1
assert 'MOBILE_APP_VERSION: "3.7.38"' in text and 'MOBILE_APP_BUILD: "81"' in text
front = 'image: systemapro-frontend:vessel-annotations-20261103'
assert text.count(front) == 1
path.write_text(text.replace(old, 'image: systemapro-backend:report-correctness-20261106')
    .replace(front, 'image: systemapro-frontend:report-correctness-20261106')
    .replace('MOBILE_APP_VERSION: "3.7.38"', 'MOBILE_APP_VERSION: "3.7.39"')
    .replace('MOBILE_APP_BUILD: "81"', 'MOBILE_APP_BUILD: "82"')
    .replace('es-td-ngo-3.7.38-81.apk', 'es-td-ngo-3.7.39-82.apk'))
PY
for file in "${files[@]}"; do cp "$stage/$file" "$file"; done
"${compose[@]}" config --quiet
"${compose[@]}" up -d --no-build --wait --wait-timeout 120 backend frontend
wait_nginx
curl --fail --silent --max-time 15 http://127.0.0.1:8000/health
curl --fail --silent --show-error --retry 8 --retry-delay 1 --retry-all-errors --max-time 15 https://neftcontrol.ru/api/mobile/version | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["version"]=="3.7.39" and str(d["build"])=="82"; print(d)'
echo "Rollback files: $backup"
