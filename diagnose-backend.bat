@echo off
chcp 65001 >nul
echo ========================================
echo   ДИАГНОСТИКА BACKEND
echo ========================================
echo.

set SERVER=root@5.129.203.182
set PASSWORD=ydR9+CL3?S@dgH
set CONTAINER_NAME=es_td_ngo_backend
set REMOTE_PATH=/opt/es-td-ngo

echo [1/8] Проверка подключения к серверу...
plink -batch -ssh -pw %PASSWORD% %SERVER% "echo 'OK'" >nul 2>&1
if errorlevel 1 (
    echo ✗ Не удается подключиться к серверу
    pause
    exit /b 1
)
echo ✓ Подключение установлено
echo.

echo [2/8] Проверка Docker на сервере...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker --version 2>&1"
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker-compose --version 2>&1"
echo.

echo [3/8] Проверка всех контейнеров backend...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker ps -a | grep -E 'backend|es_td'"
echo.

echo [4/8] Проверка статуса контейнера %CONTAINER_NAME%...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker ps | grep %CONTAINER_NAME% || echo 'Контейнер остановлен или не существует'"
echo.

echo [5/8] Проверка структуры файлов в контейнере...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker exec %CONTAINER_NAME% sh -c 'echo \"=== Файлы в /app ===\"; ls -la /app/*.py 2>&1 | head -15; echo \"\"; echo \"=== Проверка main.py ===\"; head -5 /app/main.py 2>&1 || echo \"main.py не найден\"' 2>&1"
echo.

echo [6/8] Проверка маршрутов FastAPI...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker exec %CONTAINER_NAME% python3 -c 'import sys; sys.path.insert(0, \"/app\"); from main import app; routes = [r.path for r in app.routes]; print(\"Найденные маршруты:\"); [print(f\"  {r}\") for r in sorted(set(routes))[:20]]' 2>&1"
echo.

echo [7/8] Проверка подключения к базе данных...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker exec %CONTAINER_NAME% python3 -c 'import sys; sys.path.insert(0, \"/app\"); import asyncio; from database import engine; async def test(): async with engine.begin() as conn: await conn.execute(\"SELECT 1\"); print(\"✓ Подключение к БД успешно\"); asyncio.run(test())' 2>&1"
echo.

echo [8/8] Проверка логов (последние 50 строк)...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker logs %CONTAINER_NAME% --tail 50 2>&1"
echo.

echo ========================================
echo   ПРОВЕРКА СЕТИ И ПОРТОВ
echo ========================================
echo.
plink -batch -ssh -pw %PASSWORD% %SERVER% "netstat -tuln | grep 8000 || ss -tuln | grep 8000 || echo 'Порт 8000 не прослушивается'"
echo.

echo ========================================
echo   ПРОВЕРКА DOCKER COMPOSE
echo ========================================
echo.
plink -batch -ssh -pw %PASSWORD% %SERVER% "cd %REMOTE_PATH% && docker-compose ps 2>&1"
echo.

echo ========================================
echo   ДИАГНОСТИКА ЗАВЕРШЕНА
echo ========================================
echo.
pause









