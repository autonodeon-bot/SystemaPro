@echo off
chcp 65001 >nul

set SERVER_IP=5.129.203.182
set SERVER_USER=root
set APP_DIR=/opt/es-td-ngo

echo ========================================
echo   Просмотр логов (Ctrl+C для выхода)
echo ========================================
echo.

where ssh >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] SSH не найден!
    pause
    exit /b 1
)

set "SSH_CMD=ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL %SERVER_USER%@%SERVER_IP%"

echo Выберите что просмотреть:
echo   1. Все логи
echo   2. Только backend
echo   3. Только frontend
echo.
set /p choice="Ваш выбор (1-3): "

if "%choice%"=="1" (
    %SSH_CMD% "cd %APP_DIR% && docker-compose logs -f"
) else if "%choice%"=="2" (
    %SSH_CMD% "cd %APP_DIR% && docker-compose logs -f backend"
) else if "%choice%"=="3" (
    %SSH_CMD% "cd %APP_DIR% && docker-compose logs -f frontend"
) else (
    echo Неверный выбор
    pause
    exit /b 1
)

