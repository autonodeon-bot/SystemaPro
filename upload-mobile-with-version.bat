@echo off
chcp 65001 >nul
echo ========================================
echo  ЗАГРУЗКА МОБИЛЬНОГО ПРИЛОЖЕНИЯ С АВТОМАТИЧЕСКИМ УВЕЛИЧЕНИЕМ ВЕРСИИ
echo ========================================
echo.

REM Увеличиваем версию
call mobile\increment-version.bat
if errorlevel 1 (
    echo Ошибка при увеличении версии!
    pause
    exit /b 1
)

echo.
echo [*] Сборка мобильного приложения...
cd mobile
call flutter build apk --release
if errorlevel 1 (
    echo Ошибка при сборке приложения!
    cd ..
    pause
    exit /b 1
)
cd ..

echo.
echo [*] Загрузка APK на сервер...

REM Читаем новую версию из pubspec.yaml
for /f "tokens=2 delims=: " %%a in ('findstr /C:"version:" "mobile\pubspec.yaml"') do (
    set NEW_VERSION=%%a
)

echo Версия для загрузки: %NEW_VERSION%

REM Формируем имя файла с версией
for /f "tokens=1,2 delims=+" %%a in ("%NEW_VERSION%") do (
    set VERSION_PART=%%a
    set BUILD_PART=%%b
)

REM Заменяем точки на дефисы для имени файла
set VERSION_FILE=%VERSION_PART:.-=-%
set APK_FILENAME=es-td-ngo-mobile-%VERSION_FILE%-%BUILD_PART%.apk

echo Имя файла: %APK_FILENAME%

REM Загружаем APK на сервер
pscp -batch -pw "ydR9+CL3?S@dgH" "mobile\build\app\outputs\flutter-apk\app-release.apk" "root@5.129.203.182:/tmp/app-release.apk"

if errorlevel 1 (
    echo Ошибка при загрузке APK на сервер!
    pause
    exit /b 1
)

REM Переименовываем файл на сервере и копируем в нужную директорию
plink -batch -ssh -pw "ydR9+CL3?S@dgH" "root@5.129.203.182" "mv /tmp/app-release.apk /opt/es-td-ngo/frontend/dist/mobile/%APK_FILENAME% && ln -sf /opt/es-td-ngo/frontend/dist/mobile/%APK_FILENAME% /opt/es-td-ngo/frontend/dist/mobile/app-release.apk"

if errorlevel 1 (
    echo Ошибка при переименовании APK на сервере!
    pause
    exit /b 1
)

echo.
echo [*] Обновление версии на сайте...

REM Обновляем версию на сайте (формат: X.Y.Z (build BUILD))
for /f "tokens=1,2 delims=+" %%a in ("%NEW_VERSION%") do (
    set VERSION_PART=%%a
    set BUILD_PART=%%b
)

REM Получаем текущую дату в формате DD.MM.YYYY
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set CURRENT_DATE=%datetime:~6,2%.%datetime:~4,2%.%datetime:~0,4%

echo Обновление версии на сайте: %VERSION_PART% (build %BUILD_PART%) от %CURRENT_DATE%

REM Обновляем страницу MobileApp.tsx
powershell -Command "$content = Get-Content 'pages\MobileApp.tsx' -Raw -Encoding UTF8; $pattern = 'Версия: [0-9.]+ \\(build [0-9]+\\) от [0-9.]+'; $replacement = 'Версия: %VERSION_PART% (build %BUILD_PART%) от %CURRENT_DATE%'; $content = $content -replace $pattern, $replacement; $downloadUrlPattern = 'const downloadUrl = ''http://5.129.203.182/mobile/[^'']+'''; $downloadUrlReplacement = 'const downloadUrl = ''http://5.129.203.182/mobile/%APK_FILENAME%'''; $content = $content -replace $downloadUrlPattern, $downloadUrlReplacement; $downloadAttrPattern = 'download=\"[^\"]+\"'; $downloadAttrReplacement = 'download=\"%APK_FILENAME%\"'; $content = $content -replace $downloadAttrPattern, $downloadAttrReplacement; $buttonTextPattern = 'Скачать приложение v[0-9.]+'; $buttonTextReplacement = 'Скачать приложение v%VERSION_PART%'; $content = $content -replace $buttonTextPattern, $buttonTextReplacement; Set-Content 'pages\MobileApp.tsx' -Value $content -Encoding UTF8"

REM Обновляем версию системы в App.tsx
powershell -Command "$content = Get-Content 'App.tsx' -Raw -Encoding UTF8; $pattern = 'v[0-9.]+\([0-9]+\)'; $replacement = 'v%VERSION_PART%(%BUILD_PART%)'; $content = $content -replace $pattern, $replacement; Set-Content 'App.tsx' -Value $content -Encoding UTF8"

echo.
echo [✓] Мобильное приложение успешно загружено!
echo.
echo Версия: %NEW_VERSION%
echo Дата: %CURRENT_DATE%
echo.
pause

