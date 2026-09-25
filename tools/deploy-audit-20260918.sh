#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/es-td-ngo
release=audit-20260918
backup="${AUDIT_BACKUP_DIR:-/opt/es-td-ngo-backups/${release}-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$backup"
chmod 700 "$backup"
docker inspect --format '{{.Image}}' es_td_ngo_backend > "$backup/backend-image"
docker inspect --format '{{.Image}}' es_td_ngo_frontend > "$backup/frontend-image"
docker tag "$(cat "$backup/backend-image")" "systemapro-backend:before-$release"
docker tag "$(cat "$backup/frontend-image")" "systemapro-frontend:before-$release"
if [ ! -s "$backup/server-files.tar.gz" ]; then
  tar --exclude=backend/__pycache__ -czf "$backup/server-files.tar.gz" backend docker-compose.yml nginx mobile-apk
fi
docker exec -i es_td_ngo_backend python - > "$backup/pg.env" <<'PY'
import os
env = {}
for key, source, default in [('PGHOST','DB_HOST','localhost'),('PGPORT','DB_PORT','5432'),('PGUSER','DB_USER','gen_user'),('PGPASSWORD','DB_PASS',''),('PGDATABASE','DB_NAME','default_db'),('PGSSLMODE','DB_SSLMODE','verify-full'),('PGSSLROOTCERT','DB_SSLCERT','/app/certs/root.crt')]:
    env[key] = os.getenv(source, default)
# Match the existing application's explicitly configured encryption-only mode.
# libpq otherwise treats require as verify-ca when an unrelated root.crt exists.
if env['PGSSLMODE'] == 'require':
    env['PGSSLROOTCERT'] = '/tmp/systemapro-no-configured-ca.crt'
for key, value in env.items():
    print(f'{key}={value}')
PY
chmod 600 "$backup/pg.env"
trap 'rm -f "$backup/pg.env"' EXIT
docker run --rm --env-file "$backup/pg.env" public.ecr.aws/docker/library/postgres:18 pg_dump -Fc > "$backup/database.dump"
rm -f "$backup/pg.env"
test -s "$backup/database.dump"
echo "BACKUP_OK $backup"
tar -xzf /opt/systemapro-audit-20260918.tar.gz -C /opt/es-td-ngo
docker build -f backend/Dockerfile -t systemapro-backend:$release .
docker build -f tools/frontend-audit.Dockerfile -t systemapro-frontend:$release .
cat > docker-compose.audit.yml <<EOF
services:
  backend:
    image: systemapro-backend:$release
  frontend:
    image: systemapro-frontend:$release
EOF
if ! docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build --wait --wait-timeout 180; then
  cat > docker-compose.audit.yml <<EOF
services:
  backend:
    image: systemapro-backend:before-$release
  frontend:
    image: systemapro-frontend:before-$release
EOF
  docker compose -f docker-compose.yml -f docker-compose.audit.yml up -d --no-build --wait --wait-timeout 180
  echo DEPLOY_FAILED_ROLLED_BACK
  exit 1
fi
docker exec es_td_ngo_backend python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/health').read().decode())"
docker exec es_td_ngo_backend soffice --version
docker tag systemapro-backend:$release es-td-ngo-backend:latest
docker tag systemapro-frontend:$release es-td-ngo-frontend:latest
docker compose -f docker-compose.yml -f docker-compose.audit.yml ps
echo DEPLOY_OK
