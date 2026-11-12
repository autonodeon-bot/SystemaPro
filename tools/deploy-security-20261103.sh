#!/usr/bin/env bash
set -Eeuo pipefail
# Run from a staging directory containing the three patched Python files.
stage=$(pwd)
root=/opt/es-td-ngo
backup="$root/security-backup-20261103-$(date -u +%H%M%S)"
image=systemapro-backend:security-20261103
base=$(docker inspect es_td_ngo_backend --format '{{.Image}}')
cd "$root"
# Refuse to overwrite a different deployment.
printf '%s\n' \
  'b741ff215bc304a4cab69442c3422f621aa8e65258ca1e1399dff22d88dd42f9  backend/auth_2fa_api.py' \
  'f9808e21e7d2a0dff02d2a44f3a570bfbf838c0e3214c414d35f0fbff89b861a  backend/auth_api.py' \
  'f41d7363a9c99a08914fc4964cde770b74bbd890a9a3da04068abf15980f9182  backend/observability.py' \
  '41747bab175ad582bc05e8897c953974d3066d762023fb252731e30d89365ef6  docker-compose.yml' | sha256sum -c -
mkdir -p "$backup/backend"
cp backend/auth_api.py backend/auth_2fa_api.py backend/observability.py "$backup/backend/"
cp docker-compose.yml docker-compose.audit.yml "$backup/"
docker tag "$base" systemapro-backend:before-security-20261103
printf 'FROM systemapro-backend:before-security-20261103\nCOPY auth_api.py auth_2fa_api.py observability.py /app/\n' > "$stage/Dockerfile"
docker build --network=none -t "$image" "$stage"
docker run --rm --network=none --entrypoint python "$image" -m py_compile /app/auth_api.py /app/auth_2fa_api.py /app/observability.py
rollback() {
  trap - ERR
  echo "Deployment failed; restoring $backup" >&2
  cp "$backup/backend/"*.py backend/
  cp "$backup/docker-compose.yml" "$backup/docker-compose.audit.yml" .
  docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-deps --no-build --force-recreate backend
  docker exec es_td_ngo_frontend nginx -s reload
  exit 1
}
trap rollback ERR
cp "$stage/auth_api.py" "$stage/auth_2fa_api.py" "$stage/observability.py" backend/
python3 - <<'PY'
from pathlib import Path
p = Path('docker-compose.yml')
s = p.read_text()
assert s.count('"8000:8000"') == 1
p.write_text(s.replace('"8000:8000"', '"127.0.0.1:8000:8000"'))
p = Path('docker-compose.audit.yml')
s = p.read_text()
assert s.count('systemapro-backend:vessel-v2-3.7.32') == 1
p.write_text(s.replace('systemapro-backend:vessel-v2-3.7.32', 'systemapro-backend:security-20261103'))
PY
docker compose -f docker-compose.yml -f docker-compose.audit.yml config --quiet
docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-deps --no-build --force-recreate backend
healthy=false
for attempt in $(seq 1 30); do
  if curl --silent --fail http://127.0.0.1:8000/health > "$backup/health-after.json"; then
    healthy=true
    break
  fi
  sleep 2
done
test "$healthy" = true
docker exec es_td_ngo_frontend nginx -t
docker exec es_td_ngo_frontend nginx -s reload
status=$(curl --silent --show-error -o "$backup/https-auth-after.json" -w '%{http_code}' https://neftcontrol.ru/api/auth/me)
test "$status" = 403 -o "$status" = 401
docker inspect es_td_ngo_backend --format '{{json .HostConfig.PortBindings}}'
echo "Deployed $image; rollback files: $backup"
trap - ERR
