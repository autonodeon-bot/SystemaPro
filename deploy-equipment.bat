@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ДЕПЛОЙ ОБОРУДОВАНИЯ В БАЗУ ДАННЫХ
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "REMOTE_PATH=/opt/es-td-ngo"
set "BACKEND_CONTAINER=es_td_ngo_backend"

echo [1/5] Проверка подключения к серверу
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "echo OK" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удается подключиться к серверу
    pause
    exit /b 1
)
echo Подключение установлено
echo.

echo [2/6] Копирование скриптов и models.py
pscp -batch -pw "%PASSWORD%" backend\init_test_equipment.py backend\models.py backend\create_workshops_tables.py "%SERVER%:/tmp/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать файлы
    pause
    exit /b 1
)
echo Файлы скопированы
echo.

echo [3/6] Копирование файлов в контейнер
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker cp /tmp/init_test_equipment.py %BACKEND_CONTAINER%:/app/init_test_equipment.py 2>&1 && docker cp /tmp/models.py %BACKEND_CONTAINER%:/app/models.py 2>&1 && docker cp /tmp/create_workshops_tables.py %BACKEND_CONTAINER%:/app/create_workshops_tables.py 2>&1"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при копировании в контейнер
    echo Проверьте, что контейнер запущен
) else (
    echo Файлы скопированы в контейнер
)
echo.

echo [4/6] Создание таблиц workshops и workshop_engineer_access
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %BACKEND_CONTAINER% python /app/create_workshops_tables.py"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при создании таблиц
    echo Проверьте логи контейнера
) else (
    echo Таблицы созданы
)
echo.

echo [5/6] Запуск скрипта инициализации оборудования
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %BACKEND_CONTAINER% python /app/init_test_equipment.py"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при создании оборудования
    echo Проверьте логи контейнера: docker logs %BACKEND_CONTAINER%
) else (
    echo ✅ Оборудование успешно добавлено в БД!
)
echo.

echo [6/6] Перезапуск backend контейнера (опционально)
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker restart %BACKEND_CONTAINER%" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось перезапустить контейнер
) else (
    echo Backend контейнер перезапущен
)
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
echo Должно быть создано:
echo   - 25 единиц тестового оборудования
echo   - Распределено по 7 цехам на 3 предприятиях
echo.
pause
endlocal

