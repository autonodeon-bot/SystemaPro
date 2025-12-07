@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
echo ========================================
echo   ОБНОВЛЕНИЕ ВЕРСИИ 3.1.1 НА СЕРВЕРЕ
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "REMOTE_PATH=/opt/es-td-ngo"

echo [1/7] Проверка подключения к серверу
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "echo OK" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удается подключиться к серверу
    pause
    exit /b 1
)
echo Подключение установлено
echo.

echo [2/7] Копирование frontend файлов на сервер
echo   - Копирую pages
pscp -batch -pw "%PASSWORD%" -r pages "%SERVER%:%REMOTE_PATH%/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать pages
    pause
    exit /b 1
)
echo   pages скопирована

if exist components (
    pscp -batch -pw "%PASSWORD%" -r components "%SERVER%:%REMOTE_PATH%/" >nul 2>&1
    if errorlevel 1 (
        echo ПРЕДУПРЕЖДЕНИЕ: Не удалось скопировать components
    ) else (
        echo   components скопирована
    )
)

if exist contexts (
    pscp -batch -pw "%PASSWORD%" -r contexts "%SERVER%:%REMOTE_PATH%/" >nul 2>&1
    if errorlevel 1 (
        echo ПРЕДУПРЕЖДЕНИЕ: Не удалось скопировать contexts
    ) else (
        echo   contexts скопирована
    )
)

pscp -batch -pw "%PASSWORD%" -r nginx "%SERVER%:%REMOTE_PATH%/" >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Не удалось скопировать nginx
    pause
    exit /b 1
)
echo   nginx скопирована
echo.

echo [3/7] Копирование основных файлов
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

echo [4/7] Копирование backend файлов
pscp -batch -pw "%PASSWORD%" backend\main.py backend\models.py "%SERVER%:%REMOTE_PATH%/backend/" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось скопировать backend файлы
) else (
    echo Backend файлы скопированы
)
echo.

echo [5/7] Копирование скрипта создания таблицы questionnaires
pscp -batch -pw "%PASSWORD%" backend\create_questionnaires_table.py "%SERVER%:%REMOTE_PATH%/backend/" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось скопировать скрипт создания таблицы
) else (
    echo Скрипт создания таблицы скопирован
)
echo.

echo [6/7] Создание таблицы questionnaires в базе данных
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_backend python /app/backend/create_questionnaires_table.py"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при создании таблицы
    echo Проверьте логи контейнера
) else (
    echo Таблица questionnaires создана
)
echo.

echo [7/7] Пересборка и перезапуск frontend
echo   Остановка старого контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker stop es_td_ngo_frontend 2>/dev/null; docker rm -f es_td_ngo_frontend 2>/dev/null; cd %REMOTE_PATH% && docker-compose stop frontend 2>/dev/null; docker-compose rm -f frontend 2>/dev/null" >nul 2>&1
echo   Старый контейнер остановлен
echo.

echo   Пересборка образа БЕЗ КЭША
echo   Пожалуйста, подождите
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %REMOTE_PATH% && docker-compose build --no-cache frontend 2>&1 | tail -15"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при сборке
) else (
    echo Образ пересобран
)
echo.

echo   Запуск нового контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %REMOTE_PATH% && docker-compose up -d frontend 2>&1"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Возможна ошибка при запуске
) else (
    echo Контейнер запущен
)
echo.

echo   Перезапуск backend контейнера
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker restart es_td_ngo_backend" >nul 2>&1
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось перезапустить backend
) else (
    echo Backend контейнер перезапущен
)
echo.

echo Ожидание запуска контейнеров (15 секунд)
timeout /t 15 /nobreak >nul
echo.

echo ========================================
echo   ПРОВЕРКА ВЕРСИИ
echo ========================================
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_frontend sh -c \"JS_FILE=\$(ls /usr/share/nginx/html/assets/*.js 2>/dev/null | head -1); if [ -f \\\"\$JS_FILE\\\" ]; then echo \\\"JS файл: \$(basename \$JS_FILE)\\\"; echo \\\"Размер: \$(du -h \$JS_FILE | cut -f1)\\\"; echo \\\"\\\"; echo \\\"Найденные версии:\\\"; grep -oE \\\"3\\\\.[0-9]\\\\.[0-9]\\\" \\\"\$JS_FILE\\\" | sort -u | head -5; echo \\\"\\\"; if grep -q \\\"3.1.1\\\" \\\"\$JS_FILE\\\"; then echo \\\"Версия 3.1.1 НАЙДЕНА\\\"; else echo \\\"Версия 3.1.1 НЕ найдена\\\"; echo \\\"Найдена версия:\\\"; grep -oE \\\"3\\\\.[0-9]\\\\.[0-9]\\\" \\\"\$JS_FILE\\\" | sort -u | head -1; fi; else echo \\\"JS файл не найден\\\"; fi\""
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось проверить версию
)
echo.

echo ========================================
echo   ОБНОВЛЕНИЕ ЗАВЕРШЕНО
echo ========================================
echo.
echo Проверьте результат:
echo   http://5.129.203.182/#/specs
echo   http://5.129.203.182/#/changelog
echo.
echo Версия должна быть: 3.1.1 (2025-Q4)
echo.
pause
endlocal





