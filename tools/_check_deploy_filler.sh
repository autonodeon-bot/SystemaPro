#!/bin/bash
set -e
cd /opt/es-td-ngo
echo '=== ENV ==='
grep -E '^(APP_VERSION|MOBILE_APP_VERSION|MOBILE_APP_BUILD)=' .env || true
echo '=== HEALTH ==='
curl -fsS http://127.0.0.1:8000/health; echo
echo '=== CONTAINERS ==='
docker-compose ps
echo '=== HOST FILLER MARKERS ==='
grep -c '_insert_scheme_landscape_block' backend/form_template_filler.py || echo 0
grep -c '_landscape_block_start' backend/form_template_filler.py || echo 0
grep -c '_normalize_appendix_font' backend/form_template_filler.py || echo 0
grep -c '_fit_image_width_inches' backend/form_template_filler.py || echo 0
grep -n 'finalize_official_form\|_insert_schemes_and_photos\|_append_section_properties\|_insert_scheme_landscape' backend/form_template_filler.py | head -25
echo '=== CONTAINER FILLER MARKERS ==='
docker exec es_td_ngo_backend grep -c '_insert_scheme_landscape_block' /app/form_template_filler.py || echo 0
docker exec es_td_ngo_backend grep -c '_landscape_block_start' /app/form_template_filler.py || echo 0
docker exec es_td_ngo_backend grep -c '_normalize_appendix_font' /app/form_template_filler.py || echo 0
docker exec es_td_ngo_backend grep -c '_fit_image_width_inches' /app/form_template_filler.py || echo 0
docker exec es_td_ngo_backend grep -n 'finalize_official_form\|_insert_schemes_and_photos\|_append_section_properties\|_insert_scheme_landscape' /app/form_template_filler.py | head -25
echo '=== MTIMES ==='
ls -la --time-style=long-iso backend/form_template_filler.py backend/word_generator.py
docker exec es_td_ngo_backend ls -la --time-style=long-iso /app/form_template_filler.py /app/word_generator.py
echo '=== MD5 ==='
md5sum backend/form_template_filler.py
docker exec es_td_ngo_backend md5sum /app/form_template_filler.py
echo '=== WG PATH ==='
grep -n 'fill_vessel_form_to1\|_try_fill_official_form\|fill_generic' backend/word_generator.py | head -20
docker exec es_td_ngo_backend grep -n 'fill_vessel_form_to1\|_try_fill_official_form\|fill_generic' /app/word_generator.py | head -20
echo '=== IMAGE BUILT ==='
docker inspect es_td_ngo_backend --format '{{.Created}} {{.Image}}'
echo '=== LOCAL ORDER CHECK ==='
grep -n '_insert_schemes_and_photos\|finalize_official_form' backend/form_template_filler.py | head -10
docker exec es_td_ngo_backend grep -n '_insert_schemes_and_photos\|finalize_official_form' /app/form_template_filler.py | head -10
echo '=== REPORT FORMS TO-1 ==='
ls -la backend/report_forms/to-1* 2>/dev/null | head -5
docker exec es_td_ngo_backend ls -la /app/report_forms/to-1* 2>/dev/null | head -5
