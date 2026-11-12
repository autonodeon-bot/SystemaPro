#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/es-td-ngo/vessel-annotations-stage-20261103
tar -xzf vessel-annotations-release.tar.gz
cat > Backend.Dockerfile <<'EOF'
FROM systemapro-backend:assistant-v2-20261103
COPY backend/vessel_geometry_v2.py backend/vessel_annotations.py backend/mobile_stats_api.py /app/
EOF
cat > Frontend.Dockerfile <<'EOF'
FROM systemapro-frontend:assistant-v2-20261103
COPY dist/ /usr/share/nginx/html/
EOF
docker build -f Backend.Dockerfile -t systemapro-backend:vessel-annotations-20261103 .
docker build -f Frontend.Dockerfile -t systemapro-frontend:vessel-annotations-20261103 .
