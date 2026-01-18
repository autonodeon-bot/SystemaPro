@echo off
chcp 65001 >nul
echo ========================================
echo   ЗАГРУЗКА APK ДЛЯ ИСПРАВЛЕНИЯ 404
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "APK_FILE=mobile\build\app\outputs\flutter-apk\app-release.apk"
set "REMOTE_PATH=/opt/es-td-ngo/mobile-apk"

echo [1/3] Проверка наличия APK файла
if not exist "%APK_FILE%" (
    echo ОШИБКА: APK файл не найден: %APK_FILE%
    echo Сначала соберите приложение: flutter build apk --release
    pause
    exit /b 1
)
echo APK файл найден
echo.

echo [2/3] Копирование APK на сервер
pscp -batch -pw "%PASSWORD%" "%APK_FILE%" "%SERVER%:%REMOTE_PATH%/app-release.apk"
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать APK на сервер
    pause
    exit /b 1
)
echo APK скопирован на сервер
echo.

echo [3/3] Установка прав доступа
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "chmod 644 %REMOTE_PATH%/app-release.apk; ls -lh %REMOTE_PATH%/app-release.apk"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при установке прав
)
echo.

echo ========================================
echo   APK ЗАГРУЖЕН НА СЕРВЕР
echo ========================================
echo.
echo Файл доступен по адресу:
echo   http://5.129.203.182/mobile/app-release.apk
echo.
pause
