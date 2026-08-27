#!/bin/bash
python3 - <<'PY'
from pathlib import Path
p = Path('/tmp/build-apk-server.sh')
data = p.read_bytes().replace(b'\r\n', b'\n').replace(b'\r', b'\n')
p.write_bytes(data)
print('normalized', len(data))
PY
nohup bash /tmp/build-apk-server.sh > /tmp/build-apk.log 2>&1 &
echo APK_PID:$!
sleep 4
head -25 /tmp/build-apk.log
