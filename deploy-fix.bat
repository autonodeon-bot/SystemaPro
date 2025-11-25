@echo off
chcp 65001 >nul
echo ========================================
echo   Исправление ошибки подключения к БД
echo ========================================
echo.

echo [*] Копирование исправленных файлов на сервер...
echo.

REM Копирование backend/database.py
scp -o StrictHostKeyChecking=no backend/database.py root@5.129.203.182:/opt/es-td-ngo/backend/database.py
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать database.py
    pause
    exit /b 1
)

REM Копирование backend/main.py
scp -o StrictHostKeyChecking=no backend/main.py root@5.129.203.182:/opt/es-td-ngo/backend/main.py
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать main.py
    pause
    exit /b 1
)

REM Копирование backend/models.py
scp -o StrictHostKeyChecking=no backend/models.py root@5.129.203.182:/opt/es-td-ngo/backend/models.py
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать models.py
    pause
    exit /b 1
)

REM Копирование docker-compose.yml
scp -o StrictHostKeyChecking=no docker-compose.yml root@5.129.203.182:/opt/es-td-ngo/docker-compose.yml
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось скопировать docker-compose.yml
    pause
    exit /b 1
)

echo [✓] Файлы скопированы
echo.

echo [*] Перезапуск backend на сервере...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose restart backend"
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось перезапустить backend
    pause
    exit /b 1
)

echo.
echo [✓] Backend перезапущен
echo.
echo [*] Проверка логов...
ssh -o StrictHostKeyChecking=no root@5.129.203.182 "cd /opt/es-td-ngo && docker-compose logs backend --tail=20"
echo.
echo ========================================
echo   Готово!
echo ========================================
echo.
pause


