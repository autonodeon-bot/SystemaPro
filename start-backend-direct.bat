@echo off
chcp 65001 >nul
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

echo [*] Переход в директорию backend...
cd backend
if not exist "main.py" (
    echo [❌] Файл main.py не найден
    pause
    exit /b 1
)

echo [*] Проверка зависимостей...
pip show fastapi >nul 2>&1
if errorlevel 1 (
    echo [*] Установка зависимостей...
    pip install -q fastapi uvicorn sqlalchemy asyncpg pydantic python-jose passlib python-multipart requests reportlab Pillow python-dateutil
)

echo.
echo [*] Запуск backend сервера...
echo [✓] Backend будет доступен на http://localhost:8000
echo [*] Для остановки нажмите Ctrl+C
echo.
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload

