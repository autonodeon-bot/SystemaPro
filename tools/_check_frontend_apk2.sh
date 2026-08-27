#!/bin/bash
docker exec es_td_ngo_frontend sh -c 'grep -rl "neftcontrol.ru/mobile\|MOBILE_APP\|es-td-ngo\|3.7.10\|3.7.11" /usr/share/nginx/html --include="*.js" --include="*.html" 2>/dev/null | head -30'
echo '---'
docker exec es_td_ngo_frontend sh -c 'grep -n "mobile/" /usr/share/nginx/html/assets/*Mobile* /usr/share/nginx/html/assets/index-*.js 2>/dev/null | head -20'
echo '--- files ---'
docker exec es_td_ngo_frontend sh -c 'ls /usr/share/nginx/html/assets | grep -iE "mobile|index|main|app" | head -40'
