#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/es-td-ngo
stage=/opt/es-td-ngo/vessel-annotations-stage-20261103
echo 'a71484898c33af354bf10162907dc426d3401ee40fa08dd65cdafd558ce1ffcf  /opt/es-td-ngo/vessel-annotations-stage-20261103/mobile-3.7.37-80.apk' | sha256sum -c -
backup=/opt/es-td-ngo/vessel-annotations-mobile-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$backup"
cp docker-compose.audit.yml "$backup/"
cp -p mobile-apk/app-release.apk mobile-apk/app.apk "$backup/"
rollback() {
  trap - ERR
  cp "$backup/docker-compose.audit.yml" .
  cp "$backup/app-release.apk" "$backup/app.apk" mobile-apk/
  docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend frontend
  docker exec es_td_ngo_frontend nginx -s reload
  exit 1
}
trap rollback ERR
for name in es-td-ngo-3.7.37-80.apk app-release.apk app.apk; do
  cp "$stage/mobile-3.7.37-80.apk" "mobile-apk/$name.new"
  chmod 644 "mobile-apk/$name.new"
  mv "mobile-apk/$name.new" "mobile-apk/$name"
done
python3 - <<'PY'
from pathlib import Path
p=Path('docker-compose.audit.yml');s=p.read_text()
assert 'MOBILE_APP_VERSION: "3.7.36"' in s and 'MOBILE_APP_BUILD: "79"' in s
s=s.replace('MOBILE_APP_VERSION: "3.7.36"','MOBILE_APP_VERSION: "3.7.37"').replace('MOBILE_APP_BUILD: "79"','MOBILE_APP_BUILD: "80"').replace('es-td-ngo-3.7.36-79.apk','es-td-ngo-3.7.37-80.apk')
p.write_text(s)
PY
docker compose -f docker-compose.yml -f docker-compose.audit.yml config --quiet
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build backend frontend
docker exec es_td_ngo_frontend nginx -s reload
curl --fail --silent http://127.0.0.1:8000/health
curl --fail --silent https://neftcontrol.ru/api/mobile/version | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["version"]=="3.7.37" and str(d["build"])=="80"; print(d)'
echo "Mobile rollback: $backup"
