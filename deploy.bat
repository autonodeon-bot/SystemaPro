@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo   ES TD NGO Platform - Автоматический деплой
echo ========================================
echo.

set SERVER_IP=5.129.203.182
set SERVER_USER=root
set APP_DIR=/opt/es-td-ngo
set SSH_PASSWORD=ydR9+CL3?S@dgH

:: Проверка наличия SSH
where ssh >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] SSH не найден в PATH
    echo.
    echo Установите один из вариантов:
    echo   1. Git for Windows (рекомендуется): https://git-scm.com/download/win
    echo   2. OpenSSH для Windows 10+
    echo   3. PuTTY
    echo.
    pause
    exit /b 1
)

:: Проверка наличия Docker (опционально, для локальной проверки)
where docker >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ПРЕДУПРЕЖДЕНИЕ] Docker не найден локально, но это не критично
    echo.
)

echo [1/6] Подключение к серверу...
echo.

:: Функция для выполнения SSH команд
set "SSH_CMD=ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL %SERVER_USER%@%SERVER_IP%"

echo [2/6] Настройка сервера...
echo.

%SSH_CMD% "bash -s" < setup-server-remote.sh
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось настроить сервер
    pause
    exit /b 1
)

echo [3/6] Скачивание SSL сертификата...
echo.

%SSH_CMD% "bash -c 'mkdir -p %APP_DIR%/backend/certs && if [ ! -f %APP_DIR%/backend/certs/root.crt ]; then curl -o %APP_DIR%/backend/certs/root.crt https://storage.yandexcloud.net/cloud-certs/CA.pem || echo [ПРЕДУПРЕЖДЕНИЕ] Не удалось скачать сертификат автоматически; fi && chmod 644 %APP_DIR%/backend/certs/root.crt'"
if %ERRORLEVEL% NEQ 0 (
    echo [ПРЕДУПРЕЖДЕНИЕ] Проблемы с SSL сертификатом, продолжаем...
)

echo [4/6] Создание архива проекта...
echo.

:: Создание временного архива
set TEMP_ARCHIVE=%TEMP%\es-td-ngo-deploy.tar.gz

:: Используем tar из Git Bash если доступен
where tar >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    tar -czf "%TEMP_ARCHIVE%" ^
        --exclude=node_modules ^
        --exclude=.git ^
        --exclude=dist ^
        --exclude=__pycache__ ^
        --exclude=*.pyc ^
        --exclude=.env* ^
        --exclude=backend/certs/*.crt ^
        . 2>nul
) else (
    echo [ОШИБКА] tar не найден. Установите Git for Windows или используйте WSL.
    pause
    exit /b 1
)

if not exist "%TEMP_ARCHIVE%" (
    echo [ОШИБКА] Не удалось создать архив
    pause
    exit /b 1
)

echo [5/6] Копирование файлов на сервер...
echo.

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL "%TEMP_ARCHIVE%" %SERVER_USER%@%SERVER_IP%:/tmp/
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать файлы
    del "%TEMP_ARCHIVE%" 2>nul
    pause
    exit /b 1
)

:: Распаковка на сервере
%SSH_CMD% "cd %APP_DIR% && tar -xzf /tmp/es-td-ngo-deploy.tar.gz && rm /tmp/es-td-ngo-deploy.tar.gz"
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось распаковать файлы на сервере
    del "%TEMP_ARCHIVE%" 2>nul
    pause
    exit /b 1
)

:: Удаление временного архива
del "%TEMP_ARCHIVE%" 2>nul

echo [6/6] Сборка и запуск контейнеров...
echo.

%SSH_CMD% "cd %APP_DIR% && docker-compose down 2>/dev/null || true"
%SSH_CMD% "cd %APP_DIR% && docker-compose build --no-cache"
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось собрать контейнеры
    pause
    exit /b 1
)

%SSH_CMD% "cd %APP_DIR% && docker-compose up -d"
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось запустить контейнеры
    pause
    exit /b 1
)

echo.
echo [ОЖИДАНИЕ] Ждем запуска сервисов...
timeout /t 10 /nobreak >nul

echo.
echo [ПРОВЕРКА] Статус контейнеров...
echo.

%SSH_CMD% "cd %APP_DIR% && docker-compose ps"

echo.
echo ========================================
echo   ✅ ДЕПЛОЙ ЗАВЕРШЕН УСПЕШНО!
echo ========================================
echo.
echo 🌐 Приложение доступно по адресам:
echo    Frontend:    http://%SERVER_IP%
echo    Backend API: http://%SERVER_IP%:8000
echo    Health:      http://%SERVER_IP%:8000/health
echo    API Docs:    http://%SERVER_IP%:8000/docs
echo.
echo 📋 Полезные команды:
echo    Логи:        ssh %SERVER_USER%@%SERVER_IP% "cd %APP_DIR% && docker-compose logs -f"
echo    Статус:      ssh %SERVER_USER%@%SERVER_IP% "cd %APP_DIR% && docker-compose ps"
echo    Перезапуск:  ssh %SERVER_USER%@%SERVER_IP% "cd %APP_DIR% && docker-compose restart"
echo.
pause

