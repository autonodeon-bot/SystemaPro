@echo off
chcp 65001 >nul
echo ========================================
echo  ЗАПУСК BACKEND СЕРВЕРА
echo ========================================
echo.

echo [*] Проверка Docker...
docker info >nul 2>&1
if errorlevel 1 (
    echo [⚠] Docker Desktop не запущен или недоступен
    echo.
    echo Выберите способ запуска:
    echo   1. Запустить через Docker (требует запущенный Docker Desktop)
    echo   2. Запустить напрямую через Python (без Docker)
    echo.
    set /p choice="Ваш выбор (1 или 2): "
    
    if "!choice!"=="2" goto :run_direct
    if "!choice!"=="1" (
        echo.
        echo [*] Пожалуйста, запустите Docker Desktop и повторите попытку
        echo Или нажмите любую клавишу для запуска напрямую через Python...
        pause >nul
        goto :run_direct
    )
    exit /b 1
)

echo [*] Docker доступен. Проверка контейнеров...
docker-compose ps 2>nul | findstr "backend" >nul
if errorlevel 1 (
    echo [*] Backend не запущен. Запускаю через Docker...
    docker-compose up -d backend
    echo [*] Ожидание запуска сервера...
    timeout /t 5 /nobreak >nul
    
    echo [*] Проверка статуса...
    docker-compose ps backend
) else (
    echo [✓] Backend уже запущен в Docker
)

echo.
echo [*] Проверка доступности API...
timeout /t 2 /nobreak >nul
curl -s http://localhost:8000/health >nul 2>&1
if errorlevel 1 (
    echo [⚠] API пока не отвечает. Подождите несколько секунд...
    echo [*] Логи backend:
    docker-compose logs --tail=20 backend 2>nul
) else (
    echo [✓] API доступен: http://localhost:8000
)
goto :end

:run_direct
echo.
echo ========================================
echo  ЗАПУСК BACKEND НАПРЯМУЮ (БЕЗ DOCKER)
echo ========================================
echo.

echo [*] Проверка Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo [❌] Python не установлен или не найден в PATH
    pause
    exit /b 1
)

echo [*] Проверка зависимостей...
cd backend
if not exist "requirements.txt" (
    echo [❌] Файл requirements.txt не найден
    pause
    exit /b 1
)

echo [*] Установка зависимостей (если нужно)...
pip install -q fastapi uvicorn sqlalchemy asyncpg pydantic python-jose passlib python-multipart requests reportlab >nul 2>&1

echo [*] Запуск backend сервера...
echo [✓] Backend запускается на http://localhost:8000
echo [*] Для остановки нажмите Ctrl+C
echo.
start "Backend Server" cmd /k "python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
timeout /t 3 /nobreak >nul

echo [*] Проверка доступности API...
curl -s http://localhost:8000/health >nul 2>&1
if errorlevel 1 (
    echo [⚠] API пока не отвечает. Подождите несколько секунд...
) else (
    echo [✓] API доступен: http://localhost:8000
)

cd ..

:end
echo.
echo ========================================
echo  Backend готов к работе
echo ========================================
echo.
pause

