@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ДЕПЛОЙ ВЕРСИИ 3.2.0 НА СЕРВЕР
echo   Обновление версий и дат (2025)
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "REMOTE_PATH=/opt/es-td-ngo"
set "BACKEND_CONTAINER=es_td_ngo_backend"

echo [1/8] Проверка подключения к серверу
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "echo OK" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удается подключиться к серверу
    pause
    exit /b 1
)
echo Подключение установлено
echo.

echo [2/8] Копирование backend файлов
pscp -batch -pw "%PASSWORD%" backend\main.py backend\models.py backend\auth.py backend\create_branches_tables.py "%SERVER%:%REMOTE_PATH%/backend/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать backend файлы
    pause
    exit /b 1
)
echo Backend файлы скопированы
echo.

echo [3/8] Копирование frontend файлов с обновленными версиями
pscp -batch -pw "%PASSWORD%" pages\EquipmentManagement.tsx pages\Changelog.tsx pages\Login.tsx pages\TechSpecs.tsx "%SERVER%:%REMOTE_PATH%/pages/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать frontend файлы
    pause
    exit /b 1
)
echo Frontend файлы скопированы
echo.

echo [4/8] Копирование CHANGELOG.md
pscp -batch -pw "%PASSWORD%" CHANGELOG.md "%SERVER%:%REMOTE_PATH%/" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось скопировать CHANGELOG.md
) else (
    echo CHANGELOG.md скопирован
)
echo.

echo [5/8] Копирование файлов в backend контейнер
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker cp %REMOTE_PATH%/backend/main.py %BACKEND_CONTAINER%:/app/main.py 2>&1 && docker cp %REMOTE_PATH%/backend/models.py %BACKEND_CONTAINER%:/app/models.py 2>&1 && docker cp %REMOTE_PATH%/backend/auth.py %BACKEND_CONTAINER%:/app/auth.py 2>&1 && docker cp %REMOTE_PATH%/backend/create_branches_tables.py %BACKEND_CONTAINER%:/app/create_branches_tables.py 2>&1 && echo '✓ Backend файлы скопированы' || echo 'ОШИБКА: Не удалось скопировать backend файлы'"
echo.

echo [6/8] Создание таблиц филиалов (если еще не созданы)
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %BACKEND_CONTAINER% python /app/create_branches_tables.py 2>&1 | tail -10"
echo.

echo [7/8] Перезапуск backend контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker restart %BACKEND_CONTAINER%" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось перезапустить backend
) else (
    echo Backend контейнер перезапущен
)
echo.

echo [8/8] Пересборка и перезапуск frontend
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
echo   ДЕПЛОЙ ВЕРСИИ 3.2.0 ЗАВЕРШЕН
echo ========================================
echo.
echo Проверьте результат:
echo   http://5.129.203.182/#/equipment
echo   http://5.129.203.182/#/changelog
echo.
echo Обновления:
echo   - Версия системы: 3.2.0 (2025-Q4)
echo   - Все даты обновлены на 2025 год
echo   - Иерархическая система доступа к оборудованию
echo   - Управление филиалами
echo   - Объединение обследований в отчеты
echo.
pause
endlocal



