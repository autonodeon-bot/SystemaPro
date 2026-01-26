@echo off
chcp 65001 >nul
echo ========================================
echo Жесткий редеплой версии 3.11.0
echo ========================================
echo.

echo [1/6] Копирование APK на сервер...
pscp -batch -pw "ydR9+CL3?S@dgH" "mobile\build\app\outputs\flutter-apk\app-release.apk" "root@5.129.203.182:/opt/es-td-ngo/mobile-apk/app-release.apk"
if %errorlevel% neq 0 (
    echo ОШИБКА: Не удалось скопировать APK
    pause
    exit /b 1
)
echo ✓ APK скопирован

echo.
echo [2/6] Остановка контейнеров...
plink -batch -ssh -pw "ydR9+CL3?S@dgH" "root@5.129.203.182" "cd /opt/es-td-ngo && docker-compose down"
if %errorlevel% neq 0 (
    echo ⚠ Предупреждение: Не удалось остановить контейнеры
)

echo.
echo [3/6] Удаление старых образов...
plink -batch -ssh -pw "ydR9+CL3?S@dgH" "root@5.129.203.182" "docker images -q es-td-ngo-backend es-td-ngo-frontend | ForEach-Object { docker rmi -f $_ } 2>$null"
plink -batch -ssh -pw "ydR9+CL3?S@dgH" "root@5.129.203.182" "docker system prune -f"

echo.
echo [4/6] Копирование файлов на сервер...
pscp -batch -pw "ydR9+CL3?S@dgH" -r "backend\*" "root@5.129.203.182:/opt/es-td-ngo/backend/"
pscp -batch -pw "ydR9+CL3?S@dgH" -r "pages\*" "root@5.129.203.182:/opt/es-td-ngo/frontend/src/pages/"
pscp -batch -pw "ydR9+CL3?S@dgH" -r "components\*" "root@5.129.203.182:/opt/es-td-ngo/frontend/src/components/"
pscp -batch -pw "ydR9+CL3?S@dgH" -r "contexts\*" "root@5.129.203.182:/opt/es-td-ngo/frontend/src/contexts/"
pscp -batch -pw "ydR9+CL3?S@dgH" "App.tsx" "root@5.129.203.182:/opt/es-td-ngo/frontend/src/"
pscp -batch -pw "ydR9+CL3?S@dgH" "package.json" "root@5.129.203.182:/opt/es-td-ngo/frontend/"
pscp -batch -pw "ydR9+CL3?S@dgH" "docker-compose.yml" "root@5.129.203.182:/opt/es-td-ngo/"
pscp -batch -pw "ydR9+CL3?S@dgH" "frontend.Dockerfile" "root@5.129.203.182:/opt/es-td-ngo/"

echo.
echo [5/6] Копирование APK в nginx...
plink -batch -ssh -pw "ydR9+CL3?S@dgH" "root@5.129.203.182" "cp /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/nginx/html/mobile/app-release.apk"

echo.
echo [6/6] Пересборка и запуск контейнеров...
plink -batch -ssh -pw "ydR9+CL3?S@dgH" "root@5.129.203.182" "cd /opt/es-td-ngo && docker-compose build --no-cache && docker-compose up -d"

echo.
echo ========================================
echo ✓ Редеплой завершен!
echo ========================================
echo.
echo Версия: 3.11.0
echo APK: es-td-ngo-mobile-3.11.0-9.apk
echo.
pause
