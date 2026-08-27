#!/bin/bash
docker exec es_td_ngo_frontend sh -c '
for f in /usr/share/nginx/html/assets/MobileApp-*.js /usr/share/nginx/html/assets/index-BICI_0z3.js; do
  echo "==== $f ===="
  grep -o ".\{30\}3\.7\.1[01].\{30\}" "$f" 2>/dev/null | head -5
  grep -o ".\{20\}\"47\".\{20\}" "$f" 2>/dev/null | head -5
  grep -o ".\{20\}\"48\".\{20\}" "$f" 2>/dev/null | head -5
done
'
