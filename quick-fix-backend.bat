@echo off
chcp 65001 >nul
echo ========================================
echo   БЫСТРОЕ ИСПРАВЛЕНИЕ BACKEND
echo ========================================
echo.
echo Этот скрипт выполнит:
echo   1. Проверку контейнера
echo   2. Обновление файлов без пересборки
echo   3. Перезапуск контейнера
echo   4. Проверку работоспособности
echo.
pause

set SERVER=root@5.129.203.182
set PASSWORD=ydR9+CL3?S@dgH
set CONTAINER_NAME=es_td_ngo_backend

echo [1/5] Проверка контейнера...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker ps -a | grep %CONTAINER_NAME%"
if errorlevel 1 (
    echo ✗ Контейнер не найден. Запустите rebuild-backend.bat
    pause
    exit /b 1
)
echo ✓ Контейнер найден
echo.

echo [2/5] Запуск контейнера, если остановлен...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker start %CONTAINER_NAME% 2>&1 || echo 'Контейнер уже запущен'"
timeout /t 3 /nobreak >nul
echo.

echo [3/5] Обновление файлов...
call update-backend-files.bat
if errorlevel 1 (
    echo ✗ Ошибка при обновлении файлов
    pause
    exit /b 1
)
echo.

echo [4/5] Проверка работоспособности...
timeout /t 10 /nobreak >nul
call check-auth-fix.bat
echo.

echo [5/5] Итоговая проверка...
plink -batch -ssh -pw %PASSWORD% %SERVER% "docker ps | grep %CONTAINER_NAME% && echo '✓ Контейнер работает' || echo '✗ Контейнер не запущен'"
echo.

echo ========================================
echo   ИСПРАВЛЕНИЕ ЗАВЕРШЕНО
echo ========================================
echo.
pause

























