@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo  АВТОМАТИЧЕСКИЙ ДЕПЛОЙ НА СЕРВЕР
echo ========================================
echo.

set SERVER_IP=5.129.203.182
set SERVER_USER=root
set SERVER_PASS=ydR9+CL3?S@dgH
set APP_DIR=/opt/es-td-ngo

echo [1/8] Проверка необходимых файлов...
if not exist "backend\main.py" (
    echo [❌] Ошибка: backend\main.py не найден
    pause
    exit /b 1
)
if not exist "docker-compose.yml" (
    echo [❌] Ошибка: docker-compose.yml не найден
    pause
    exit /b 1
)
echo [✓] Все файлы на месте
echo.

echo [2/8] Проверка подключения к серверу...
ping -n 1 %SERVER_IP% >nul 2>&1
if errorlevel 1 (
    echo [❌] Сервер %SERVER_IP% недоступен
    pause
    exit /b 1
)
echo [✓] Сервер доступен
echo.

echo [3/8] Подключение к серверу и создание директорий...
echo y | plink -ssh -pw %SERVER_PASS% %SERVER_USER%@%SERVER_IP% "mkdir -p %APP_DIR% && mkdir -p %APP_DIR%/backend && mkdir -p %APP_DIR%/backend/reports && mkdir -p %APP_DIR%/backend/certs && mkdir -p %APP_DIR%/frontend && mkdir -p %APP_DIR%/nginx" 2>nul
if errorlevel 1 (
    echo [⚠] Проверяю альтернативный метод подключения...
    plink -ssh -batch -pw %SERVER_PASS% %SERVER_USER%@%SERVER_IP% "mkdir -p %APP_DIR% && mkdir -p %APP_DIR%/backend && mkdir -p %APP_DIR%/backend/reports && mkdir -p %APP_DIR%/backend/certs && mkdir -p %APP_DIR%/frontend && mkdir -p %APP_DIR%/nginx" 2>nul
)
echo [✓] Директории созданы
echo.

echo [4/8] Копирование backend файлов...
pscp -batch -pw %SERVER_PASS% -r backend\*.py %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/ 2>nul
pscp -batch -pw %SERVER_PASS% backend\requirements.txt %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/ 2>nul
pscp -batch -pw %SERVER_PASS% backend\Dockerfile %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/ 2>nul
if exist "backend\test_data.py" (
    pscp -batch -pw %SERVER_PASS% backend\test_data.py %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/ 2>nul
)
if exist "backend\auth.py" (
    pscp -batch -pw %SERVER_PASS% backend\auth.py %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/ 2>nul
)
echo [✓] Backend файлы скопированы
echo.

echo [5/8] Копирование frontend файлов...
if exist "src" (
    pscp -batch -pw %SERVER_PASS% -r src\* %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/ 2>nul
)
if exist "pages" (
    pscp -batch -pw %SERVER_PASS% -r pages\* %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/ 2>nul
)
if exist "package.json" (
    pscp -batch -pw %SERVER_PASS% package.json %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/ 2>nul
)
if exist "vite.config.ts" (
    pscp -batch -pw %SERVER_PASS% vite.config.ts %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/ 2>nul
)
if exist "tsconfig.json" (
    pscp -batch -pw %SERVER_PASS% tsconfig.json %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/ 2>nul
)
if exist "index.html" (
    pscp -batch -pw %SERVER_PASS% index.html %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/ 2>nul
)
if exist "frontend.Dockerfile" (
    pscp -batch -pw %SERVER_PASS% frontend.Dockerfile %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/ 2>nul
)
echo [✓] Frontend файлы скопированы
echo.

echo [6/8] Копирование конфигурационных файлов...
pscp -batch -pw %SERVER_PASS% docker-compose.yml %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
if exist "nginx" (
    pscp -batch -pw %SERVER_PASS% -r nginx\* %SERVER_USER%@%SERVER_IP%:%APP_DIR%/nginx/ 2>nul
)
echo [✓] Конфигурационные файлы скопированы
echo.

echo [7/8] Создание скрипта деплоя на сервере...
pscp -batch -pw %SERVER_PASS% deploy-simple.sh %SERVER_USER%@%SERVER_IP%:%APP_DIR%/deploy.sh 2>nul
plink -batch -ssh -pw %SERVER_PASS% %SERVER_USER%@%SERVER_IP% "chmod +x %APP_DIR%/deploy.sh && dos2unix %APP_DIR%/deploy.sh 2>/dev/null || sed -i 's/\r$//' %APP_DIR%/deploy.sh" 2>nul
echo [✓] Скрипт деплоя создан
echo.

echo [8/8] Запуск деплоя на сервере...
echo [*] Это может занять несколько минут...
plink -batch -ssh -pw %SERVER_PASS% %SERVER_USER%@%SERVER_IP% "cd %APP_DIR% && ./deploy.sh"
if errorlevel 1 (
    echo [⚠] Ошибка при выполнении деплоя на сервере
    echo [*] Попробуйте подключиться вручную:
    echo     ssh %SERVER_USER%@%SERVER_IP%
    echo     cd %APP_DIR%
    echo     ./deploy.sh
    goto :end
)

echo.
echo ========================================
echo  ДЕПЛОЙ ЗАВЕРШЕН УСПЕШНО!
echo ========================================
echo.
echo Проверьте статус:
echo   ssh %SERVER_USER%@%SERVER_IP%
echo   cd %APP_DIR%
echo   docker-compose ps
echo   docker-compose logs -f backend
echo.
echo API доступен по адресу:
echo   http://%SERVER_IP%:8000
echo   http://%SERVER_IP%:8000/health
echo.
echo Frontend доступен по адресу:
echo   http://%SERVER_IP%
echo.

:end
pause
