@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ДЕПЛОЙ СИСТЕМЫ ДОСТУПА К ОБОРУДОВАНИЮ
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

echo [2/5] Копирование backend файлов
pscp -batch -pw "%PASSWORD%" backend\main.py backend\models.py backend\auth.py "%SERVER%:%REMOTE_PATH%/backend/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать backend файлы
    pause
    exit /b 1
)
echo Backend файлы скопированы
echo.

echo [3/5] Копирование frontend файлов
pscp -batch -pw "%PASSWORD%" pages\EquipmentManagement.tsx "%SERVER%:%REMOTE_PATH%/pages/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать frontend файлы
    pause
    exit /b 1
)
echo Frontend файлы скопированы
echo.

echo [4/5] Копирование файлов в контейнеры
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker cp %REMOTE_PATH%/backend/main.py %BACKEND_CONTAINER%:/app/main.py 2>&1 && docker cp %REMOTE_PATH%/backend/models.py %BACKEND_CONTAINER%:/app/models.py 2>&1 && docker cp %REMOTE_PATH%/backend/auth.py %BACKEND_CONTAINER%:/app/auth.py 2>&1 && echo '✓ Backend файлы скопированы' || echo 'ОШИБКА: Не удалось скопировать backend файлы'"
echo.

echo [5/5] Перезапуск контейнеров
echo   Перезапуск backend
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker restart %BACKEND_CONTAINER%" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось перезапустить backend
) else (
    echo Backend контейнер перезапущен
)
echo.

echo   Остановка и удаление старого frontend контейнера
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
echo Функционал:
echo   - Админ и мастер-оператор могут назначать доступ к цехам
echo   - Админ и мастер-оператор могут назначать доступ к конкретному оборудованию
echo   - Инженеры видят только доступное им оборудование в мобильном приложении
echo.
pause
endlocal

