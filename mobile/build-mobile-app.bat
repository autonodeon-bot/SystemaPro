@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   СБОРКА МОБИЛЬНОГО ПРИЛОЖЕНИЯ
echo   Flutter APK для Android
echo ========================================
echo.

cd /d "%~dp0"

echo [1/6] Проверка Flutter
flutter --version >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Flutter не установлен или не в PATH
    echo Установите Flutter: https://flutter.dev/docs/get-started/install
    pause
    exit /b 1
)
echo Flutter найден
echo.

echo [2/6] Очистка предыдущих сборок
flutter clean >nul 2>&1
echo Очистка завершена
echo.

echo [3/6] Получение зависимостей
flutter pub get
if errorlevel 1 (
    echo ОШИБКА: Не удалось получить зависимости
    pause
    exit /b 1
)
echo Зависимости установлены
echo.

echo [4/6] Генерация кода для Drift
flutter pub run build_runner build --delete-conflicting-outputs
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Ошибка при генерации кода Drift
    echo Продолжаем сборку...
)
echo.

echo [5/6] Проверка подключенных устройств
flutter devices
echo.

echo [6/6] Сборка APK
echo   Это может занять несколько минут...
flutter build apk --release
if errorlevel 1 (
    echo ОШИБКА: Не удалось собрать APK
    pause
    exit /b 1
)
echo.

echo ========================================
echo   СБОРКА ЗАВЕРШЕНА
echo ========================================
echo.
echo APK файл находится в:
echo   build\app\outputs\flutter-apk\app-release.apk
echo.
echo Размер файла:
for %%A in (build\app\outputs\flutter-apk\app-release.apk) do echo   %%~zA байт
echo.
echo Для установки на устройство:
echo   adb install build\app\outputs\flutter-apk\app-release.apk
echo.
pause
endlocal

