@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ДЕПЛОЙ ИЕРАРХИЧЕСКОЙ СИСТЕМЫ ДОСТУПА
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "REMOTE_PATH=/opt/es-td-ngo"
set "BACKEND_CONTAINER=es_td_ngo_backend"

echo [1/7] Проверка подключения к серверу
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "echo OK" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удается подключиться к серверу
    pause
    exit /b 1
)
echo Подключение установлено
echo.

echo [2/7] Копирование backend файлов
pscp -batch -pw "%PASSWORD%" backend\main.py backend\models.py backend\auth.py backend\create_branches_tables.py "%SERVER%:%REMOTE_PATH%/backend/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать backend файлы
    pause
    exit /b 1
)
echo Backend файлы скопированы
echo.

echo [3/7] Копирование frontend файлов
pscp -batch -pw "%PASSWORD%" pages\EquipmentManagement.tsx "%SERVER%:%REMOTE_PATH%/pages/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать frontend файлы
    pause
    exit /b 1
)
echo Frontend файлы скопированы
echo.

echo [4/7] Копирование файлов в backend контейнер
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker cp %REMOTE_PATH%/backend/main.py %BACKEND_CONTAINER%:/app/main.py 2>&1 && docker cp %REMOTE_PATH%/backend/models.py %BACKEND_CONTAINER%:/app/models.py 2>&1 && docker cp %REMOTE_PATH%/backend/auth.py %BACKEND_CONTAINER%:/app/auth.py 2>&1 && docker cp %REMOTE_PATH%/backend/create_branches_tables.py %BACKEND_CONTAINER%:/app/create_branches_tables.py 2>&1 && echo '✓ Backend файлы скопированы' || echo 'ОШИБКА: Не удалось скопировать backend файлы'"
echo.

echo [5/7] Создание таблиц филиалов и доступа
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %BACKEND_CONTAINER% python /app/create_branches_tables.py 2>&1"
echo.

echo [6/7] Перезапуск backend контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker restart %BACKEND_CONTAINER%" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось перезапустить backend
) else (
    echo Backend контейнер перезапущен
)
echo.

echo [7/7] Пересборка и перезапуск frontend
echo   Остановка старого frontend контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker stop es_td_ngo_frontend 2>/dev/null; docker rm -f es_td_ngo_frontend 2>/dev/null; cd %REMOTE_PATH% && docker-compose stop frontend 2>/dev/null; docker-compose rm -f frontend 2>/dev/null" >nul 2>&1
echo.

echo   Пересборка frontend образа БЕЗ КЭША
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %REMOTE_PATH% && docker-compose build --no-cache frontend 2>&1 | tail -15"
echo.

echo   Запуск нового frontend контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %REMOTE_PATH% && docker-compose up -d frontend 2>&1"
echo.

echo Ожидание запуска контейнеров (15 секунд)
timeout /t 15 /nobreak >nul
echo.

echo ========================================
echo   ДЕПЛОЙ ЗАВЕРШЕН
echo ========================================
echo.
echo Проверьте результат:
echo   http://5.129.203.182/#/equipment
echo.
echo Новый функционал:
echo   - Иерархическая структура: Enterprise ^> Branch ^> Workshop ^> EquipmentType ^> Equipment
echo   - Назначение доступа на любом уровне иерархии
echo   - Создание филиалов (Branch) между предприятиями и цехами
echo   - Объединение нескольких обследований в один технический отчет
echo.
pause
endlocal



