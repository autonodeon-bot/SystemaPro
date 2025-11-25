@echo off
chcp 65001 >nul
echo ========================================
echo   Установка Flutter SDK для Windows
echo ========================================
echo.

REM Проверка наличия Flutter
where flutter >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [✓] Flutter уже установлен
    flutter --version
    echo.
    echo Flutter найден в системе. Продолжить установку? (Y/N)
    set /p continue=
    if /i not "%continue%"=="Y" exit /b 0
)

echo [*] Инструкция по установке Flutter:
echo.
echo 1. Скачайте Flutter SDK:
echo    https://docs.flutter.dev/get-started/install/windows
echo.
echo 2. Распакуйте архив в C:\src\flutter
echo    (или другую папку без пробелов в пути)
echo.
echo 3. Добавьте Flutter в PATH:
echo    - Откройте "Переменные среды"
echo    - Найдите переменную PATH
echo    - Добавьте: C:\src\flutter\bin
echo.
echo 4. Перезапустите командную строку
echo.
echo 5. Выполните: flutter doctor
echo.
echo ========================================
echo   Альтернативный способ (Git)
echo ========================================
echo.
echo Если установлен Git, можно клонировать:
echo.
echo   cd C:\src
echo   git clone https://github.com/flutter/flutter.git -b stable
echo   setx PATH "%PATH%;C:\src\flutter\bin"
echo.
echo ========================================
echo.
echo Открыть страницу загрузки Flutter? (Y/N)
set /p open=
if /i "%open%"=="Y" (
    start https://docs.flutter.dev/get-started/install/windows
)
echo.
pause




