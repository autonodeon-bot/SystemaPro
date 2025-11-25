@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set SERVER_IP=5.129.203.182
set SERVER_USER=root
set APP_DIR=/opt/es-td-ngo

echo ========================================
echo   Диагностика проблем
echo ========================================
echo.

where ssh >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] SSH не найден!
    pause
    exit /b 1
)

set "SSH_CMD=ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL %SERVER_USER%@%SERVER_IP%"

echo [1] Проверка доступности сервера...
ping -n 1 %SERVER_IP% >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Сервер недоступен!
    pause
    exit /b 1
) else (
    echo [OK] Сервер доступен
)

echo.
echo [2] Проверка статуса контейнеров...
%SSH_CMD% "cd %APP_DIR% && docker-compose ps 2>/dev/null || echo Контейнеры не найдены"

echo.
echo [3] Проверка открытых портов...
%SSH_CMD% "netstat -tulpn | grep -E ':(80|8000)' || ss -tulpn | grep -E ':(80|8000)' || echo Не удалось проверить порты"

echo.
echo [4] Проверка firewall...
%SSH_CMD% "ufw status 2>/dev/null || iptables -L -n | grep -E '(80|8000)' || echo Firewall не настроен"

echo.
echo [5] Проверка логов backend (последние 20 строк)...
%SSH_CMD% "cd %APP_DIR% && docker-compose logs --tail=20 backend 2>/dev/null || echo Логи недоступны"

echo.
echo [6] Проверка логов frontend (последние 20 строк)...
%SSH_CMD% "cd %APP_DIR% && docker-compose logs --tail=20 frontend 2>/dev/null || echo Логи недоступны"

echo.
echo [7] Проверка наличия файлов проекта...
%SSH_CMD% "ls -la %APP_DIR%/docker-compose.yml 2>/dev/null && echo [OK] docker-compose.yml найден || echo [ОШИБКА] docker-compose.yml не найден"

echo.
echo [8] Проверка SSL сертификата...
%SSH_CMD% "ls -la %APP_DIR%/backend/certs/root.crt 2>/dev/null && echo [OK] SSL сертификат найден || echo [ПРЕДУПРЕЖДЕНИЕ] SSL сертификат не найден"

echo.
echo [9] Проверка Docker...
%SSH_CMD% "docker --version 2>/dev/null && echo [OK] Docker установлен || echo [ОШИБКА] Docker не установлен"
%SSH_CMD% "docker-compose --version 2>/dev/null && echo [OK] Docker Compose установлен || echo [ОШИБКА] Docker Compose не установлен"

echo.
echo [10] Попытка запуска контейнеров...
%SSH_CMD% "cd %APP_DIR% && docker-compose up -d 2>&1"

echo.
echo [11] Ожидание запуска (10 секунд)...
timeout /t 10 /nobreak >nul

echo.
echo [12] Финальная проверка статуса...
%SSH_CMD% "cd %APP_DIR% && docker-compose ps"

echo.
echo ========================================
echo   Рекомендации:
echo ========================================
echo.
echo Если контейнеры не запущены:
echo   1. Проверьте логи: view-logs.bat
echo   2. Перезапустите: restart.bat
echo   3. Пересоберите: quick-deploy.bat
echo.
echo Если порты закрыты:
echo   1. Откройте порты: ssh %SERVER_USER%@%SERVER_IP% "ufw allow 80/tcp && ufw allow 8000/tcp"
echo.
pause

