#!/bin/bash
# Простой скрипт деплоя для выполнения на сервере

APP_DIR=/opt/es-td-ngo

echo "========================================"
echo "  ДЕПЛОЙ СИСТЕМЫ"
echo "========================================"
echo

cd "$APP_DIR" || exit 1

echo "[1/4] Остановка старых контейнеров..."
docker compose down 2>/dev/null || docker-compose down 2>/dev/null

echo "[2/4] Сборка образов..."
docker compose build --no-cache || docker-compose build --no-cache

echo "[3/4] Запуск контейнеров..."
docker compose up -d || docker-compose up -d

echo "[4/4] Ожидание запуска сервисов..."
sleep 10

echo "Проверка статуса..."
docker compose ps || docker-compose ps

echo "Добавление тестовых данных..."
docker compose exec -T backend python test_data.py 2>/dev/null || docker-compose exec -T backend python test_data.py 2>/dev/null || echo "Тестовые данные уже существуют или ошибка"

echo
echo "========================================"
echo "  ДЕПЛОЙ ЗАВЕРШЕН!"
echo "========================================"
echo
echo "API: http://$(hostname -I | awk '{print $1}'):8000"
echo "Frontend: http://$(hostname -I | awk '{print $1}')"
echo
echo "Логи: docker compose logs -f backend"
