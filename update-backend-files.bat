@echo off
chcp 65001 >nul
echo ========================================
echo   ОБНОВЛЕНИЕ ФАЙЛОВ BACKEND БЕЗ ПЕРЕСБОРКИ
echo ========================================
echo.

set SERVER=root@5.129.203.182
set PASSWORD=ydR9+CL3?S@dgH
set REMOTE_PATH=/opt/es-td-ngo
set CONTAINER_NAME=es_td_ngo_backend

echo [1/7] Проверка подключения к серверу...
plink -batch -ssh -pw %PASSWORD% %SERVER% "echo 'Подключение успешно'" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удается подключиться к серверу
    pause
    exit /b 1
)
echo ✓ Подключение установлено
echo.

echo [2/7] Копирование всех Python файлов на сервер...
pscp -batch -pw %PASSWORD% backend\*.py root@5.129.203.182:/tmp/ 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при копировании файлов
    echo Продолжаю...
)
echo ✓ Файлы скопированы в /tmp/
echo.

echo [3/7] Проверка существующих контейнеров...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker ps -a | grep backend || echo 'Контейнер не найден'"
echo.

echo [4/7] Проверка и запуск контейнера...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker ps | grep %CONTAINER_NAME% >nul 2>&1"
if errorlevel 1 (
    echo Контейнер не запущен, проверяю существование...
    plink -batch -ssh -pw %PASSWORD% %SERVER% "docker ps -a | grep %CONTAINER_NAME% >nul 2>&1"
    if errorlevel 1 (
        echo ОШИБКА: Контейнер %CONTAINER_NAME% не существует
        echo.
        echo Запустите create-backend-container.bat для создания контейнера
        echo Или подождите, пока Docker Hub станет доступен
        pause
        exit /b 1
    )
    echo Контейнер существует, запускаю...
    plink -batch -ssh -pw %PASSWORD% %SERVER% "docker start %CONTAINER_NAME% 2>&1 || (cd %REMOTE_PATH% && docker-compose up -d backend 2>&1)"
)
echo ✓ Контейнер проверен/запущен
echo.

echo [5/7] Ожидание готовности контейнера (5 секунд)...
timeout /t 5 /nobreak >nul
echo.

echo [6/7] Копирование файлов в контейнер...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker cp /tmp/main.py %CONTAINER_NAME%:/app/main.py 2>&1 && docker cp /tmp/auth.py %CONTAINER_NAME%:/app/auth.py 2>&1 && docker cp /tmp/models.py %CONTAINER_NAME%:/app/models.py 2>&1 && docker cp /tmp/database.py %CONTAINER_NAME%:/app/database.py 2>&1 && docker cp /tmp/init_users.py %CONTAINER_NAME%:/app/init_users.py 2>&1 && docker cp /tmp/report_generator.py %CONTAINER_NAME%:/app/report_generator.py 2>&1 && echo '✓ Все файлы скопированы' || echo 'ОШИБКА: Не удалось скопировать некоторые файлы'"
echo.

echo [7/7] Перезапуск контейнера для применения изменений...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker restart %CONTAINER_NAME% 2>&1"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось перезапустить контейнер
    echo Пробую через docker-compose...
    plink -batch -ssh -pw %PASSWORD% %SERVER% "cd %REMOTE_PATH% && docker-compose restart backend 2>&1"
) else (
    echo ✓ Контейнер перезапущен
)
echo.

echo Ожидание запуска (15 секунд)...
timeout /t 15 /nobreak >nul
echo.

echo ========================================
echo   ПРОВЕРКА СТАТУСА
echo ========================================
echo.
echo Проверка статуса контейнера...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker ps | grep backend || docker ps -a | grep backend"
echo.

echo Проверка логов (последние 30 строк)...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker logs %CONTAINER_NAME% --tail 30 2>&1 | head -30"
echo.

echo Проверка доступности API...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker exec %CONTAINER_NAME% python3 -c 'import urllib.request, urllib.parse; data = urllib.parse.urlencode({\"username\": \"admin\", \"password\": \"admin123\"}).encode(); req = urllib.request.Request(\"http://localhost:8000/health\", timeout=5); resp = urllib.request.urlopen(req); print(\"API доступен:\", resp.getcode())' 2>&1 || echo 'API недоступен'"
echo.

echo ========================================
echo   ОБНОВЛЕНИЕ ЗАВЕРШЕНО
echo ========================================
echo.
echo Следующие шаги:
echo   1. Запустите check-auth-fix.bat для полной проверки
echo   2. Проверьте логи: docker logs %CONTAINER_NAME%
echo   3. Проверьте API: http://5.129.203.182:8000/docs
echo.
pause


