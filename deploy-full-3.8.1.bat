@echo off
chcp 65001 >nul
echo ========================================
echo   ПОЛНЫЙ ДЕПЛОЙ ВЕРСИИ 3.8.1
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "APP_DIR=/opt/es-td-ngo"
set "APK_FILE=mobile\build\app\outputs\flutter-apk\app-release.apk"

echo [1/5] Загрузка APK на сервер
if exist "%APK_FILE%" (
    pscp -batch -pw "%PASSWORD%" "%APK_FILE%" "%SERVER%:%APP_DIR%/mobile-apk/app-release.apk"
    plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "chmod 644 %APP_DIR%/mobile-apk/app-release.apk"
    echo ✓ APK загружен
) else (
    echo ✗ APK не найден: %APK_FILE%
)
echo.

echo [2/5] Загрузка backend файлов
pscp -batch -pw "%PASSWORD%" backend\main.py "%SERVER%:%APP_DIR%/backend/"
echo ✓ Backend файлы загружены
echo.

echo [3/5] Загрузка frontend файлов
pscp -batch -pw "%PASSWORD%" -r pages\* "%SERVER%:%APP_DIR%/frontend/"
pscp -batch -pw "%PASSWORD%" -r src\* "%SERVER%:%APP_DIR%/frontend/"
pscp -batch -pw "%PASSWORD%" App.tsx "%SERVER%:%APP_DIR%/frontend/"
pscp -batch -pw "%PASSWORD%" package.json "%SERVER%:%APP_DIR%/frontend/"
pscp -batch -pw "%PASSWORD%" package-lock.json* "%SERVER%:%APP_DIR%/frontend/"
pscp -batch -pw "%PASSWORD%" vite.config.ts "%SERVER%:%APP_DIR%/frontend/"
pscp -batch -pw "%PASSWORD%" tsconfig.json "%SERVER%:%APP_DIR%/frontend/"
pscp -batch -pw "%PASSWORD%" index.html "%SERVER%:%APP_DIR%/frontend/"
pscp -batch -pw "%PASSWORD%" frontend.Dockerfile "%SERVER%:%APP_DIR%/frontend/"
pscp -batch -pw "%PASSWORD%" docker-compose.yml "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" -r nginx\* "%SERVER%:%APP_DIR%/nginx/"
echo ✓ Frontend файлы загружены
echo.

echo [4/5] Остановка контейнеров
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose down"
echo ✓ Контейнеры остановлены
echo.

echo [5/6] Пересборка контейнеров БЕЗ КЭША
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose build --no-cache --pull backend frontend"
echo ✓ Контейнеры пересобраны
echo.

echo [6/6] Запуск контейнеров
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose up -d"
echo ✓ Контейнеры запущены
echo.


echo ========================================
echo   ДЕПЛОЙ ЗАВЕРШЕН
echo ========================================
echo.
echo Версия системы: 3.8.1
echo APK доступен: http://5.129.203.182/mobile/app-release.apk
echo.
pause
