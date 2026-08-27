#!/bin/bash
docker exec es_td_ngo_frontend sh -c 'ls /usr/share/nginx/html/assets' | grep -iE 'mobile|index-' | head -40
echo '--- es-td-ngo files ---'
docker exec es_td_ngo_frontend sh -c 'grep -l es-td-ngo /usr/share/nginx/html/assets/*.js' 2>/dev/null | head -10
echo '--- 3.7.10 files ---'
docker exec es_td_ngo_frontend sh -c 'grep -l 3.7.10 /usr/share/nginx/html/assets/*.js' 2>/dev/null | head -10
echo '--- sample ---'
docker exec es_td_ngo_frontend sh -c 'grep -oh "es-td-ngo[a-zA-Z0-9._+-]*" /usr/share/nginx/html/assets/*.js' 2>/dev/null | sort -u | head -20
