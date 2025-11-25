@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set SERVER_IP=5.129.203.182
set SERVER_USER=root
set APP_DIR=/opt/es-td-ngo

echo ========================================
echo   Исправление проблем деплоя
echo ========================================
echo.

where ssh >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] SSH не найден!
    pause
    exit /b 1
)

set "SSH_CMD=ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL %SERVER_USER%@%SERVER_IP%"

echo [1] Остановка всех контейнеров...
%SSH_CMD% "cd %APP_DIR% && docker-compose down 2>/dev/null || true"

echo.
echo [2] Очистка старых контейнеров и образов...
%SSH_CMD% "cd %APP_DIR% && docker-compose rm -f 2>/dev/null || true"
%SSH_CMD% "docker system prune -f 2>/dev/null || true"

echo.
echo [3] Проверка и открытие портов в firewall...
%SSH_CMD% "ufw allow 22/tcp 2>/dev/null || true"
%SSH_CMD% "ufw allow 80/tcp 2>/dev/null || true"
%SSH_CMD% "ufw allow 8000/tcp 2>/dev/null || true"
%SSH_CMD% "ufw --force enable 2>/dev/null || true"

echo.
echo [4] Проверка SSL сертификата...
%SSH_CMD% "bash -c 'mkdir -p %APP_DIR%/backend/certs && if [ ! -f %APP_DIR%/backend/certs/root.crt ]; then curl -o %APP_DIR%/backend/certs/root.crt https://storage.yandexcloud.net/cloud-certs/CA.pem || echo [ПРЕДУПРЕЖДЕНИЕ] Не удалось скачать; fi && chmod 644 %APP_DIR%/backend/certs/root.crt 2>/dev/null || true'"

echo.
echo [5] Проверка наличия docker-compose.yml...
%SSH_CMD% "test -f %APP_DIR%/docker-compose.yml && echo [OK] docker-compose.yml найден || (echo [ОШИБКА] docker-compose.yml не найден! Нужен полный деплой. && exit 1)"

echo.
echo [6] Пересборка контейнеров...
%SSH_CMD% "cd %APP_DIR% && docker-compose build --no-cache --pull"

if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось собрать контейнеры
    echo Попробуйте выполнить полный деплой: quick-deploy.bat
    pause
    exit /b 1
)

echo.
echo [7] Запуск контейнеров...
%SSH_CMD% "cd %APP_DIR% && docker-compose up -d"

if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось запустить контейнеры
    pause
    exit /b 1
)

echo.
echo [8] Ожидание запуска сервисов (15 секунд)...
timeout /t 15 /nobreak >nul

echo.
echo [9] Проверка статуса контейнеров...
%SSH_CMD% "cd %APP_DIR% && docker-compose ps"

echo.
echo [10] Проверка логов на ошибки...
%SSH_CMD% "cd %APP_DIR% && docker-compose logs --tail=10 backend | grep -i error || echo Ошибок в логах backend не найдено"
%SSH_CMD% "cd %APP_DIR% && docker-compose logs --tail=10 frontend | grep -i error || echo Ошибок в логах frontend не найдено"

echo.
echo [11] Проверка доступности портов...
%SSH_CMD% "netstat -tulpn | grep -E ':(80|8000)' || ss -tulpn | grep -E ':(80|8000)' || echo Не удалось проверить порты"

echo.
echo ========================================
echo   Проверка завершена!
echo ========================================
echo.
echo Попробуйте открыть в браузере:
echo   http://%SERVER_IP%
echo   http://%SERVER_IP%:8000/health
echo.
echo Если не работает, запустите: diagnose.bat
echo.
pause

