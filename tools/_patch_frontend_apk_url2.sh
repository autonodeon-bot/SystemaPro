#!/bin/bash
echo '=== index.html script refs ==='
docker exec es_td_ngo_frontend sh -c 'grep -oE "assets/[^\"]+" /usr/share/nginx/html/index.html | head -30'
echo '=== MobileApp apk urls ==='
for f in MobileApp--x4XaQjj.js MobileApp-BgpRvYlm.js MobileApp-CF7WeEMu.js MobileApp-Cf_N-WPa.js MobileApp-oxC111Gh.js MobileApp-zfB8ybkp.js; do
  echo "-- $f --"
  docker exec es_td_ngo_frontend sh -c "grep -oh 'https://[^\"]*apk\|es-td-ngo[^\"]*apk\|3\.7\.[0-9]*' /usr/share/nginx/html/assets/$f" 2>/dev/null | sort -u | head -20
done
echo '=== patch all MobileApp + index with 3.7.11-48 ==='
docker exec es_td_ngo_frontend sh -c '
cd /usr/share/nginx/html/assets
for f in MobileApp-*.js index-*.js; do
  [ -f "$f" ] || continue
  if grep -q "es-td-ngo\|3.7.10\|/mobile/" "$f" 2>/dev/null; then
    sed -i "s|es-td-ngo-3\.7\.[0-9]*-[0-9]*\.apk|es-td-ngo-3.7.11-48.apk|g" "$f"
    sed -i "s|es-td-ngo-mobile-3\.[0-9.]*-[0-9]*\.apk|es-td-ngo-3.7.11-48.apk|g" "$f"
    sed -i "s|3\.7\.10|3.7.11|g" "$f"
    echo patched:$f
  fi
done
'
docker exec es_td_ngo_frontend nginx -s reload
echo DONE
for f in MobileApp-*.js; do :; done
docker exec es_td_ngo_frontend sh -c 'grep -oh "es-td-ngo[a-zA-Z0-9._+-]*apk\|3\.7\.1[0-9]" /usr/share/nginx/html/assets/MobileApp-*.js' 2>/dev/null | sort -u
