#!/bin/bash
set -e
docker exec es_td_ngo_frontend sh -c 'ls /usr/share/nginx/html/; ls /usr/share/nginx/html/assets 2>/dev/null | head'
echo '--- APK refs ---'
docker exec es_td_ngo_frontend grep -roh 'es-td-ngo[^"[:space:]]*apk' /usr/share/nginx/html --include='*.js' 2>/dev/null | sort -u | head -20 || true
echo '--- version refs ---'
docker exec es_td_ngo_frontend grep -roh '3\.7\.[0-9]*' /usr/share/nginx/html/assets --include='*.js' 2>/dev/null | sort -u | head -20 || true
