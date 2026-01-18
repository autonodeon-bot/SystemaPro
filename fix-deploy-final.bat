@echo off
chcp 65001 >nul
echo ========================================
echo   ИСПРАВЛЕНИЕ И ДЕПЛОЙ 3.8.1
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "APP_DIR=/opt/es-td-ngo"
set "APK_FILE=mobile\build\app\outputs\flutter-apk\app-release.apk"

echo [1/6] Останавливаю старые контейнеры
plink -batch -ssh -pw %PASSWORD% %SERVER% "cd %APP_DIR%; docker-compose down -v"
echo.

echo [2/6] Загружаю APK
if exist "%APK_FILE%" (
    pscp -batch -pw %PASSWORD% "%APK_FILE%" "%SERVER%:%APP_DIR%/mobile-apk/app-release.apk"
    plink -batch -ssh -pw %PASSWORD% %SERVER% "chmod 644 %APP_DIR%/mobile-apk/app-release.apk"
    echo APK загружен
) else (
    echo APK не найден, пропускаю
)
echo.

echo [3/6] Загружаю файлы проекта
pscp -batch -pw %PASSWORD% -r pages\* %SERVER%:%APP_DIR%/
pscp -batch -pw %PASSWORD% App.tsx %SERVER%:%APP_DIR%/
pscp -batch -pw %PASSWORD% package.json %SERVER%:%APP_DIR%/
pscp -batch -pw %PASSWORD% vite.config.ts %SERVER%:%APP_DIR%/
pscp -batch -pw %PASSWORD% tsconfig.json %SERVER%:%APP_DIR%/
pscp -batch -pw %PASSWORD% index.html %SERVER%:%APP_DIR%/
pscp -batch -pw %PASSWORD% frontend.Dockerfile %SERVER%:%APP_DIR%/
pscp -batch -pw %PASSWORD% docker-compose.yml %SERVER%:%APP_DIR%/
pscp -batch -pw %PASSWORD% backend\main.py %SERVER%:%APP_DIR%/backend/
echo Файлы загружены
echo.

echo [4/6] Пересобираю контейнеры БЕЗ КЭША
echo Это займет несколько минут...
plink -batch -ssh -pw %PASSWORD% %SERVER% "cd %APP_DIR%; docker-compose build --no-cache backend frontend"
echo.

echo [5/6] Запускаю контейнеры
plink -batch -ssh -pw %PASSWORD% %SERVER% "cd %APP_DIR%; docker-compose up -d"
echo.

echo [6/6] Проверяю статус
plink -batch -ssh -pw %PASSWORD% %SERVER% "cd %APP_DIR%; docker-compose ps"
plink -batch -ssh -pw %PASSWORD% %SERVER% "ls -lh %APP_DIR%/mobile-apk/app-release.apk"
echo.

echo ========================================
echo   ДЕПЛОЙ ЗАВЕРШЕН
echo ========================================
echo.
echo Версия системы: 3.8.1
echo APK: http://5.129.203.182/mobile/app-release.apk
echo.
echo ВАЖНО: Сделайте жесткое обновление (Ctrl+Shift+R)
echo.
pause
