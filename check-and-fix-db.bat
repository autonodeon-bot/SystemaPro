@echo off
chcp 65001 >nul
echo ========================================
echo   Проверка и исправление базы данных
echo ========================================
echo.

echo [*] Копирование скриптов на сервер...
echo.

REM Копирование models.py
scp -o StrictHostKeyChecking=no backend/models.py root@5.129.203.182:/opt/es-td-ngo/backend/models.py
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать models.py
    pause
    exit /b 1
)

REM Копирование check_db.py
scp -o StrictHostKeyChecking=no backend/check_db.py root@5.129.203.182:/opt/es-td-ngo/backend/check_db.py
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать check_db.py
    pause
    exit /b 1
)

echo [✓] Файлы скопированы
echo.

echo [*] Копирование check_db.py в контейнер...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker cp backend/check_db.py es_td_ngo_backend:/app/check_db.py"
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать check_db.py в контейнер
    pause
    exit /b 1
)

echo [*] Копирование models.py в контейнер...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker cp backend/models.py es_td_ngo_backend:/app/models.py"
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать models.py в контейнер
    pause
    exit /b 1
)

echo [*] Запуск диагностики базы данных на сервере...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose exec -T backend python /app/check_db.py"
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось запустить диагностику
    pause
    exit /b 1
)

echo.
echo [*] Проверка логов backend...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose logs backend --tail=30"
echo.
echo ========================================
echo   Готово!
echo ========================================
echo.
pause

