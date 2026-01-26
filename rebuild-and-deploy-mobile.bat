@echo off
chcp 65001 >nul
echo ========================================
echo   ПЕРЕСБОРКА И ДЕПЛОЙ МОБИЛЬНОГО ПРИЛОЖЕНИЯ 3.13.0
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "APP_DIR=/opt/es-td-ngo"
set "APK_FILE=mobile\build\app\outputs\flutter-apk\app-release.apk"

echo [1/5] Очистка проекта Flutter...
cd mobile
call flutter clean
echo   ✓ Проект очищен
echo.

echo [2/5] Обновление зависимостей...
call flutter pub get
echo   ✓ Зависимости обновлены
echo.

echo [3/5] Сборка APK с версией 3.13.0+14...
call flutter build apk --release
cd ..
if not exist "%APK_FILE%" (
    echo   ОШИБКА: APK не собран!
    pause
    exit /b 1
)
echo   ✓ APK собран: %APK_FILE%
echo.

echo [4/5] Загрузка APK на сервер...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "mkdir -p %APP_DIR%/mobile-apk; rm -f %APP_DIR%/mobile-apk/app-release.apk"
pscp -batch -pw "%PASSWORD%" "%APK_FILE%" "%SERVER%:%APP_DIR%/mobile-apk/app-release.apk"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "chmod 644 %APP_DIR%/mobile-apk/app-release.apk; ls -lh %APP_DIR%/mobile-apk/app-release.apk"
echo   ✓ APK загружен на сервер
echo.

echo [5/5] Обновление backend (версия и URL)...
pscp -batch -pw "%PASSWORD%" backend\main.py "%SERVER%:%APP_DIR%/backend/"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose restart backend"
echo   ✓ Backend обновлен
echo.

echo ========================================
echo   ДЕПЛОЙ ЗАВЕРШЕН
echo ========================================
echo.
echo Версия мобильного приложения: 3.13.0 (build 14)
echo APK доступен: http://5.129.203.182/mobile/app-release.apk
echo.
echo ВАЖНО: После установки обновления перезапустите приложение!
echo.
pause
