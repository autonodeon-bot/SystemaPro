@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
echo ========================================
echo   ДЕПЛОЙ СИСТЕМЫ 3.20 И МОБИЛЬНОГО ПРИЛОЖЕНИЯ 3.20
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "APP_DIR=/opt/es-td-ngo"
set "APK_FILE=mobile\build\app\outputs\flutter-apk\app-release.apk"
set "HOSTKEY=SHA256:0le6080AaJ2eq4TG//RZ7kRC5J7PyfsloqaGt2N7VQM"

echo [1/8] Проверка подключения к серверу...
plink -batch -hostkey %HOSTKEY% -ssh -pw "%PASSWORD%" "%SERVER%" "echo OK" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удается подключиться к серверу
    pause
    exit /b 1
)
echo   OK
echo.

echo [2/8] Сборка мобильного приложения (APK)...
if not exist "%APK_FILE%" (
    cd mobile
    call flutter pub get
    call flutter build apk --release
    cd ..
)
if not exist "%APK_FILE%" (
    echo   ОШИБКА: APK не собран. Запустите: cd mobile ^&^& flutter build apk --release
    pause
    exit /b 1
)
echo   APK: %APK_FILE%
echo.

echo [3/8] Загрузка backend на сервер...
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" backend\main.py "%SERVER%:%APP_DIR%/backend/"
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" backend\models.py "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" backend\report_generator.py "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" backend\word_generator.py "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" backend\report_utils.py "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" backend\requirements.txt "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" backend\Dockerfile "%SERVER%:%APP_DIR%/backend/" 2>nul
echo   OK
echo.

echo [4/8] Загрузка frontend и конфигурации на сервер...
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" package.json "%SERVER%:%APP_DIR%/"
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" package-lock.json "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" App.tsx "%SERVER%:%APP_DIR%/"
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" index.html "%SERVER%:%APP_DIR%/"
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" index.tsx "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" index.css "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" constants.ts "%SERVER%:%APP_DIR%/"
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" types.ts "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" vite.config.ts "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" tsconfig.json "%SERVER%:%APP_DIR%/"
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" tailwind.config.js "%SERVER%:%APP_DIR%/"
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" postcss.config.js "%SERVER%:%APP_DIR%/"
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" frontend.Dockerfile "%SERVER%:%APP_DIR%/"
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" docker-compose.yml "%SERVER%:%APP_DIR%/"
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" -r pages\* "%SERVER%:%APP_DIR%/pages/"
pscp -batch -pw "%PASSWORD%" -r nginx\* "%SERVER%:%APP_DIR%/nginx/"
if exist components pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" -r components\* "%SERVER%:%APP_DIR%/components/" 2>nul
if exist contexts pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" -r contexts\* "%SERVER%:%APP_DIR%/contexts/" 2>nul
echo   OK
echo.

echo [5/8] Загрузка APK на сервер...
plink -batch -hostkey %HOSTKEY% -ssh -pw "%PASSWORD%" "%SERVER%" "mkdir -p %APP_DIR%/mobile-apk"
pscp -batch -hostkey %HOSTKEY% -pw "%PASSWORD%" "%APK_FILE%" "%SERVER%:%APP_DIR%/mobile-apk/app-release.apk"
plink -batch -hostkey %HOSTKEY% -ssh -pw "%PASSWORD%" "%SERVER%" "chmod 644 %APP_DIR%/mobile-apk/app-release.apk"
echo   OK
echo.

echo [6/8] Пересборка контейнеров (backend, frontend) на сервере...
plink -batch -hostkey %HOSTKEY% -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR% && docker-compose build --no-cache backend frontend"
if errorlevel 1 (
    echo   ПРЕДУПРЕЖДЕНИЕ: возможна ошибка сборки. Проверьте логи выше.
)
echo.

echo [7/8] Перезапуск контейнеров...
plink -batch -hostkey %HOSTKEY% -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR% && docker-compose up -d backend frontend"
if errorlevel 1 (
    echo   ОШИБКА при запуске. Пробуем полный перезапуск...
    plink -batch -hostkey %HOSTKEY% -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR% && docker-compose up -d"
)
echo   OK
echo.

echo [8/8] Очистка кэша nginx...
plink -batch -hostkey %HOSTKEY% -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_frontend sh -c 'rm -rf /var/cache/nginx/* 2>/dev/null; nginx -s reload 2>/dev/null'" 2>nul
echo   OK
echo.

echo ========================================
echo   ПРОВЕРКА
echo ========================================
plink -batch -hostkey %HOSTKEY% -ssh -pw "%PASSWORD%" "%SERVER%" "docker ps | grep es_td_ngo"
echo.
plink -batch -hostkey %HOSTKEY% -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_backend grep -E 'version=|MOBILE_APP_VERSION|MOBILE_APP_BUILD' /app/main.py 2>/dev/null | head -3"
echo.
plink -batch -hostkey %HOSTKEY% -ssh -pw "%PASSWORD%" "%SERVER%" "ls -lh %APP_DIR%/mobile-apk/app-release.apk 2>/dev/null"
echo.

echo ========================================
echo   ДЕПЛОЙ 3.20 ЗАВЕРШЕН
echo ========================================
echo   Сайт:    http://5.129.203.182/
echo   API:     http://5.129.203.182:8000/
echo   APK:     http://5.129.203.182/mobile/app-release.apk
echo   Версия:  3.20.0 (build 20)
echo ========================================
echo.
pause
