#!/usr/bin/env bash
set -Eeuo pipefail
stage=/opt/es-td-ngo/security-stage-20261103
root=/opt/es-td-ngo
cd "$root"
echo '4a1ce662ce96d653fffbc3460cf2da962f2cc25235e811f7684601eee5c67ad9  /opt/es-td-ngo/security-stage-20261103/security-release.apk' | sha256sum -c -
backup="$root/security-mobile-backup-20261103-$(date -u +%H%M%S)"
mkdir -p "$backup"
cp docker-compose.audit.yml backend/mobile_stats_api.py "$backup/"
cp -p mobile-apk/app-release.apk mobile-apk/app.apk "$backup/"
rollback() {
  trap - ERR
  cp "$backup/docker-compose.audit.yml" .
  cp "$backup/mobile_stats_api.py" backend/
  cp "$backup/app-release.apk" "$backup/app.apk" mobile-apk/
  docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-deps --no-build backend
  docker exec es_td_ngo_frontend nginx -s reload
  echo "Mobile publication rolled back from $backup" >&2
  exit 1
}
trap rollback ERR
# New files are complete before each public alias is atomically replaced.
for name in es-td-ngo-3.7.36-79.apk app-release.apk app.apk; do
  cp "$stage/security-release.apk" "mobile-apk/$name.new"
  chmod 644 "mobile-apk/$name.new"
  mv "mobile-apk/$name.new" "mobile-apk/$name"
done
cp "$stage/mobile_stats_api.py" backend/
python3 - <<'PY'
from pathlib import Path
p = Path('docker-compose.audit.yml')
s = p.read_text()
assert s.count('    image: systemapro-backend:security-20261103') == 1
assert 'environment:' not in s
s = s.replace('    image: systemapro-backend:security-20261103', '''    image: systemapro-backend:security-20261103
    environment:
      MOBILE_APP_VERSION: "3.7.36"
      MOBILE_APP_BUILD: "79"
      MOBILE_APP_DOWNLOAD_URL: "https://neftcontrol.ru/mobile/es-td-ngo-3.7.36-79.apk"''')
p.write_text(s)
PY
docker compose -f docker-compose.yml -f docker-compose.audit.yml config --quiet
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-deps --no-build backend
healthy=false
for attempt in $(seq 1 30); do
  if curl --silent --fail http://127.0.0.1:8000/health > "$backup/health.json"; then healthy=true; break; fi
  sleep 2
done
test "$healthy" = true
docker exec es_td_ngo_frontend nginx -s reload
curl --fail --silent https://neftcontrol.ru/api/mobile/version > "$backup/version.json"
python3 - "$backup/version.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data['version'] == '3.7.36' and str(data['build']) == '79', data
assert data['download_url'].endswith('/es-td-ngo-3.7.36-79.apk'), data
print('Published mobile version 3.7.36 (79)')
PY
echo "Mobile rollback files: $backup"
trap - ERR
