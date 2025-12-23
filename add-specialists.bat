@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ДОБАВЛЕНИЕ СПЕЦИАЛИСТОВ НК В БАЗУ
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "CONTAINER_NAME=es_td_ngo_backend"

echo [1/3] Копирование скрипта на сервер
pscp -batch -pw "%PASSWORD%" backend\init_specialists.py "%SERVER%:/tmp/init_specialists.py" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать скрипт
    pause
    exit /b 1
)
echo Скрипт скопирован
echo.

echo [2/3] Копирование скрипта в контейнер
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker cp /tmp/init_specialists.py %CONTAINER_NAME%:/app/init_specialists.py 2>&1"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при копировании в контейнер
)
echo.

echo [3/3] Запуск скрипта в контейнере
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %CONTAINER_NAME% python3 /app/init_specialists.py 2>&1"
if errorlevel 1 (
    echo.
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при выполнении скрипта
    echo Проверьте логи контейнера
)
echo.

echo ========================================
echo   ВЫПОЛНЕНИЕ ЗАВЕРШЕНО
echo ========================================
echo.
echo Проверьте результат в интерфейсе:
echo   http://5.129.203.182/#/specialists
echo.
pause
endlocal
























