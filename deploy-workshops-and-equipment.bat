@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ДЕПЛОЙ ЦЕХОВ И ТЕСТОВОГО ОБОРУДОВАНИЯ
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "REMOTE_PATH=/opt/es-td-ngo"
set "BACKEND_CONTAINER=es_td_ngo_backend"

echo [1/6] Проверка подключения к серверу
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "echo OK" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удается подключиться к серверу
    pause
    exit /b 1
)
echo Подключение установлено
echo.

echo [2/6] Копирование backend файлов
pscp -batch -pw "%PASSWORD%" backend\models.py backend\main.py backend\auth.py "%SERVER%:%REMOTE_PATH%/backend/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать backend файлы
    pause
    exit /b 1
)
echo Backend файлы скопированы
echo.

echo [3/6] Копирование скриптов создания таблиц и данных
pscp -batch -pw "%PASSWORD%" backend\create_workshops_tables.py backend\init_test_equipment.py "%SERVER%:/app/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать скрипты
    pause
    exit /b 1
)
echo Скрипты скопированы
echo.

echo [4/6] Создание таблиц workshops и workshop_engineer_access
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %BACKEND_CONTAINER% python /app/create_workshops_tables.py"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при создании таблиц
    echo Проверьте логи контейнера
)
echo.

echo [5/6] Создание 20 тестовых единиц оборудования
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %BACKEND_CONTAINER% python /app/init_test_equipment.py"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при создании оборудования
    echo Проверьте логи контейнера
)
echo.

echo [6/6] Перезапуск backend контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker restart %BACKEND_CONTAINER%" >nul 2>&1
echo Backend контейнер перезапущен
echo.

echo Ожидание запуска контейнера (10 секунд)
timeout /t 10 /nobreak >nul
echo.

echo ========================================
echo   ДЕПЛОЙ ЗАВЕРШЕН
echo ========================================
echo.
echo Проверьте результат:
echo   http://5.129.203.182/#/equipment
echo.
echo Должны быть созданы:
echo   - Таблицы workshops и workshop_engineer_access
echo   - 20 тестовых единиц оборудования на нескольких предприятиях
echo.
pause
endlocal





















