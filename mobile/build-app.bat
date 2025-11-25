@echo off
chcp 65001 >nul
echo ========================================
echo   Сборка мобильного приложения ЕС ТД НГО
echo ========================================
echo.

REM Проверка наличия Flutter
where flutter >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Flutter не найден в PATH
    echo.
    echo Пожалуйста, установите Flutter:
    echo 1. Скачайте с https://flutter.dev/docs/get-started/install/windows
    echo 2. Распакуйте в C:\src\flutter
    echo 3. Добавьте C:\src\flutter\bin в PATH
    echo 4. Перезапустите командную строку
    echo.
    echo Или используйте установщик Flutter SDK
    echo.
    pause
    exit /b 1
)

echo [✓] Flutter найден
echo.

REM Переход в папку mobile
cd /d "%~dp0"
echo [*] Текущая директория: %CD%
echo.

REM Проверка версии Flutter
echo [*] Проверка версии Flutter...
flutter --version
echo.

REM Установка зависимостей
echo [*] Установка зависимостей...
flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось установить зависимости
    pause
    exit /b 1
)
echo [✓] Зависимости установлены
echo.

REM Проверка устройств
echo [*] Проверка доступных устройств...
flutter devices
echo.

REM Очистка предыдущих сборок
echo [*] Очистка предыдущих сборок...
flutter clean
echo.

REM Установка зависимостей после очистки
echo [*] Повторная установка зависимостей...
flutter pub get
echo.

REM Сборка APK
echo [*] Начинаю сборку APK (Release)...
echo Это может занять несколько минут...
echo.
flutter build apk --release
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ОШИБКА] Сборка не удалась
    echo Проверьте ошибки выше
    pause
    exit /b 1
)

echo.
echo ========================================
echo   ✓ Сборка завершена успешно!
echo ========================================
echo.
echo APK файл находится в:
echo build\app\outputs\flutter-apk\app-release.apk
echo.
echo Размер файла:
if exist "build\app\outputs\flutter-apk\app-release.apk" (
    for %%A in ("build\app\outputs\flutter-apk\app-release.apk") do echo   %%~zA байт
)
echo.
pause




