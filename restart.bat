@echo off
chcp 65001 >nul

set SERVER_IP=5.129.203.182
set SERVER_USER=root
set APP_DIR=/opt/es-td-ngo

echo ========================================
echo   Перезапуск приложения
echo ========================================
echo.

where ssh >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] SSH не найден!
    pause
    exit /b 1
)

set "SSH_CMD=ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL %SERVER_USER%@%SERVER_IP%"

echo Остановка контейнеров...
%SSH_CMD% "cd %APP_DIR% && docker-compose down"

echo.
echo Запуск контейнеров...
%SSH_CMD% "cd %APP_DIR% && docker-compose up -d"

echo.
echo ✅ Приложение перезапущено!
echo.
pause

