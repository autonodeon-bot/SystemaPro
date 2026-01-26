@echo off
chcp 65001 >nul
echo ========================================
echo   ПОЛНАЯ ОЧИСТКА И ПЕРЕСБОРКА 3.10.0
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "APP_DIR=/opt/es-td-ngo"
set "APK_FILE=mobile\build\app\outputs\flutter-apk\app-release.apk"

echo [1/9] Проверка и сборка APK...
if not exist "%APK_FILE%" (
    echo   APK не найден, собираю...
    cd mobile
    call flutter clean
    call flutter pub get
    call flutter build apk --release
    cd ..
    if not exist "%APK_FILE%" (
        echo   ОШИБКА: Не удалось собрать APK!
        pause
        exit /b 1
    )
)
echo   ✓ APK найден
echo.

echo [2/9] Полная остановка и удаление контейнеров...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose down -v"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker ps -a | grep es_td_ngo | awk '{print $1}' | xargs -r docker rm -f"
echo   ✓ Контейнеры остановлены и удалены
echo.

echo [3/9] Удаление старых Docker образов...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker images | grep es-td-ngo | awk '{print $3}' | grep -v SIZE | xargs -r docker rmi -f 2>&1"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker system prune -af --volumes"
echo   ✓ Старые образы удалены
echo.

echo [4/9] Очистка кэша сборки на сервере...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "rm -rf %APP_DIR%/.docker"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "rm -rf %APP_DIR%/mobile-apk/*"
echo   ✓ Кэш очищен
echo.

echo [5/9] Загрузка APK на сервер...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "mkdir -p %APP_DIR%/mobile-apk; rm -f %APP_DIR%/mobile-apk/app-release.apk"
pscp -batch -pw "%PASSWORD%" "%APK_FILE%" "%SERVER%:%APP_DIR%/mobile-apk/app-release.apk"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "chmod 644 %APP_DIR%/mobile-apk/app-release.apk"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "ls -lh %APP_DIR%/mobile-apk/app-release.apk"
echo   ✓ APK загружен
echo.

echo [6/9] Загрузка всех исходников в КОРЕНЬ проекта...
echo   Загрузка backend...
pscp -batch -pw "%PASSWORD%" backend\main.py "%SERVER%:%APP_DIR%/backend/"
pscp -batch -pw "%PASSWORD%" backend\models.py "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" backend\word_generator.py "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" backend\Dockerfile "%SERVER%:%APP_DIR%/backend/" 2>nul

echo   Загрузка frontend в корень (контекст сборки)...
pscp -batch -pw "%PASSWORD%" package.json "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" package-lock.json "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" App.tsx "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" -r pages\* "%SERVER%:%APP_DIR%/pages/"
if exist src (pscp -batch -pw "%PASSWORD%" -r src\* "%SERVER%:%APP_DIR%/src/" 2>nul)
if exist contexts (pscp -batch -pw "%PASSWORD%" -r contexts\* "%SERVER%:%APP_DIR%/contexts/" 2>nul)
if exist components (pscp -batch -pw "%PASSWORD%" -r components\* "%SERVER%:%APP_DIR%/components/" 2>nul)
pscp -batch -pw "%PASSWORD%" vite.config.ts "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" tsconfig.json "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" index.html "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" index.tsx "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" index.css "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" tailwind.config.js "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" postcss.config.js "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" constants.ts "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" types.ts "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" frontend.Dockerfile "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" docker-compose.yml "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" -r nginx\* "%SERVER%:%APP_DIR%/nginx/"
echo   ✓ Исходники загружены
echo.

echo [7/9] Создание директории для шаблонов и загрузка шаблона чертежа...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "mkdir -p %APP_DIR%/backend/reports/assets"
echo   ВАЖНО: Разместите файл vessel_template.png в %APP_DIR%/backend/reports/assets/
echo   на сервере вручную или используйте команду:
echo   pscp -batch -pw "%PASSWORD%" vessel_template.png "%SERVER%:%APP_DIR%/backend/reports/assets/"
echo.

echo [8/9] Пересборка контейнеров БЕЗ КЭША...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose build --no-cache --pull backend frontend"
echo   ✓ Контейнеры пересобраны
echo.

echo [9/9] Запуск контейнеров...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose up -d"
echo   ✓ Контейнеры запущены
echo.

echo [10/9] Очистка кэша nginx и перезапуск...
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
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_backend grep -E 'version=|MOBILE_APP_VERSION' /app/main.py | head -3"

echo.
echo Проверка версии в frontend:
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_frontend sh -c 'grep -r \"3.10.0\" /usr/share/nginx/html/*.html 2>/dev/null | head -2'"

echo.
echo Проверка доступности APK:
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "curl -I http://127.0.0.1/mobile/app-release.apk 2>&1 | head -3"

echo.
echo Проверка директории шаблонов:
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "ls -lh %APP_DIR%/backend/reports/assets/ 2>&1"

echo.
echo ========================================
echo   ДЕПЛОЙ ЗАВЕРШЕН
echo ========================================
echo.
echo Версия системы: 3.10.0
echo Версия мобильного приложения: 3.10.0 (build 8)
echo APK доступен: http://5.129.203.182/mobile/app-release.apk
echo.
echo ВАЖНО: 
echo 1. Обновите страницу через Ctrl+Shift+R (жесткая перезагрузка)
echo 2. Разместите шаблон чертежа vessel_template.png в %APP_DIR%/backend/reports/assets/
echo    на сервере для работы функции автоматической загрузки шаблонов
echo.
pause
