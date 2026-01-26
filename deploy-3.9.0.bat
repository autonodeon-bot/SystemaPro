@echo off
chcp 65001 >nul
echo ========================================
echo   ДЕПЛОЙ ВЕРСИИ 3.9.0
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "APP_DIR=/opt/es-td-ngo"

echo [1/7] Очистка проекта Flutter...
cd mobile
call flutter clean
echo   ✓ Проект очищен
echo.

echo [2/7] Обновление зависимостей...
call flutter pub get
echo   ✓ Зависимости обновлены
echo.

echo [3/7] Сборка APK с версией 3.9.0+7...
call flutter build apk --release
cd ..
set "APK_FILE=mobile\build\app\outputs\flutter-apk\app-release.apk"
if not exist "%APK_FILE%" (
    echo   ОШИБКА: APK не собран!
    pause
    exit /b 1
)
echo   ✓ APK собран: %APK_FILE%
echo.

echo [4/7] Остановка старых контейнеров...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose down"
echo   ✓ Контейнеры остановлены
echo.

echo [5/7] Загрузка файлов на сервер...
pscp -batch -pw "%PASSWORD%" backend\main.py "%SERVER%:%APP_DIR%/backend/"
pscp -batch -pw "%PASSWORD%" pages\*.tsx "%SERVER%:%APP_DIR%/pages/"
pscp -batch -pw "%PASSWORD%" App.tsx "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" package.json "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" contexts\ThemeContext.tsx "%SERVER%:%APP_DIR%/contexts/"
pscp -batch -pw "%PASSWORD%" index.tsx "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" index.css "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" tailwind.config.js "%SERVER%:%APP_DIR%/"
echo   ✓ Файлы загружены
echo.

echo [6/7] Загрузка APK на сервер...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "mkdir -p %APP_DIR%/mobile-apk; rm -f %APP_DIR%/mobile-apk/app-release.apk"
pscp -batch -pw "%PASSWORD%" "%APK_FILE%" "%SERVER%:%APP_DIR%/mobile-apk/app-release.apk"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "chmod 644 %APP_DIR%/mobile-apk/app-release.apk; ls -lh %APP_DIR%/mobile-apk/app-release.apk"
echo   ✓ APK загружен на сервер
echo.

echo [7/7] Пересборка и запуск контейнеров...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose build --no-cache backend frontend"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose up -d"
echo   ✓ Контейнеры пересобраны и запущены
echo.

echo ========================================
echo   ДЕПЛОЙ ЗАВЕРШЕН
echo ========================================
echo.
echo Версия системы: 3.9.0
echo Версия мобильного приложения: 3.9.0 (build 7)
echo APK доступен: http://5.129.203.182/mobile/app-release.apk
echo.
echo ВАЖНО: После установки обновления перезапустите приложение!
echo.
pause
