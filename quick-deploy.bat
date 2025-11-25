@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo   ES TD NGO Platform - Быстрый деплой
echo ========================================
echo.

set SERVER_IP=5.129.203.182
set SERVER_USER=root
set APP_DIR=/opt/es-td-ngo

:: Проверка SSH
where ssh >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] SSH не найден!
    echo Установите Git for Windows: https://git-scm.com/download/win
    pause
    exit /b 1
)

set "SSH_CMD=ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL %SERVER_USER%@%SERVER_IP%"

echo [1/5] Настройка сервера...
%SSH_CMD% "bash -s" < setup-server-remote.sh
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Ошибка настройки сервера
    pause
    exit /b 1
)

echo [2/5] Скачивание SSL сертификата...
%SSH_CMD% "bash -c 'mkdir -p %APP_DIR%/backend/certs && curl -o %APP_DIR%/backend/certs/root.crt https://storage.yandexcloud.net/cloud-certs/CA.pem 2>/dev/null || echo [ПРЕДУПРЕЖДЕНИЕ] Не удалось скачать сертификат; chmod 644 %APP_DIR%/backend/certs/root.crt 2>/dev/null || true'"

echo [3/5] Создание архива...
set TEMP_ARCHIVE=%TEMP%\es-td-ngo-deploy.tar.gz
where tar >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] tar не найден! Установите Git for Windows
    pause
    exit /b 1
)

tar -czf "%TEMP_ARCHIVE%" --exclude=node_modules --exclude=.git --exclude=dist --exclude=__pycache__ --exclude=*.pyc --exclude=.env* --exclude=backend/certs/*.crt . 2>nul
if not exist "%TEMP_ARCHIVE%" (
    echo [ОШИБКА] Не удалось создать архив
    pause
    exit /b 1
)

echo [4/5] Копирование файлов...
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "%TEMP_ARCHIVE%" %SERVER_USER%@%SERVER_IP%:/tmp/
%SSH_CMD% "cd %APP_DIR% && tar -xzf /tmp/es-td-ngo-deploy.tar.gz && rm /tmp/es-td-ngo-deploy.tar.gz"
del "%TEMP_ARCHIVE%" 2>nul

echo [5/5] Запуск контейнеров...
%SSH_CMD% "cd %APP_DIR% && docker-compose down 2>/dev/null || true"
%SSH_CMD% "cd %APP_DIR% && docker-compose build --no-cache"
%SSH_CMD% "cd %APP_DIR% && docker-compose up -d"

timeout /t 5 /nobreak >nul

echo.
echo ✅ ДЕПЛОЙ ЗАВЕРШЕН!
echo.
echo 🌐 Приложение: http://%SERVER_IP%
echo 📊 API: http://%SERVER_IP%:8000
echo.
pause

