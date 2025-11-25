@echo off
chcp 65001 >nul
echo ========================================
echo   Альтернативная проверка БД
echo   (запуск скрипта напрямую на сервере)
echo ========================================
echo.

echo [*] Копирование скриптов на сервер...
scp -o StrictHostKeyChecking=no backend/models.py root@5.129.203.182:/opt/es-td-ngo/backend/models.py
scp -o StrictHostKeyChecking=no backend/check_db.py root@5.129.203.182:/opt/es-td-ngo/backend/check_db.py
scp -o StrictHostKeyChecking=no backend/database.py root@5.129.203.182:/opt/es-td-ngo/backend/database.py

echo [✓] Файлы скопированы
echo.

echo [*] Запуск диагностики через docker-compose exec...
echo     (используем рабочую директорию контейнера)
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose exec -T backend sh -c 'cd /app && python check_db.py'"

echo.
echo [*] Проверка логов backend...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose logs backend --tail=30"
echo.
pause



