@echo off
chcp 65001 >nul
echo ========================================
echo   ЖЕСТКИЙ ПЕРЕЗАПУСК И ДЕПЛОЙ 3.11.0
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "APP_DIR=/opt/es-td-ngo"
set "APK_FILE=C:\DIANEKS\SYS\mobile\build\app\outputs\flutter-apk\app-release.apk"

echo [1/10] Проверка и сборка APK...
if not exist "%APK_FILE%" (
    echo   APK не найден, собираю...
    cd C:\DIANEKS\SYS\mobile
    call flutter clean
    call flutter pub get
    call flutter build apk --release
    cd C:\DIANEKS\SYS
    if not exist "%APK_FILE%" (
        echo   ОШИБКА: Не удалось собрать APK!
        pause
        exit /b 1
    )
)
echo   ✓ APK найден
echo.

echo [2/10] Полная остановка и удаление контейнеров...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose down -v"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker ps -a | grep es_td_ngo | awk '{print $1}' | xargs -r docker rm -f"
echo   ✓ Контейнеры остановлены и удалены
echo.

echo [3/10] Удаление старых Docker образов...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker images | grep es-td-ngo | awk '{print $3}' | grep -v SIZE | xargs -r docker rmi -f 2>&1"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker system prune -af --volumes"
echo   ✓ Старые образы удалены
echo.

echo [4/10] Очистка кэша сборки на сервере...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "rm -rf %APP_DIR%/.docker"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "rm -rf %APP_DIR%/mobile-apk/*"
echo   ✓ Кэш очищен
echo.

echo [5/10] Загрузка APK на сервер...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "mkdir -p %APP_DIR%/mobile-apk; rm -f %APP_DIR%/mobile-apk/app-release.apk"
pscp -batch -pw "%PASSWORD%" "%APK_FILE%" "%SERVER%:%APP_DIR%/mobile-apk/app-release.apk"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "chmod 644 %APP_DIR%/mobile-apk/app-release.apk"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "ls -lh %APP_DIR%/mobile-apk/app-release.apk"
echo   ✓ APK загружен
echo.

echo [6/10] Загрузка всех исходников backend...
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\backend\main.py" "%SERVER%:%APP_DIR%/backend/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\backend\models.py" "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\backend\word_generator.py" "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\backend\Dockerfile" "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\backend\requirements.txt" "%SERVER%:%APP_DIR%/backend/" 2>nul
echo   ✓ Backend файлы загружены
echo.

echo [7/10] Загрузка всех исходников frontend...
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\package.json" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\package-lock.json" "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\App.tsx" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" -r "C:\DIANEKS\SYS\pages\*" "%SERVER%:%APP_DIR%/pages/"
if exist "C:\DIANEKS\SYS\src" (pscp -batch -pw "%PASSWORD%" -r "C:\DIANEKS\SYS\src\*" "%SERVER%:%APP_DIR%/src/" 2>nul)
if exist "C:\DIANEKS\SYS\contexts" (pscp -batch -pw "%PASSWORD%" -r "C:\DIANEKS\SYS\contexts\*" "%SERVER%:%APP_DIR%/contexts/" 2>nul)
if exist "C:\DIANEKS\SYS\components" (pscp -batch -pw "%PASSWORD%" -r "C:\DIANEKS\SYS\components\*" "%SERVER%:%APP_DIR%/components/" 2>nul)
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\vite.config.ts" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\tsconfig.json" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\index.html" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\index.tsx" "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\index.css" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\tailwind.config.js" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\postcss.config.js" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\constants.ts" "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\types.ts" "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\frontend.Dockerfile" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\docker-compose.yml" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" -r "C:\DIANEKS\SYS\nginx\*" "%SERVER%:%APP_DIR%/nginx/"
echo   ✓ Frontend файлы загружены
echo.

echo [8/10] Копирование APK в nginx...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cp %APP_DIR%/mobile-apk/app-release.apk %APP_DIR%/nginx/html/mobile/app-release.apk"
echo   ✓ APK скопирован в nginx
echo.

echo [9/10] Пересборка контейнеров БЕЗ КЭША...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose build --no-cache --pull backend frontend"
echo   ✓ Контейнеры пересобраны
echo.

echo [10/10] Запуск контейнеров...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose up -d"
echo   ✓ Контейнеры запущены
echo.

echo [11/10] Очистка кэша nginx и перезапуск...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_frontend sh -c 'rm -rf /var/cache/nginx/*; nginx -s reload'" 2>nul
echo   ✓ Кэш nginx очищен
echo.

echo ========================================
echo   ПРОВЕРКА РЕЗУЛЬТАТА
echo ========================================
echo.

echo Проверка контейнеров:
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker ps | grep es_td_ngo"

echo.
echo Проверка APK файла:
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "ls -lh %APP_DIR%/mobile-apk/app-release.apk"

echo.
echo Проверка версии в backend:
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_backend grep -E 'version=|MOBILE_APP_VERSION|MOBILE_APP_BUILD' /app/main.py | head -3"

echo.
echo Проверка доступности APK:
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "curl -I http://127.0.0.1/mobile/app-release.apk 2>&1 | head -3"

echo.
echo ========================================
echo   ДЕПЛОЙ ЗАВЕРШЕН
echo ========================================
echo.
echo Версия системы: 3.11.0
echo Версия мобильного приложения: 3.11.0 (build 9)
echo APK доступен: http://5.129.203.182/mobile/app-release.apk
echo.
echo ВАЖНО: 
echo 1. Обновите страницу через Ctrl+Shift+R (жесткая перезагрузка)
echo 2. Проверьте версию в интерфейсе
echo.
pause
