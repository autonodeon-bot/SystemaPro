#!/usr/bin/env bash
set -Eeuo pipefail
docker network create --internal systemapro-deps-test-20261103
docker run -d --name systemapro-deps-db-20261103 --network systemapro-deps-test-20261103 --tmpfs /var/lib/postgresql -e POSTGRES_USER=upgrade_test -e POSTGRES_PASSWORD=disposable_upgrade_test -e POSTGRES_DB=systemapro_upgrade_test public.ecr.aws/docker/library/postgres:18
for n in {1..30}; do docker exec systemapro-deps-db-20261103 pg_isready -U upgrade_test -d systemapro_upgrade_test && break; sleep 1; done
docker run -d --name systemapro-deps-api-20261103 --network systemapro-deps-test-20261103 --tmpfs /app/uploads --tmpfs /app/reports -e APP_ENV=test -e DB_HOST=systemapro-deps-db-20261103 -e DB_USER=upgrade_test -e DB_PASS=disposable_upgrade_test -e DB_NAME=systemapro_upgrade_test -e DB_SSLMODE=disable -e JWT_SECRET_KEY=disposable-upgrade-test-key-20261103 systemapro-backend:dependencies-20261103
for n in {1..60}; do docker exec systemapro-deps-api-20261103 python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')" 2>/dev/null && break; sleep 1; done
docker cp /opt/es-td-ngo/dependency-stage-20261103/smoke-dependencies-20261103.py systemapro-deps-api-20261103:/app/smoke_upgrade.py
docker exec systemapro-deps-api-20261103 python -u /app/smoke_upgrade.py
