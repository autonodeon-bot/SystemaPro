#!/bin/bash
set -e
docker exec es_td_ngo_frontend sh -c '
cd /usr/share/nginx/html/assets
# Xh=version, Zh=build рядом в constants бандла
for f in index-*.js; do
  if grep -q "Xh=\"3.7.11\",Zh=\"47\"" "$f" 2>/dev/null; then
    sed -i "s/Xh=\"3.7.11\",Zh=\"47\"/Xh=\"3.7.11\",Zh=\"48\"/g" "$f"
    echo patched:$f
  fi
done
grep -oh "Xh=\"3.7[^\"]*\",Zh=\"[0-9]*\"" index-BICI_0z3.js | head -3
'
docker exec es_td_ngo_frontend nginx -s reload
echo OK
