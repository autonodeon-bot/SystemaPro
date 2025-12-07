@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ОБНОВЛЕНИЕ BACKEND (AUTH)
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "CONTAINER_NAME=es_td_ngo_backend"

echo [1/2] Копирование main.py в контейнер
pscp -batch -pw "%PASSWORD%" backend\main.py "%SERVER%:/tmp/main.py" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать файл
    pause
    exit /b 1
)

plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker cp /tmp/main.py %CONTAINER_NAME%:/app/main.py 2>&1"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при копировании
)
echo Файл скопирован
echo.

echo [2/2] Перезапуск контейнера для применения изменений
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker restart %CONTAINER_NAME% 2>&1"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при перезапуске
) else (
    echo Контейнер перезапущен
)
echo.

echo ========================================
echo   ОБНОВЛЕНИЕ ЗАВЕРШЕНО
echo ========================================
echo.
pause
endlocal





