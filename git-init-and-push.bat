@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo   ИНИЦИАЛИЗАЦИЯ И ПУШ НА GITHUB
echo ========================================
echo.

REM Проверка наличия git
where git >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Git не установлен!
    pause
    exit /b 1
)

REM Проверка и инициализация репозитория
if not exist ".git" (
    echo [1/5] Инициализация git репозитория...
    git init
    if %ERRORLEVEL% NEQ 0 (
        echo [ОШИБКА] Не удалось инициализировать репозиторий!
        pause
        exit /b 1
    )
    echo [OK] Репозиторий инициализирован
    echo.
    
    echo [2/5] Настройка remote репозитория...
    echo.
    echo Введите URL вашего GitHub репозитория:
    echo Например: https://github.com/username/repo.git
    echo Или: git@github.com:username/repo.git
    echo.
    set /p REPO_URL="URL репозитория: "
    
    if "!REPO_URL!"=="" (
        echo [ОШИБКА] URL не введен!
        pause
        exit /b 1
    )
    
    git remote add origin "!REPO_URL!"
    if %ERRORLEVEL% NEQ 0 (
        echo [ОШИБКА] Не удалось добавить remote!
        pause
        exit /b 1
    )
    echo [OK] Remote настроен
    echo.
) else (
    echo [OK] Git репозиторий уже существует
    echo.
    git remote -v
    echo.
)

echo [3/5] Добавление файлов...
git add .
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось добавить файлы!
    pause
    exit /b 1
)
echo [OK] Файлы добавлены
echo.

echo [4/5] Создание коммита...
git commit -m "Версия 3.8.1: Обновления мобильного приложения, раскрывающийся список версий и исправления" -m "Обновлена версия мобильного приложения до 3.8.1 (build 6)" -m "Добавлен раскрывающийся список версий на странице 'Что нового' с анимацией" -m "Исправлена логика проверки обновлений: после установки APK приложение перепроверяет версию" -m "Исправлен MOBILE_APP_DOWNLOAD_URL в backend (правильный URL для скачивания APK)" -m "Обновлена конфигурация nginx: полное отключение кэша для всех файлов, включая APK" -m "Исправлена команда удаления Docker образов (фильтр SIZE)" -m "Добавлены скрипты для полной пересборки и деплоя системы" -m "Улучшена обработка ошибок при установке обновлений в мобильном приложении"
if %ERRORLEVEL% NEQ 0 (
    echo [ПРЕДУПРЕЖДЕНИЕ] Коммит не создан. Возможно, нет изменений.
    git status --short
    echo.
) else (
    echo [OK] Коммит создан
    echo.
)

echo [5/5] Отправка на GitHub...
echo.
echo Попытка отправить на origin/main...
git push -u origin main 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Попытка отправить на origin/master...
    git push -u origin master 2>&1
    if %ERRORLEVEL% NEQ 0 (
        echo.
        echo [ОШИБКА] Не удалось отправить на GitHub!
        echo.
        echo Возможные причины:
        echo 1. Неправильный URL репозитория
        echo 2. Нет прав доступа
        echo 3. Требуется аутентификация (настройте SSH ключи или токен)
        echo 4. Ветка не существует (создайте ветку main или master)
        echo.
        echo Проверьте настройки:
        git remote -v
        git branch
        echo.
        pause
        exit /b 1
    )
)
echo.
echo [OK] Изменения отправлены на GitHub
echo.

echo ========================================
echo   ГОТОВО
echo ========================================
echo.
echo Версия: 3.8.1
echo Коммит создан и отправлен на GitHub
echo.
pause
