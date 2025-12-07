@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ОБНОВЛЕНИЕ ВЕРСИИ НА СЕРВЕРЕ
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "REMOTE_PATH=/opt/es-td-ngo"

echo [1/6] Проверка подключения к серверу
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "echo OK" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удается подключиться к серверу
    echo Проверьте подключение к интернету и доступность сервера
    pause
    exit /b 1
)
echo Подключение установлено
echo.

echo [2/6] Копирование папок на сервер
echo   - Копирую pages
pscp -batch -pw "%PASSWORD%" -r pages "%SERVER%:%REMOTE_PATH%/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать pages
    pause
    exit /b 1
)
echo   pages скопирована
echo.

echo   - Копирую components
if exist components (
    pscp -batch -pw "%PASSWORD%" -r components "%SERVER%:%REMOTE_PATH%/" >nul 2>&1
    if errorlevel 1 (
        echo ПРЕДУПРЕЖДЕНИЕ: Не удалось скопировать components
    ) else (
        echo   components скопирована
    )
) else (
    echo   Папка components не найдена, пропускаю
)
echo.

echo   - Копирую contexts
if exist contexts (
    pscp -batch -pw "%PASSWORD%" -r contexts "%SERVER%:%REMOTE_PATH%/" >nul 2>&1
    if errorlevel 1 (
        echo ПРЕДУПРЕЖДЕНИЕ: Не удалось скопировать contexts
    ) else (
        echo   contexts скопирована
    )
) else (
    echo   Папка contexts не найдена, пропускаю
)
echo.

echo   - Копирую nginx
pscp -batch -pw "%PASSWORD%" -r nginx "%SERVER%:%REMOTE_PATH%/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать nginx
    pause
    exit /b 1
)
echo   nginx скопирована
echo.

echo [3/6] Копирование файлов на сервер
pscp -batch -pw "%PASSWORD%" index.html index.tsx App.tsx package.json vite.config.ts constants.ts frontend.Dockerfile docker-compose.yml "%SERVER%:%REMOTE_PATH%/" >nul 2>&1
if exist package-lock.json (
    pscp -batch -pw "%PASSWORD%" package-lock.json "%SERVER%:%REMOTE_PATH%/" >nul 2>&1
)
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Некоторые файлы не удалось скопировать
) else (
    echo Файлы скопированы
)
echo.

echo [4/6] Проверка версии в коде на сервере
       plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd /opt/es-td-ngo && grep -E '3\.1\.1' pages/TechSpecs.tsx | head -1"
echo.

echo [5/6] Остановка и удаление старого контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker stop es_td_ngo_frontend 2>/dev/null; docker rm -f es_td_ngo_frontend 2>/dev/null; cd /opt/es-td-ngo && docker-compose stop frontend 2>/dev/null; docker-compose rm -f frontend 2>/dev/null" >nul 2>&1
echo Старый контейнер остановлен и удален
echo.

echo [6/6] Пересборка образа БЕЗ КЭША
echo   Пожалуйста, подождите
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd /opt/es-td-ngo && docker-compose build --no-cache frontend 2>&1 | tail -15"
if errorlevel 1 (
    echo.
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при сборке
    echo Проверяю логи
    plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd /opt/es-td-ngo && docker-compose build --no-cache frontend 2>&1 | tail -20"
    echo.
    echo Пробую пересобрать еще раз
    plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd /opt/es-td-ngo && docker-compose build --no-cache frontend 2>&1 | tail -10"
) else (
    echo Образ пересобран
)
echo.

echo Запуск нового контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd /opt/es-td-ngo && docker-compose up -d frontend 2>&1"
if errorlevel 1 (
    echo.
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при запуске через docker-compose
    echo Пробую альтернативные способы запуска
    echo.
    echo Способ 1: Остановка всех контейнеров и перезапуск
    plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd /opt/es-td-ngo && docker-compose stop frontend 2>&1"
    plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd /opt/es-td-ngo && docker-compose rm -f frontend 2>&1"
    plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd /opt/es-td-ngo && docker-compose up -d frontend 2>&1"
    if errorlevel 1 (
        echo.
        echo Способ 2: Прямой запуск через docker run
        plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker stop es_td_ngo_frontend 2>/dev/null; docker rm es_td_ngo_frontend 2>/dev/null; docker run -d --name es_td_ngo_frontend -p 80:80 es-td-ngo-frontend:latest 2>&1"
    )
    echo.
    echo Проверяю статус контейнера
    plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker ps -a | grep frontend || echo 'Контейнер не найден'"
    echo.
    echo Проверяю логи контейнера
    plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker logs es_td_ngo_frontend --tail 10 2>&1 || echo 'Контейнер не найден'"
) else (
    echo Контейнер запущен
)
echo.

echo Ожидание запуска контейнера (15 секунд)
timeout /t 15 /nobreak >nul
echo.

echo ========================================
echo   ПРОВЕРКА ВЕРСИИ
echo ========================================
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_frontend sh -c \"JS_FILE=\$(ls /usr/share/nginx/html/assets/*.js 2>/dev/null | head -1); if [ -f \\\"\$JS_FILE\\\" ]; then echo \\\"JS файл: \$(basename \$JS_FILE)\\\"; echo \\\"Размер: \$(du -h \$JS_FILE | cut -f1)\\\"; echo \\\"\\\"; echo \\\"Найденные версии:\\\"; grep -oE \\\"3\\\\.[0-9]\\\\.[0-9]\\\" \\\"\$JS_FILE\\\" | sort -u | head -5; echo \\\"\\\"; if grep -q \\\"3.1.0\\\" \\\"\$JS_FILE\\\"; then echo \\\"Версия 3.1.0 НАЙДЕНА\\\"; else echo \\\"Версия 3.1.0 НЕ найдена\\\"; echo \\\"Найдена версия:\\\"; grep -oE \\\"3\\\\.[0-9]\\\\.[0-9]\\\" \\\"\$JS_FILE\\\" | sort -u | head -1; fi; else echo \\\"JS файл не найден\\\"; fi\""
if errorlevel 1 (
    echo.
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось проверить версию
    echo Контейнер может быть еще не запущен
    echo Подождите 1-2 минуты и проверьте вручную
)
echo.

echo ========================================
echo   ОБНОВЛЕНИЕ ЗАВЕРШЕНО
echo ========================================
echo.
echo Проверьте результат:
echo   http://5.129.203.182/#/specs
echo.
       echo Версия должна быть: 3.1.1 (2025-Q4)
echo.
echo Если версия все еще 3.0.0:
echo   1. Подождите еще 2-3 минуты (сборка может быть в процессе)
echo   2. Очистите кэш браузера (Ctrl+Shift+Delete)
echo   3. Используйте режим инкогнито (Ctrl+Shift+N)
echo.
pause
endlocal
