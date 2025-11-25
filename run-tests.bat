@echo off
chcp 65001 >nul
echo ========================================
echo  ТЕСТИРОВАНИЕ СИСТЕМЫ
echo ========================================
echo.

echo [0] Проверка и запуск backend...
echo.
echo Выберите способ запуска backend:
echo   1. Через Docker (если Docker Desktop запущен)
echo   2. Напрямую через Python (без Docker)
echo.
set /p backend_choice="Ваш выбор (1 или 2, по умолчанию 2): "
if "%backend_choice%"=="" set backend_choice=2
if "%backend_choice%"=="1" (
    call start-backend.bat
) else (
    echo [*] Запуск backend напрямую через Python...
    start "Backend Server" cmd /k "cd backend && python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
    echo [*] Ожидание запуска сервера...
    timeout /t 5 /nobreak >nul
    echo [*] Проверка доступности API...
    curl -s http://localhost:8000/health >nul 2>&1
    if errorlevel 1 (
        echo [⚠] API пока не отвечает. Подождите несколько секунд...
    ) else (
        echo [✓] API доступен
    )
)
echo.

echo [1] Тестирование API endpoints...
echo.
cd backend
python test_api.py
if errorlevel 1 (
    echo.
    echo [❌] Ошибка при тестировании API
    echo Проверьте, что backend запущен: docker-compose ps
    echo.
    pause
    exit /b 1
)
echo.

echo [2] Добавление тестовых данных...
echo.
python test_data.py
echo.

echo [3] Повторное тестирование API после добавления данных...
echo.
python test_api.py
echo.

echo ========================================
echo  ТЕСТИРОВАНИЕ ЗАВЕРШЕНО
echo ========================================
echo.
pause



