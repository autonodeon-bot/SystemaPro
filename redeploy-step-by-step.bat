@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "APP_DIR=/opt/es-td-ngo"
set "APK_FILE=mobile\build\app\outputs\flutter-apk\app-release.apk"

echo ========================================
echo   ПОЛНАЯ ПЕРЕСБОРКА 3.8.1
echo ========================================
echo.

REM Шаг 1: Сборка APK
echo [1] Сборка APK...
if not exist "%APK_FILE%" (
    cd mobile
    call flutter build apk --release
    cd ..
)
if exist "%APK_FILE%" (
    echo   [OK] APK собран
) else (
    echo   [ERROR] APK не собран!
    pause
    exit /b 1
)
echo.

REM Шаг 2: Остановка контейнеров
echo [2] Остановка контейнеров...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose down -v"
echo   [OK] Контейнеры остановлены
echo.

REM Шаг 3: Удаление образов
echo [3] Удаление старых образов...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker system prune -af --volumes"
echo   [OK] Образы удалены
echo.

REM Шаг 4: Загрузка APK
echo [4] Загрузка APK...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "mkdir -p %APP_DIR%/mobile-apk; rm -f %APP_DIR%/mobile-apk/app-release.apk"
pscp -batch -pw "%PASSWORD%" "%APK_FILE%" "%SERVER%:%APP_DIR%/mobile-apk/app-release.apk"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "chmod 644 %APP_DIR%/mobile-apk/app-release.apk"
echo   [OK] APK загружен
echo.

REM Шаг 5: Загрузка исходников
echo [5] Загрузка исходников...
pscp -batch -pw "%PASSWORD%" backend\main.py "%SERVER%:%APP_DIR%/backend/"
pscp -batch -pw "%PASSWORD%" package.json "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" App.tsx "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" -r pages\* "%SERVER%:%APP_DIR%/pages/"
pscp -batch -pw "%PASSWORD%" vite.config.ts "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" tsconfig.json "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" index.html "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" frontend.Dockerfile "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" docker-compose.yml "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" -r nginx\* "%SERVER%:%APP_DIR%/nginx/"
echo   [OK] Исходники загружены
echo.

REM Шаг 6: Пересборка
echo [6] Пересборка контейнеров (это займет время)...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose build --no-cache --pull backend frontend"
echo   [OK] Контейнеры пересобраны
echo.

REM Шаг 7: Запуск
echo [7] Запуск контейнеров...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose up -d"
echo   [OK] Контейнеры запущены
echo.

REM Шаг 8: Очистка кэша nginx
echo [8] Очистка кэша nginx...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_frontend sh -c 'rm -rf /var/cache/nginx/*; nginx -s reload'"
echo   [OK] Кэш очищен
echo.

echo ========================================
echo   ДЕПЛОЙ ЗАВЕРШЕН
echo ========================================
echo.
echo Версия: 3.8.1
echo APK: http://5.129.203.182/mobile/app-release.apk
echo.
echo Обновите страницу: Ctrl+Shift+R
echo.
pause
