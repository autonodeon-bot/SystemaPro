@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo   Деплой изменений в Git
echo ========================================
echo.

echo [1] Проверка статуса Git...
git status --short
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Git не инициализирован!
    pause
    exit /b 1
)

echo.
echo [2] Добавление всех изменений...
git add -A
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось добавить файлы
    pause
    exit /b 1
)

echo.
echo [3] Проверка что есть что коммитить...
git diff --cached --quiet
if %ERRORLEVEL% EQU 0 (
    echo [ИНФО] Нет изменений для коммита
    goto :push
)

echo.
echo [4] Создание коммита...
git commit -m "feat: настройка деплоя и исправление проблем

- Настроен backend с подключением к удаленной PostgreSQL БД с SSL
- Исправлены импорты в backend (убраны относительные импорты)
- Настроен Tailwind CSS через PostCSS (убран CDN)
- Исправлен Leaflet (убран CDN, добавлен npm пакет)
- Исправлен белый экран (добавлен entry point в index.html)
- Созданы скрипты деплоя для Windows (bat файлы)
- Создана документация по деплою
- Обновлен docker-compose.yml для работы с удаленной БД
- Добавлены скрипты диагностики и исправления проблем"

if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось создать коммит
    pause
    exit /b 1
)

echo [OK] Коммит создан

:push
echo.
echo [5] Отправка в удаленный репозиторий...
git push origin main
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось отправить изменения
    echo Попробуйте: git push origin main
    pause
    exit /b 1
)

echo.
echo ========================================
echo   ✅ ДЕПЛОЙ В GIT ЗАВЕРШЕН!
echo ========================================
echo.
pause

