#!/bin/bash
set -e
docker exec es_td_ngo_frontend sh -c 'cd /usr/share/nginx/html; for f in assets/*.js; do [ -f "$f" ] || continue; if grep -q "es-td-ngo-3.7" "$f" 2>/dev/null; then sed -i "s/es-td-ngo-3\.7\.[0-9]*-[0-9]*\.apk/es-td-ngo-3.7.11-48.apk/g; s/3\.7\.10/3.7.11/g; s/(build 47)/(build 48)/g" "$f"; echo patched:$f; fi; done; nginx -s reload'
echo FRONTEND_APK_LINK_UPDATED
docker exec es_td_ngo_frontend sh -c 'grep -oh "es-td-ngo-3\.7\.[0-9]*-[0-9]*\.apk" assets/*.js | sort -u | head -10'
