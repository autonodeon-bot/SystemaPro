@echo off
chcp 65001 >nul
echo ========================================
echo   СОЗДАНИЕ BACKEND КОНТЕЙНЕРА
echo ========================================
echo.

set SERVER=root@5.129.203.182
set PASSWORD=ydR9+CL3?S@dgH
set REMOTE_PATH=/opt/es-td-ngo

echo [1/5] Проверка подключения к серверу...
plink -batch -ssh -pw %PASSWORD% %SERVER% "echo 'OK'" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удается подключиться к серверу
    pause
    exit /b 1
)
echo ✓ Подключение установлено
echo.

echo [2/5] Копирование backend файлов на сервер...
pscp -batch -pw %PASSWORD% -r backend %SERVER%:%REMOTE_PATH%/ 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать backend
    pause
    exit /b 1
)
echo ✓ Backend файлы скопированы
echo.

echo [3/5] Проверка существующих образов Python...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker images | grep python | head -3"
echo.

echo [4/5] Попытка создания контейнера через docker-compose...
echo   Примечание: Если Docker Hub недоступен, используйте существующий образ
plink -batch -ssh -pw %PASSWORD% %SERVER% "cd %REMOTE_PATH% && docker-compose up -d backend 2>&1"
if errorlevel 1 (
    echo.
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось создать контейнер через docker-compose
    echo Возможные причины:
    echo   1. Docker Hub лимит (429 Too Many Requests)
    echo   2. Отсутствует образ python:3.11-slim
    echo.
    echo Проверяю наличие локального образа...
    plink -batch -ssh -pw %PASSWORD% %SERVER% "docker images | grep python"
    echo.
    echo Если образ python:3.11-slim отсутствует, подождите 1-2 часа
    echo и попробуйте снова, или используйте существующий образ.
) else (
    echo ✓ Контейнер создан и запущен
)
echo.

echo [5/5] Проверка статуса контейнера...
plink -batch -ssh -pw %PASSWORD% %SERVER% "cd %REMOTE_PATH% && docker-compose ps"
echo.

echo ========================================
echo   СОЗДАНИЕ ЗАВЕРШЕНО
echo ========================================
echo.
echo Если контейнер не создан из-за лимита Docker Hub:
echo   1. Подождите 1-2 часа
echo   2. Или используйте существующий образ Python на сервере
echo   3. Или запустите rebuild-backend.bat позже
echo.
pause

























