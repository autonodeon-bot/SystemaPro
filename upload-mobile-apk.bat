@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ЗАГРУЗКА МОБИЛЬНОГО ПРИЛОЖЕНИЯ
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "APK_FILE=mobile\build\app\outputs\flutter-apk\app-release.apk"
set "REMOTE_PATH=/opt/es-td-ngo/frontend/dist/mobile"

echo [1/4] Проверка наличия APK файла
if not exist "%APK_FILE%" (
    echo ОШИБКА: APK файл не найден: %APK_FILE%
    echo Сначала соберите приложение: flutter build apk --release
    pause
    exit /b 1
)
echo APK файл найден
echo.

echo [2/4] Копирование APK на сервер
pscp -batch -pw "%PASSWORD%" "%APK_FILE%" "%SERVER%:/tmp/app-release.apk" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать APK на сервер
    pause
    exit /b 1
)
echo APK скопирован на сервер
echo.

echo [3/4] Создание директории для мобильного приложения на сервере
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "mkdir -p %REMOTE_PATH% 2>&1"
echo.

echo [4/4] Перемещение APK в директорию frontend
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "mv /tmp/app-release.apk %REMOTE_PATH%/app-release.apk 2>&1; chmod 644 %REMOTE_PATH%/app-release.apk 2>&1"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при перемещении файла
)
echo.

echo ========================================
echo   APK ЗАГРУЖЕН НА СЕРВЕР
echo ========================================
echo.
echo Файл доступен по адресу:
echo   http://5.129.203.182/mobile/app-release.apk
echo.
echo Теперь можно создать QR код для скачивания
echo.
pause
endlocal





