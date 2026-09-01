#!/bin/bash
set -e
cd /opt/es-td-ngo
echo ENV
grep -E '^(APP_VERSION|MOBILE_APP_VERSION|MOBILE_APP_BUILD)=' .env
echo HEALTH
curl -fsS http://127.0.0.1:8000/health; echo
echo MARKERS
docker exec es_td_ngo_backend grep -c _paragraph_plain_text /app/form_template_filler.py
docker exec es_td_ngo_backend grep -c close_prev_as_portrait /app/form_template_filler.py
docker exec es_td_ngo_backend grep -c 'DIAGNOSTICS' /app/word_generator.py
echo MD5
md5sum backend/form_template_filler.py
docker exec es_td_ngo_backend md5sum /app/form_template_filler.py
echo SMOKE
docker cp /tmp/_smoke_scheme_landscape.py es_td_ngo_backend:/tmp/_smoke_scheme_landscape.py
docker exec es_td_ngo_backend python /tmp/_smoke_scheme_landscape.py
echo DBG
docker cp /tmp/_dbg_sec15.py es_td_ngo_backend:/tmp/_dbg_sec15.py
docker exec es_td_ngo_backend python /tmp/_dbg_sec15.py | tail -n 30
