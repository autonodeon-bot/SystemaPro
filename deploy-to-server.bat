@echo off
chcp 65001 >nul
echo ========================================
echo  ДЕПЛОЙ СИСТЕМЫ НА СЕРВЕР
echo ========================================
echo.

set SERVER_IP=5.129.203.182
set SERVER_USER=root
set SERVER_PASS=ydR9+CL3?S@dgH
set APP_DIR=/opt/es-td-ngo

echo [*] Подключение к серверу...
echo.

echo [*] Создание директории приложения...
plink -ssh -pw %SERVER_PASS% %SERVER_USER%@%SERVER_IP% "mkdir -p %APP_DIR% && mkdir -p %APP_DIR%/backend && mkdir -p %APP_DIR%/backend/reports && mkdir -p %APP_DIR%/frontend"

echo [*] Копирование файлов на сервер...
echo.

echo   - Backend файлы...
pscp -pw %SERVER_PASS% -r backend\*.py %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/
pscp -pw %SERVER_PASS% backend\requirements.txt %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/
pscp -pw %SERVER_PASS% backend\Dockerfile %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/

echo   - Frontend файлы...
pscp -pw %SERVER_PASS% -r src\* %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/
pscp -pw %SERVER_PASS% -r pages\* %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/
pscp -pw %SERVER_PASS% package.json %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/
pscp -pw %SERVER_PASS% vite.config.ts %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/
pscp -pw %SERVER_PASS% tsconfig.json %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/
pscp -pw %SERVER_PASS% index.html %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/
pscp -pw %SERVER_PASS% frontend.Dockerfile %SERVER_USER%@%SERVER_IP%:%APP_DIR%/frontend/

echo   - Docker конфигурация...
pscp -pw %SERVER_PASS% docker-compose.yml %SERVER_USER%@%SERVER_IP%:%APP_DIR%/
pscp -pw %SERVER_PASS% -r nginx\* %SERVER_USER%@%SERVER_IP%:%APP_DIR%/nginx/

echo [*] Создание скрипта инициализации на сервере...
plink -ssh -pw %SERVER_PASS% %SERVER_USER%@%SERVER_IP% "cat > %APP_DIR%/init.sh << 'EOF'
#!/bin/bash
cd %APP_DIR%
docker-compose down
docker-compose build --no-cache
docker-compose up -d
sleep 10
docker-compose exec -T backend python test_data.py
echo 'Инициализация завершена'
EOF
chmod +x %APP_DIR%/init.sh"

echo [*] Запуск инициализации на сервере...
plink -ssh -pw %SERVER_PASS% %SERVER_USER%@%SERVER_IP% "cd %APP_DIR% && ./init.sh"

echo.
echo [✓] Деплой завершен!
echo.
echo Проверьте статус:
echo   docker-compose ps
echo   docker-compose logs -f backend
echo.
pause



