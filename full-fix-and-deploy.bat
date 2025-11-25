@echo off
chcp 65001 >nul
echo ========================================
echo   ПОЛНОЕ ИСПРАВЛЕНИЕ И РАЗВЕРТЫВАНИЕ
echo ========================================
echo.

echo [1] Копирование всех исправленных файлов на сервер...
echo.

REM Копирование backend/database.py
scp -o StrictHostKeyChecking=no backend/database.py root@5.129.203.182:/opt/es-td-ngo/backend/database.py
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать database.py
    pause
    exit /b 1
)

REM Копирование backend/main.py
scp -o StrictHostKeyChecking=no backend/main.py root@5.129.203.182:/opt/es-td-ngo/backend/main.py
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать main.py
    pause
    exit /b 1
)

REM Копирование backend/models.py
scp -o StrictHostKeyChecking=no backend/models.py root@5.129.203.182:/opt/es-td-ngo/backend/models.py
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать models.py
    pause
    exit /b 1
)

REM Копирование docker-compose.yml
scp -o StrictHostKeyChecking=no docker-compose.yml root@5.129.203.182:/opt/es-td-ngo/docker-compose.yml
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать docker-compose.yml
    pause
    exit /b 1
)

echo [✓] Файлы скопированы
echo.

echo [2] Пересборка и перезапуск backend...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose up -d --build backend"
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось пересобрать backend
    pause
    exit /b 1
)

echo [✓] Backend пересобран и перезапущен
echo.

echo [3] Ожидание запуска контейнера (10 секунд)...
timeout /t 10 /nobreak >nul

echo [4] Копирование check_db.py в контейнер...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker cp backend/check_db.py es_td_ngo_backend:/app/check_db.py 2>nul"
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker cp backend/models.py es_td_ngo_backend:/app/models.py 2>nul"

echo [5] Запуск диагностики и создание тестовых данных...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose exec -T backend python /app/check_db.py 2>&1"
echo.

echo [6] Проверка работы API...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "curl -s http://localhost:8000/health"
echo.
echo.

echo [7] Проверка API /api/equipment...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "curl -s http://localhost:8000/api/equipment | head -c 300"
echo.
echo.

echo [8] Последние логи backend...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose logs backend --tail=20"
echo.

echo ========================================
echo   ГОТОВО!
echo ========================================
echo.
echo Проверьте работу мобильного приложения.
echo Если ошибка осталась, запустите: diagnose-server.bat
echo.
pause



