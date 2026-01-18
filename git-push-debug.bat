@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo   ПУШ ИЗМЕНЕНИЙ ВЕРСИИ 3.8.1 НА GITHUB
echo ========================================
echo.

REM Вывод в файл для диагностики
set "LOG_FILE=git-push-log.txt"
echo Дата: %DATE% %TIME% > "%LOG_FILE%"
echo. >> "%LOG_FILE%"

REM Проверка git
where git >> "%LOG_FILE%" 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Git не найден! >> "%LOG_FILE%"
    type "%LOG_FILE%"
    pause
    exit /b 1
)

REM Проверка репозитория
if not exist ".git" (
    echo [ОШИБКА] Git репозиторий не найден! >> "%LOG_FILE%"
    type "%LOG_FILE%"
    pause
    exit /b 1
)

REM Проверка remote
echo Проверка remote... >> "%LOG_FILE%"
git remote -v >> "%LOG_FILE%" 2>&1
echo. >> "%LOG_FILE%"

REM Добавление файлов
echo Добавление файлов... >> "%LOG_FILE%"
git add . >> "%LOG_FILE%" 2>&1
echo Статус после add: >> "%LOG_FILE%"
git status --short >> "%LOG_FILE%" 2>&1
echo. >> "%LOG_FILE%"

REM Создание коммита
echo Создание коммита... >> "%LOG_FILE%"
git commit -m "Версия 3.8.1: Обновления мобильного приложения, раскрывающийся список версий и исправления" >> "%LOG_FILE%" 2>&1
echo. >> "%LOG_FILE%"

REM Отправка на GitHub
echo Отправка на GitHub... >> "%LOG_FILE%"
git push >> "%LOG_FILE%" 2>&1
echo. >> "%LOG_FILE%"

REM Вывод результата
type "%LOG_FILE%"
echo.
echo Лог сохранен в: %LOG_FILE%
echo.
pause
