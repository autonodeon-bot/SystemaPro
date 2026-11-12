#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/es-td-ngo/assistant-v2-stage-20261103
tar -xzf assistant-release.tar.gz
cat > Backend.Dockerfile <<'EOF'
FROM systemapro-backend:assistant-20261103
COPY backend/main.py backend/report_assistant.py backend/report_assistant_api.py /app/
EOF
cat > Frontend.Dockerfile <<'EOF'
FROM systemapro-frontend:assistant-20261103
COPY dist/ /usr/share/nginx/html/
EOF
docker build -f Backend.Dockerfile -t systemapro-backend:assistant-v2-20261103 .
docker build -f Frontend.Dockerfile -t systemapro-frontend:assistant-v2-20261103 .
