#!/bin/bash
echo '=== version constants in active index ==='
docker exec es_td_ngo_frontend sh -c 'grep -oh "3\.7\.[0-9]*" /usr/share/nginx/html/assets/index-BICI_0z3.js | sort | uniq -c | sort -rn | head'
echo '=== build numbers near mobile ==='
docker exec es_td_ngo_frontend sh -c 'python3 - <<"PY"
from pathlib import Path
p = Path("/usr/share/nginx/html/assets/index-BICI_0z3.js")
t = p.read_text(encoding="utf-8", errors="ignore")
for needle in ["3.7.10", "3.7.11", "MOBILE", "47", "48", "es-td-ngo"]:
    print(needle, t.count(needle))
# find context around 3.7.
idx = 0
n = 0
while n < 8:
    i = t.find("3.7.", idx)
    if i < 0: break
    print("---", repr(t[max(0,i-40):i+60]))
    idx = i + 4
    n += 1
PY'
