@echo off
chcp 65001 >nul
echo ========================================
echo   ПОЛНАЯ ПЕРЕСБОРКА BACKEND
echo ========================================
echo.

set SERVER=root@5.129.203.182
set PASSWORD=ydR9+CL3?S@dgH
set REMOTE_PATH=/opt/es-td-ngo
set CONTAINER_NAME=es_td_ngo_backend

echo [1/6] Проверка подключения к серверу...
plink -batch -ssh -pw %PASSWORD% %SERVER% "echo 'Подключение успешно'" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удается подключиться к серверу
    pause
    exit /b 1
)
echo ✓ Подключение установлено
echo.

echo [2/6] Копирование всех файлов backend на сервер...
echo   - Копирую Python файлы...
pscp -batch -pw %PASSWORD% backend\*.py root@5.129.203.182:%REMOTE_PATH%/backend/ 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при копировании Python файлов
)
echo   - Копирую requirements.txt...
pscp -batch -pw %PASSWORD% backend\requirements.txt root@5.129.203.182:%REMOTE_PATH%/backend/ 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при копировании requirements.txt
)
echo   - Копирую Dockerfile...
pscp -batch -pw %PASSWORD% backend\Dockerfile root@5.129.203.182:%REMOTE_PATH%/backend/ 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать Dockerfile
    pause
    exit /b 1
)
echo ✓ Все файлы скопированы
echo.

echo [3/6] Остановка и удаление старого контейнера...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker stop %CONTAINER_NAME% 2>/dev/null; docker rm -f %CONTAINER_NAME% 2>/dev/null; cd %REMOTE_PATH% && docker-compose stop backend 2>/dev/null; docker-compose rm -f backend 2>/dev/null"
echo ✓ Старый контейнер остановлен и удален
echo.

echo Удаление старого образа (если существует)...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker images | grep es-td-ngo-backend && docker rmi es-td-ngo-backend 2>/dev/null || echo 'Образ не найден или уже удален'"
echo.

echo [4/6] Проверка доступности Docker Hub...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker pull python:3.11-slim 2>&1 | head -5"
if errorlevel 1 (
    echo.
    echo ⚠️  ПРЕДУПРЕЖДЕНИЕ: Возможен лимит Docker Hub
    echo Пробую использовать существующий образ...
    plink -batch -ssh -pw %PASSWORD% %SERVER% "docker images | grep python | head -3"
    echo.
    echo Пробую пересобрать с использованием кэша...
    plink -batch -ssh -pw %PASSWORD% %SERVER% "cd %REMOTE_PATH% && docker-compose build backend 2>&1 | tail -20"
) else (
    echo ✓ Docker Hub доступен
    echo.
    echo [5/6] Пересборка образа БЕЗ КЭША (это займет 2-3 минуты)...
    plink -batch -ssh -pw %PASSWORD% %SERVER% "cd %REMOTE_PATH% && docker-compose build --no-cache backend 2>&1 | tail -20"
)
if errorlevel 1 (
    echo.
    echo ⚠️  ОШИБКА: Не удалось пересобрать образ
    echo Попробуйте запустить update-backend-files.bat для обновления без пересборки
    pause
    exit /b 1
)
echo ✓ Образ пересобран
echo.

echo [6/6] Запуск нового контейнера...
plink -batch -ssh -pw %PASSWORD% %SERVER% "cd %REMOTE_PATH% && docker-compose up -d backend 2>&1"
echo ✓ Контейнер запущен
echo.

echo Ожидание запуска (10 секунд)...
timeout /t 10 /nobreak >nul
echo.

echo Проверка статуса...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker ps | grep backend || docker ps -a | grep backend"
echo.

echo Проверка логов...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker logs %CONTAINER_NAME% --tail 20 2>&1 || echo 'Контейнер еще не запущен'"
echo.

echo ========================================
echo   ПЕРЕСБОРКА ЗАВЕРШЕНА
echo ========================================
echo.
echo Теперь запустите check-auth-fix.bat для проверки
echo.
pause


