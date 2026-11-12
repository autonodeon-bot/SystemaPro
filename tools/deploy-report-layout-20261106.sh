#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/es-td-ngo
stage=/opt/es-td-ngo/report-layout-stage-20261106
backup=/opt/es-td-ngo/report-layout-backup-$(date +%Y%m%d-%H%M%S)
files=(vessel_sheet.py vessel_geometry_v2.py form_template_filler.py vessel_epb_appendices.py word_generator.py)
compose=(docker compose -f docker-compose.yml -f docker-compose.audit.yml)
apk=es-td-ngo-3.7.38-81.apk
echo "8ae82427ded81083c850d248ac657d37738929245bb874bd3e23cf9f56a358fd  $stage/$apk" | sha256sum -c -
mkdir -p "$backup/backend"
cp docker-compose.audit.yml "$backup/"
cp -p mobile-apk/app.apk mobile-apk/app-release.apk "$backup/"
for file in "${files[@]}"; do cp "backend/$file" "$backup/backend/$file"; done
rollback() {
  trap - ERR
  cp "$backup/docker-compose.audit.yml" .
  cp "$backup/app.apk" "$backup/app-release.apk" mobile-apk/
  for file in "${files[@]}"; do cp "$backup/backend/$file" "backend/$file"; done
  "${compose[@]}" up -d --no-build --wait --wait-timeout 120 backend
  docker exec es_td_ngo_frontend nginx -s reload
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
old = 'image: systemapro-backend:vessel-annotations-20261103'
assert text.count(old) == 1
assert 'MOBILE_APP_VERSION: "3.7.37"' in text and 'MOBILE_APP_BUILD: "80"' in text
path.write_text(text.replace(old, 'image: systemapro-backend:report-layout-20261106')
    .replace('MOBILE_APP_VERSION: "3.7.37"', 'MOBILE_APP_VERSION: "3.7.38"')
    .replace('MOBILE_APP_BUILD: "80"', 'MOBILE_APP_BUILD: "81"')
    .replace('es-td-ngo-3.7.37-80.apk', 'es-td-ngo-3.7.38-81.apk'))
PY
for file in "${files[@]}"; do cp "$stage/backend/$file" "backend/$file"; done
"${compose[@]}" config --quiet
"${compose[@]}" up -d --no-build --wait --wait-timeout 120 backend
docker exec es_td_ngo_frontend nginx -s reload
curl --fail --silent --max-time 15 http://127.0.0.1:8000/health
curl --fail --silent --show-error --retry 8 --retry-delay 1 --retry-all-errors --max-time 15 https://neftcontrol.ru/api/mobile/version | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["version"]=="3.7.38" and str(d["build"])=="81"; print(d)'
echo "Rollback files: $backup"
