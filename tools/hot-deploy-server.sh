#!/bin/bash
set -e
cd /opt/es-td-ngo/backend
for f in *.py; do
  docker cp "$f" es_td_ngo_backend:/app/"$f"
done
docker restart es_td_ngo_backend
sleep 10
docker exec es_td_ngo_backend python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/health').read().decode())"
docker exec es_td_ngo_backend python -c "import main; print(main.app.version)"
docker cp /opt/es-td-ngo/dist-new/. es_td_ngo_frontend:/usr/share/nginx/html/
docker exec es_td_ngo_frontend nginx -s reload
echo FRONTEND_DEPLOYED
