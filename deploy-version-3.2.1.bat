@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ДЕПЛОЙ ВЕРСИИ 3.2.1 НА СЕРВЕР
echo   Обновление версий и исправлений
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "REMOTE_PATH=/opt/es-td-ngo"
set "BACKEND_CONTAINER=es_td_ngo_backend"

echo [1/7] Проверка подключения к серверу
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "echo OK" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удается подключиться к серверу
    pause
    exit /b 1
)
echo Подключение установлено
echo.

echo [2/7] Копирование frontend файлов с обновленными версиями
pscp -batch -pw "%PASSWORD%" pages\Changelog.tsx pages\Login.tsx pages\TechSpecs.tsx "%SERVER%:%REMOTE_PATH%/pages/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать frontend файлы
    pause
    exit /b 1
)
echo Frontend файлы скопированы
echo.

echo [3/7] Копирование CHANGELOG.md
pscp -batch -pw "%PASSWORD%" CHANGELOG.md "%SERVER%:%REMOTE_PATH%/" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось скопировать CHANGELOG.md
) else (
    echo CHANGELOG.md скопирован
)
echo.

echo [4/7] Пересборка и перезапуск frontend
echo   Остановка старого frontend контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker stop es_td_ngo_frontend 2>/dev/null; docker rm -f es_td_ngo_frontend 2>/dev/null; cd %REMOTE_PATH% && docker-compose stop frontend 2>/dev/null; docker-compose rm -f frontend 2>/dev/null" >nul 2>&1
echo.

echo   Пересборка frontend образа БЕЗ КЭША
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %REMOTE_PATH% && docker-compose build --no-cache frontend 2>&1 | tail -15"
echo.

echo   Запуск нового frontend контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %REMOTE_PATH% && docker-compose up -d frontend 2>&1"
echo.

echo Ожидание запуска контейнеров (15 секунд)
timeout /t 15 /nobreak >nul
echo.

echo [5/7] Проверка статуса контейнеров
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker ps --filter name=es_td_ngo --format 'table {{.Names}}\t{{.Status}}'"
echo.

echo [6/7] Проверка backend API
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "curl -s http://localhost:8000/health | head -5"
echo.

echo [7/7] Финальная проверка
echo   Backend: http://5.129.203.182:8000/docs
echo   Frontend: http://5.129.203.182
echo   Changelog: http://5.129.203.182/#/changelog
echo.

echo ========================================
echo   ДЕПЛОЙ ВЕРСИИ 3.2.1 ЗАВЕРШЕН
echo ========================================
echo.
echo Обновления:
echo   - Версия системы: 3.2.1 (2025-Q4)
echo   - Исправлена обработка ролей в мобильном приложении
echo   - Добавлена защита от неправильных ролей
echo   - Обновлен CHANGELOG с версией 3.2.1
echo.
pause
endlocal

