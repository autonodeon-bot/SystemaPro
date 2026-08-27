#!/bin/bash
set -e
for p in /tmp/build-apk-server.sh /tmp/_start_apk_build.sh /tmp/_wait_apk_3710.sh; do
  python3 - <<PY
from pathlib import Path
p = Path("$p")
p.write_bytes(p.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n"))
print("normalized", p)
PY
done
docker cp /opt/es-td-ngo/backend/main.py es_td_ngo_backend:/app/main.py
docker restart es_td_ngo_backend
rm -rf /opt/es-td-ngo/mobile/build
bash /tmp/_start_apk_build.sh
