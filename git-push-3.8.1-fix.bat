@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo   ПУШ ИЗМЕНЕНИЙ ВЕРСИИ 3.8.1 НА GITHUB
echo ========================================
echo.

REM Проверка наличия git
where git >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Git не установлен или не найден в PATH!
    pause
    exit /b 1
)
echo [OK] Git найден
echo.

REM Проверка наличия репозитория
if not exist ".git" (
    echo [ОШИБКА] Git репозиторий не найден в текущей директории!
    echo Инициализирую репозиторий...
    git init
    if %ERRORLEVEL% NEQ 0 (
        echo [ОШИБКА] Не удалось инициализировать репозиторий!
        pause
        exit /b 1
    )
    echo [OK] Репозиторий инициализирован
    echo.
    echo [ВНИМАНИЕ] Необходимо настроить remote репозиторий!
    echo Выполните: git remote add origin YOUR_REPO_URL
    echo Или: git remote set-url origin YOUR_REPO_URL
    echo.
    pause
    exit /b 1
)
echo [OK] Git репозиторий найден
echo.

REM Проверка remote
git remote -v >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Remote репозиторий не настроен!
    echo.
    echo Текущие remote:
    git remote -v
    echo.
    echo Необходимо настроить remote:
    echo   git remote add origin YOUR_REPO_URL
    echo Или:
    echo   git remote set-url origin YOUR_REPO_URL
    echo.
    pause
    exit /b 1
)
echo [OK] Remote репозиторий настроен:
git remote -v
echo.

echo [1/4] Проверка статуса...
git status --short
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось проверить статус!
    pause
    exit /b 1
)
echo.

echo [2/4] Добавление всех изменений...
git add .
if %ERRORLEVEL% NEQ 0 (
    echo [ОШИБКА] Не удалось добавить файлы!
    pause
    exit /b 1
)
echo [OK] Файлы добавлены
echo.

echo [3/4] Создание коммита...
git commit -m "Версия 3.8.1: Обновления мобильного приложения, раскрывающийся список версий и исправления" -m "Обновлена версия мобильного приложения до 3.8.1 (build 6)" -m "Добавлен раскрывающийся список версий на странице 'Что нового' с анимацией" -m "Исправлена логика проверки обновлений: после установки APK приложение перепроверяет версию" -m "Исправлен MOBILE_APP_DOWNLOAD_URL в backend (правильный URL для скачивания APK)" -m "Обновлена конфигурация nginx: полное отключение кэша для всех файлов, включая APK" -m "Исправлена команда удаления Docker образов (фильтр SIZE)" -m "Добавлены скрипты для полной пересборки и деплоя системы" -m "Улучшена обработка ошибок при установке обновлений в мобильном приложении"
if %ERRORLEVEL% NEQ 0 (
    echo [ПРЕДУПРЕЖДЕНИЕ] Коммит не создан. Возможно, нет изменений для коммита.
    echo Проверяю статус...
    git status --short
    echo.
    echo Если есть изменения, они уже закоммичены или нет изменений для коммита.
    echo.
) else (
    echo [OK] Коммит создан
    echo.
)

echo [4/4] Отправка на GitHub...
git push
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ОШИБКА] Не удалось отправить на GitHub!
    echo.
    echo Возможные причины:
    echo 1. Не настроен remote репозиторий
    echo 2. Нет прав доступа к репозиторию
    echo 3. Нет подключения к интернету
    echo 4. Требуется аутентификация
    echo.
    echo Проверьте настройки:
    git remote -v
    echo.
    echo Попробуйте выполнить вручную:
    echo   git push origin main
    echo Или:
    echo   git push origin master
    echo.
    pause
    exit /b 1
)
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
