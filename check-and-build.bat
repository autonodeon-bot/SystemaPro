@echo off
chcp 65001 >nul
echo ========================================
echo   ПРОВЕРКА И СБОРКА СИСТЕМЫ
echo ========================================
echo.

echo [1/3] Проверка скрипта инициализации пользователей...
cd /d "%~dp0"
if exist "backend\init_users.py" (
    echo [✓] Скрипт найден
    echo [*] Запуск инициализации пользователей...
    cd backend
    python init_users.py
    cd ..
    echo.
) else (
    echo [✗] Скрипт не найден
    echo.
)

echo [2/3] Проверка мобильного приложения...
if exist "mobile\build\app\outputs\flutter-apk\app-release.apk" (
    echo [✓] Старый APK найден
    for %%A in ("mobile\build\app\outputs\flutter-apk\app-release.apk") do (
        echo     Размер: %%~zA байт
        echo     Дата: %%~tA
    )
    echo [*] Пересборка APK...
) else (
    echo [*] APK не найден, создание нового...
)

cd mobile
call build-app.bat
cd ..

echo.
echo [3/3] Проверка результата...
if exist "mobile\build\app\outputs\flutter-apk\app-release.apk" (
    echo [✓] APK успешно собран!
    for %%A in ("mobile\build\app\outputs\flutter-apk\app-release.apk") do (
        echo     Размер: %%~zA байт
        echo     Путь: %%~fA
    )
) else (
    echo [✗] Ошибка: APK не найден после сборки
)

echo.
echo ========================================
echo   ЗАВЕРШЕНО
echo ========================================
pause


























