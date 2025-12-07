@echo off
chcp 65001 >nul
echo ========================================
echo   ПРОВЕРКА ИСПРАВЛЕНИЙ АВТОРИЗАЦИИ
echo ========================================
echo.

set SERVER=root@5.129.203.182
set PASSWORD=ydR9+CL3?S@dgH
set CONTAINER_NAME=es_td_ngo_backend

echo [1/6] Проверка подключения к серверу...
plink -batch -ssh -pw %PASSWORD% %SERVER% "echo 'OK'" >nul 2>&1
if errorlevel 1 (
    echo ✗ Не удается подключиться к серверу
    pause
    exit /b 1
)
echo ✓ Подключение установлено
echo.

echo [2/6] Проверка существования контейнера...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker ps -a | grep %CONTAINER_NAME% >nul 2>&1"
if errorlevel 1 (
    echo ✗ Контейнер %CONTAINER_NAME% не найден
    echo.
    echo Попробуйте запустить:
    echo   1. update-backend-files.bat - для обновления файлов
    echo   2. rebuild-backend.bat - для полной пересборки
    echo.
    pause
    exit /b 1
)
echo ✓ Контейнер найден
echo.

echo [3/6] Проверка статуса контейнера...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker ps | grep %CONTAINER_NAME%"
if errorlevel 1 (
    echo ⚠️  Контейнер остановлен, запускаю...
    plink -batch -ssh -pw %PASSWORD% %SERVER% "docker start %CONTAINER_NAME% 2>&1"
    echo Ожидание запуска (5 секунд)...
    timeout /t 5 /nobreak >nul
)
echo.

echo [4/6] Проверка структуры файлов в контейнере...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker exec %CONTAINER_NAME% sh -c 'ls -la /app/*.py 2>&1 | head -10'"
echo.

echo [5/6] Проверка пользователей в БД...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker exec %CONTAINER_NAME% sh -c 'cd /app && python3 -c \"import sys; sys.path.insert(0, \\\"/app\\\"); import asyncio; from init_users import init_users; asyncio.run(init_users())\" 2>&1'"
echo.

echo [6/6] Тестирование endpoint авторизации...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker exec %CONTAINER_NAME% python3 -c 'import urllib.request, urllib.parse, json; data = urllib.parse.urlencode({\"username\": \"admin\", \"password\": \"admin123\"}).encode(); req = urllib.request.Request(\"http://localhost:8000/api/auth/login\", data=data, headers={\"Content-Type\": \"application/x-www-form-urlencoded\"}); resp = urllib.request.urlopen(req, timeout=5); result = json.loads(resp.read().decode()); print(\"✓ Авторизация успешна!\"); print(\"  Роль:\", result.get(\"role\", \"не указана\")); print(\"  User ID:\", result.get(\"user_id\", \"не указан\"))' 2>&1"
if errorlevel 1 (
    echo.
    echo ✗ ОШИБКА: Endpoint /api/auth/login недоступен или возвращает ошибку
    echo.
    echo Проверяю логи...
    plink -batch -ssh -pw %PASSWORD% %SERVER% "docker logs %CONTAINER_NAME% --tail 30 2>&1 | tail -20"
) else (
    echo ✓ Endpoint работает корректно
)
echo.

echo ========================================
echo   ДОПОЛНИТЕЛЬНАЯ ДИАГНОСТИКА
echo ========================================
echo.
echo Проверка логов backend (последние 20 строк)...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker logs %CONTAINER_NAME% --tail 20 2>&1"
echo.

echo Проверка доступности API извне...
plink -batch -ssh -pw %PASSWORD% %SERVER% "curl -s -o /dev/null -w 'HTTP Status: %%{http_code}\n' http://localhost:8000/health 2>&1 || echo 'curl недоступен, проверяю через python...'"
echo.

echo ========================================
echo   ПРОВЕРКА ЗАВЕРШЕНА
echo ========================================
echo.
echo Тестовые учетные записи:
echo   admin / admin123
echo   chief_operator / chief123
echo   operator / operator123
echo   engineer1 / engineer123
echo   engineer2 / engineer123
echo.
echo Если авторизация не работает:
echo   1. Проверьте логи: docker logs %CONTAINER_NAME%
echo   2. Запустите update-backend-files.bat для обновления файлов
echo   3. Проверьте, что контейнер запущен: docker ps | grep backend
echo.
pause

