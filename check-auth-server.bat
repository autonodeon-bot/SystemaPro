@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ПРОВЕРКА АВТОРИЗАЦИИ НА СЕРВЕРЕ
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "CONTAINER_NAME=es_td_ngo_backend"

echo [1/4] Проверка наличия пользователей в БД
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %CONTAINER_NAME% python3 -c \"import asyncio; from database import AsyncSessionLocal; from models import User; from sqlalchemy import select; async def check(): async with AsyncSessionLocal() as db: result = await db.execute(select(User)); users = result.scalars().all(); print(f'Найдено пользователей: {len(users)}'); [print(f'  - {u.username} ({u.role}) - активен: {u.is_active}') for u in users]; asyncio.run(check())\" 2>&1"
echo.

echo [2/4] Проверка пароля admin
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %CONTAINER_NAME% python3 -c \"from auth import verify_password, hash_password; test_hash = hash_password('admin123'); print(f'Хеш пароля admin123: {test_hash[:50]}...'); test_verify = verify_password('admin123', test_hash); print(f'Проверка пароля: {test_verify}')\" 2>&1"
echo.

echo [3/4] Тестирование endpoint авторизации
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec %CONTAINER_NAME% python3 -c \"import urllib.request, urllib.parse; data = urllib.parse.urlencode({'username': 'admin', 'password': 'admin123'}).encode(); req = urllib.request.Request('http://localhost:8000/api/auth/login', data=data, headers={'Content-Type': 'application/x-www-form-urlencoded'}); try: resp = urllib.request.urlopen(req); print('УСПЕХ:', resp.read().decode()); except urllib.error.HTTPError as e: print('ОШИБКА:', e.code, e.read().decode())\" 2>&1"
echo.

echo [4/4] Проверка логов backend
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker logs %CONTAINER_NAME% --tail 20 2>&1 | grep -E 'вход|login|admin|password|Пользователь' || echo 'Логи не найдены'"
echo.

echo ========================================
echo   ПРОВЕРКА ЗАВЕРШЕНА
echo ========================================
pause
endlocal





















