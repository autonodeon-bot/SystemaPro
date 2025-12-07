@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ПОЛНЫЙ ДЕПЛОЙ СИСТЕМЫ
echo   Backend + Frontend + Миграции БД
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "REMOTE_PATH=/opt/es-td-ngo"
set "BACKEND_CONTAINER=es_td_ngo_backend"

echo [1/10] Проверка подключения к серверу
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "echo OK" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удается подключиться к серверу
    pause
    exit /b 1
)
echo Подключение установлено
echo.

echo [2/10] Копирование backend файлов
pscp -batch -pw "%PASSWORD%" backend\main.py backend\models.py backend\auth.py backend\database.py backend\offline_encryption.py backend\offline_endpoints.py backend\report_generator.py "%SERVER%:%REMOTE_PATH%/backend/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать backend файлы
    pause
    exit /b 1
)
echo Backend файлы скопированы
echo.

echo [3/10] Копирование requirements.txt
pscp -batch -pw "%PASSWORD%" backend\requirements.txt "%SERVER%:%REMOTE_PATH%/backend/" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось скопировать requirements.txt
) else (
    echo requirements.txt скопирован
)
echo.

echo [4/10] Копирование миграций БД
pscp -batch -pw "%PASSWORD%" backend\create_offline_tables.py backend\create_branches_tables.py "%SERVER%:%REMOTE_PATH%/backend/" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось скопировать миграции
) else (
    echo Миграции скопированы
)
echo.

echo [5/10] Копирование frontend файлов
pscp -batch -pw "%PASSWORD%" pages\*.tsx components\*.tsx contexts\*.tsx types.ts constants.ts "%SERVER%:%REMOTE_PATH%/pages/" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось скопировать некоторые frontend файлы
) else (
    echo Frontend файлы скопированы
)
echo.

echo [6/10] Копирование файлов в backend контейнер
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker cp %REMOTE_PATH%/backend/main.py %BACKEND_CONTAINER%:/app/main.py 2>&1 && docker cp %REMOTE_PATH%/backend/models.py %BACKEND_CONTAINER%:/app/models.py 2>&1 && docker cp %REMOTE_PATH%/backend/auth.py %BACKEND_CONTAINER%:/app/auth.py 2>&1 && docker cp %REMOTE_PATH%/backend/database.py %BACKEND_CONTAINER%:/app/database.py 2>&1 && docker cp %REMOTE_PATH%/backend/offline_encryption.py %BACKEND_CONTAINER%:/app/offline_encryption.py 2>&1 && docker cp %REMOTE_PATH%/backend/offline_endpoints.py %BACKEND_CONTAINER%:/app/offline_endpoints.py 2>&1 && docker cp %REMOTE_PATH%/backend/report_generator.py %BACKEND_CONTAINER%:/app/report_generator.py 2>&1 && docker cp %REMOTE_PATH%/backend/create_offline_tables.py %BACKEND_CONTAINER%:/app/create_offline_tables.py 2>&1 && echo '✓ Backend файлы скопированы' || echo 'ОШИБКА: Не удалось скопировать backend файлы'"
echo.

echo [7/10] Установка новых зависимостей в контейнере
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %BACKEND_CONTAINER% pip install cryptography==42.0.5 2>&1 | tail -5"
echo.

echo [8/10] Выполнение миграций БД
echo   - Создание таблиц для offline-first режима
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %BACKEND_CONTAINER% python /app/create_offline_tables.py 2>&1 | tail -15"
echo.
echo   - Создание таблиц для иерархической системы доступа
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %BACKEND_CONTAINER% python /app/create_branches_tables.py 2>&1 | tail -15"
echo.

echo [9/10] Перезапуск backend контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker restart %BACKEND_CONTAINER%" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось перезапустить backend
) else (
    echo Backend контейнер перезапущен
)
echo.

echo [10/10] Пересборка и перезапуск frontend
echo   Остановка старого frontend контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker stop es_td_ngo_frontend 2>/dev/null; docker rm -f es_td_ngo_frontend 2>/dev/null; cd %REMOTE_PATH% && docker-compose stop frontend 2>/dev/null; docker-compose rm -f frontend 2>/dev/null" >nul 2>&1
echo.

echo   Пересборка frontend образа БЕЗ КЭША
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %REMOTE_PATH% && docker-compose build --no-cache frontend 2>&1 | tail -15"
echo.

echo   Запуск нового frontend контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %REMOTE_PATH% && docker-compose up -d frontend 2>&1"
echo.

echo Ожидание запуска контейнеров (20 секунд)
timeout /t 20 /nobreak >nul
echo.

echo ========================================
echo   ДЕПЛОЙ ЗАВЕРШЕН
echo ========================================
echo.
echo Проверьте результат:
echo   Backend: http://5.129.203.182:8000/docs
echo   Frontend: http://5.129.203.182
echo.
echo Обновления:
echo   - Offline-first режим для мобильного приложения
echo   - Иерархическая система доступа к оборудованию
echo   - Исправлена обработка ролей в мобильном приложении
echo   - Все миграции БД выполнены
echo.
pause
endlocal

