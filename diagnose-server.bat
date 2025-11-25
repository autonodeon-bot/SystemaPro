@echo off
chcp 65001 >nul
echo ========================================
echo   ДИАГНОСТИКА СЕРВЕРА И BACKEND
echo ========================================
echo.

echo [1] Проверка статуса контейнеров...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose ps"
echo.

echo [2] Проверка логов backend (последние 50 строк)...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose logs backend --tail=50"
echo.

echo [3] Проверка работы API /health...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "curl -s http://localhost:8000/health || echo 'ОШИБКА: API не отвечает'"
echo.

echo [4] Проверка работы API /api/equipment...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "curl -s http://localhost:8000/api/equipment | head -c 500 || echo 'ОШИБКА: API не отвечает'"
echo.

echo [5] Проверка подключения к БД из контейнера...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose exec -T backend python -c 'import asyncio; from database import engine; from sqlalchemy import text; async def test(): async with engine.begin() as conn: result = await conn.execute(text(\"SELECT 1\")); print(\"✅ БД подключена\"); asyncio.run(test())' 2>&1"
echo.

echo ========================================
echo   ДИАГНОСТИКА ЗАВЕРШЕНА
echo ========================================
echo.
pause



