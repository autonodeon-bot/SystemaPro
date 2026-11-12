#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/es-td-ngo/dependency-stage-20261103
tar -xzf dependency-release.tar.gz
cat > Backend.release.Dockerfile <<'EOF'
FROM systemapro-backend:security-20261103
COPY backend/requirements.txt backend/requirements.lock /app/
RUN pip uninstall -y python-jose ecdsa rsa pyasn1 && pip install --no-cache-dir --require-hashes -r /app/requirements.lock
COPY backend/auth.py backend/security.py /app/
COPY backend/report_forms/epb_vessel_layout.docx /app/report_forms/
COPY backend/report_forms/report_fields.json /app/report_forms/
EOF
cat > Frontend.release.Dockerfile <<'EOF'
FROM public.ecr.aws/docker/library/node:24.22.2-alpine AS builder
WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci --no-audit --fund=false
COPY . .
RUN node --version && npm run build
FROM systemapro-frontend:vessel-v2-3.7.32
COPY --from=builder /build/dist/ /usr/share/nginx/html/
EOF
cat > Backend.test.Dockerfile <<'EOF'
FROM systemapro-backend:dependencies-20261103
COPY backend/requirements-test.txt /tmp/requirements-test.txt
RUN pip freeze > /tmp/runtime-constraints.txt && pip install --no-cache-dir -r /tmp/requirements-test.txt -c /tmp/runtime-constraints.txt
COPY backend/tests /app/tests
COPY backend/conftest.py backend/pytest.ini /app/
COPY public/examples/visio-vessel.json /public/examples/visio-vessel.json
COPY test-fixtures/fixture.json /artifacts/vessel-constructor-v2/fixture.json
COPY test-fixtures/report_fields.json /mobile/assets/data/report_fields.json
COPY test-fixtures/report_fields.json /app/tests/mobile/assets/data/report_fields.json
EOF
docker build -f Backend.release.Dockerfile -t systemapro-backend:dependencies-20261103 .
docker build -f Frontend.release.Dockerfile -t systemapro-frontend:dependencies-20261103 .
docker build -f Backend.test.Dockerfile -t systemapro-backend:dependencies-test-20261103 .
docker run --rm --network none --env APP_ENV=test --env DB_SSLMODE=disable systemapro-backend:dependencies-test-20261103 python -m pytest tests -q --disable-warnings --tb=short
