@echo off
chcp 65001 >nul

set SERVER_IP=5.129.203.182
set SERVER_USER=root
set APP_DIR=/opt/es-td-ngo

echo ========================================
echo   Проверка статуса приложения
echo ========================================
echo.

where ssh >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] SSH не найден!
    pause
    exit /b 1
)

set "SSH_CMD=ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL %SERVER_USER%@%SERVER_IP%"

echo [СТАТУС КОНТЕЙНЕРОВ]
echo.
%SSH_CMD% "cd %APP_DIR% && docker-compose ps"

echo.
echo [ПОСЛЕДНИЕ ЛОГИ BACKEND]
echo.
%SSH_CMD% "cd %APP_DIR% && docker-compose logs --tail=20 backend"

echo.
echo [ПОСЛЕДНИЕ ЛОГИ FRONTEND]
echo.
%SSH_CMD% "cd %APP_DIR% && docker-compose logs --tail=20 frontend"

echo.
echo [ПРОВЕРКА ПОДКЛЮЧЕНИЯ К БД]
echo.
%SSH_CMD% "cd %APP_DIR% && docker-compose exec -T backend python -c \"import asyncio; from backend.database import engine; from sqlalchemy import text; asyncio.run((lambda: engine.begin()).__call__().__aenter__().execute(text('SELECT 1')))\" 2>&1 || echo Проверка подключения..."

echo.
echo [ПРОВЕРКА HEALTH ENDPOINT]
echo.
curl -s http://%SERVER_IP%:8000/health 2>nul || echo Не удалось подключиться к API

echo.
pause

