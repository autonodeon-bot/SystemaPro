@echo off
chcp 65001 >nul
echo ========================================
echo  УВЕЛИЧЕНИЕ ВЕРСИИ МОБИЛЬНОГО ПРИЛОЖЕНИЯ
echo ========================================
echo.

set PUBSPEC_FILE=mobile\pubspec.yaml

if not exist "%PUBSPEC_FILE%" (
    echo Ошибка: Файл %PUBSPEC_FILE% не найден!
    pause
    exit /b 1
)

echo [*] Чтение текущей версии из %PUBSPEC_FILE%...

for /f "tokens=2 delims=: " %%a in ('findstr /C:"version:" "%PUBSPEC_FILE%"') do (
    set CURRENT_VERSION=%%a
)

echo Текущая версия: %CURRENT_VERSION%

REM Парсим версию (формат: X.Y.Z+BUILD)
for /f "tokens=1,2 delims=+" %%a in ("%CURRENT_VERSION%") do (
    set VERSION_PART=%%a
    set BUILD_PART=%%b
)

REM Увеличиваем build number
set /a NEW_BUILD=%BUILD_PART%+1
set NEW_VERSION=%VERSION_PART%+%NEW_BUILD%

echo Новая версия: %NEW_VERSION%

REM Заменяем версию в файле
powershell -Command "(Get-Content '%PUBSPEC_FILE%') -replace 'version: %CURRENT_VERSION%', 'version: %NEW_VERSION%' | Set-Content '%PUBSPEC_FILE%'"

echo.
echo [✓] Версия успешно обновлена!
echo.
echo Старая версия: %CURRENT_VERSION%
echo Новая версия:  %NEW_VERSION%
echo.
pause











