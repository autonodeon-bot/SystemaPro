#!/bin/bash
echo "=== ПОЛНОЕ ОБНОВЛЕНИЕ СЕРВЕРА ==="
echo ""

cd /opt/es-td-ngo

echo "1. Проверяю версию в коде..."
grep "3\.[0-9]\.[0-9]" pages/TechSpecs.tsx | head -1
echo ""

echo "2. Останавливаю frontend..."
docker-compose stop frontend
docker-compose rm -f frontend
echo ""

echo "3. Пересобираю образ БЕЗ КЭША..."
docker-compose build --no-cache frontend
echo ""

echo "4. Запускаю frontend..."
docker-compose up -d frontend
sleep 10
echo ""

echo "5. Проверяю версию в собранном JS..."
JS_FILE=$(docker exec es_td_ngo_frontend sh -c 'ls /usr/share/nginx/html/assets/*.js 2>/dev/null | head -1')
if [ -n "$JS_FILE" ]; then
    echo "JS файл: $(basename $JS_FILE)"
    echo "Версии в JS:"
    docker exec es_td_ngo_frontend sh -c "grep -o '3\.[0-9]\.[0-9]' $JS_FILE | sort -u | head -5"
    echo ""
    if docker exec es_td_ngo_frontend sh -c "grep -q '3.1.0' $JS_FILE"; then
        echo "✓ Версия 3.1.0 НАЙДЕНА"
    else
        echo "✗ Версия 3.1.0 НЕ найдена"
    fi
else
    echo "JS файл не найден"
fi

echo ""
echo "Готово!"










