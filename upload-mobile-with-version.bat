@echo off
chcp 65001 >nul
echo ========================================
echo  Р—РђР“Р РЈР—РљРђ РњРћР‘РР›Р¬РќРћР“Рћ РџР РР›РћР–Р•РќРРЇ РЎ РђР’РўРћРњРђРўРР§Р•РЎРљРРњ РЈР’Р•Р›РР§Р•РќРР•Рњ Р’Р•Р РЎРР
echo ========================================
echo.

REM Р•СЃР»Рё СѓСЃС‚Р°РЅРѕРІР»РµРЅР° РїРµСЂРµРјРµРЅРЅР°СЏ РѕРєСЂСѓР¶РµРЅРёСЏ NO_PAUSE=1 вЂ” РЅРµ РѕСЃС‚Р°РЅР°РІР»РёРІР°РµРјСЃСЏ РЅР° pause
if "%NO_PAUSE%"=="1" (
    set "SKIP_PAUSE=1"
)

REM Увеличиваем версию (можно пропустить: set SKIP_INCREMENT=1)
if "%SKIP_INCREMENT%"=="1" goto :after_increment
call mobile\increment-version.bat
if errorlevel 1 (
    echo Ошибка при увеличении версии!
    if not defined SKIP_PAUSE pause
    exit /b 1
)
:after_increment

echo.
echo [*] Сборка мобильного приложения... (можно пропустить: set SKIP_BUILD=1)
if "%SKIP_BUILD%"=="1" goto :after_build
cd mobile
call flutter build apk --release
if errorlevel 1 (
    echo Ошибка при сборке приложения!
    cd ..
    if not defined SKIP_PAUSE pause
    exit /b 1
)
cd ..
:after_build

echo.
echo [*] Р—Р°РіСЂСѓР·РєР° APK РЅР° СЃРµСЂРІРµСЂ...

REM Р§РёС‚Р°РµРј РЅРѕРІСѓСЋ РІРµСЂСЃРёСЋ РёР· pubspec.yaml
for /f "tokens=2 delims=: " %%a in ('findstr /C:"version:" "mobile\pubspec.yaml"') do (
    set NEW_VERSION=%%a
)

echo Р’РµСЂСЃРёСЏ РґР»СЏ Р·Р°РіСЂСѓР·РєРё: %NEW_VERSION%

REM Р¤РѕСЂРјРёСЂСѓРµРј РёРјСЏ С„Р°Р№Р»Р° СЃ РІРµСЂСЃРёРµР№
for /f "tokens=1,2 delims=+" %%a in ("%NEW_VERSION%") do (
    set VERSION_PART=%%a
    set BUILD_PART=%%b
)

REM Р—Р°РјРµРЅСЏРµРј С‚РѕС‡РєРё РЅР° РґРµС„РёСЃС‹ РґР»СЏ РёРјРµРЅРё С„Р°Р№Р»Р°
set VERSION_FILE=%VERSION_PART:.-=-%
set APK_FILENAME=es-td-ngo-mobile-%VERSION_FILE%-%BUILD_PART%.apk

echo РРјСЏ С„Р°Р№Р»Р°: %APK_FILENAME%

REM Р—Р°РіСЂСѓР¶Р°РµРј APK РЅР° СЃРµСЂРІРµСЂ
pscp -batch -pw "ydR9+CL3?S@dgH" "mobile\build\app\outputs\flutter-apk\app-release.apk" "root@5.129.203.182:/tmp/app-release.apk"

if errorlevel 1 (
    echo РћС€РёР±РєР° РїСЂРё Р·Р°РіСЂСѓР·РєРµ APK РЅР° СЃРµСЂРІРµСЂ!
    if not defined SKIP_PAUSE pause
    exit /b 1
)

REM РџРµСЂРµРёРјРµРЅРѕРІС‹РІР°РµРј С„Р°Р№Р» РЅР° СЃРµСЂРІРµСЂРµ Рё РєРѕРїРёСЂСѓРµРј РІ РЅСѓР¶РЅСѓСЋ РґРёСЂРµРєС‚РѕСЂРёСЋ
plink -batch -ssh -pw "ydR9+CL3?S@dgH" "root@5.129.203.182" "mv /tmp/app-release.apk /opt/es-td-ngo/frontend/dist/mobile/%APK_FILENAME% && ln -sf /opt/es-td-ngo/frontend/dist/mobile/%APK_FILENAME% /opt/es-td-ngo/frontend/dist/mobile/app-release.apk"

if errorlevel 1 (
    echo РћС€РёР±РєР° РїСЂРё РїРµСЂРµРёРјРµРЅРѕРІР°РЅРёРё APK РЅР° СЃРµСЂРІРµСЂРµ!
    if not defined SKIP_PAUSE pause
    exit /b 1
)

echo.
echo [*] РћР±РЅРѕРІР»РµРЅРёРµ РІРµСЂСЃРёРё РЅР° СЃР°Р№С‚Рµ...

REM РћР±РЅРѕРІР»СЏРµРј РІРµСЂСЃРёСЋ РЅР° СЃР°Р№С‚Рµ (С„РѕСЂРјР°С‚: X.Y.Z (build BUILD))
for /f "tokens=1,2 delims=+" %%a in ("%NEW_VERSION%") do (
    set VERSION_PART=%%a
    set BUILD_PART=%%b
)

REM РџРѕР»СѓС‡Р°РµРј С‚РµРєСѓС‰СѓСЋ РґР°С‚Сѓ РІ С„РѕСЂРјР°С‚Рµ DD.MM.YYYY
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set CURRENT_DATE=%datetime:~6,2%.%datetime:~4,2%.%datetime:~0,4%

echo РћР±РЅРѕРІР»РµРЅРёРµ РІРµСЂСЃРёРё РЅР° СЃР°Р№С‚Рµ: %VERSION_PART% (build %BUILD_PART%) РѕС‚ %CURRENT_DATE%

REM РћР±РЅРѕРІР»СЏРµРј СЃС‚СЂР°РЅРёС†Сѓ MobileApp.tsx
powershell -Command "$content = Get-Content 'pages\MobileApp.tsx' -Raw -Encoding UTF8; $pattern = 'Р’РµСЂСЃРёСЏ: [0-9.]+ \\(build [0-9]+\\) РѕС‚ [0-9.]+'; $replacement = 'Р’РµСЂСЃРёСЏ: %VERSION_PART% (build %BUILD_PART%) РѕС‚ %CURRENT_DATE%'; $content = $content -replace $pattern, $replacement; $downloadUrlPattern = 'const downloadUrl = ''http://5.129.203.182/mobile/[^'']+'''; $downloadUrlReplacement = 'const downloadUrl = ''http://5.129.203.182/mobile/%APK_FILENAME%'''; $content = $content -replace $downloadUrlPattern, $downloadUrlReplacement; $downloadAttrPattern = 'download=\"[^\"]+\"'; $downloadAttrReplacement = 'download=\"%APK_FILENAME%\"'; $content = $content -replace $downloadAttrPattern, $downloadAttrReplacement; $buttonTextPattern = 'РЎРєР°С‡Р°С‚СЊ РїСЂРёР»РѕР¶РµРЅРёРµ v[0-9.]+'; $buttonTextReplacement = 'РЎРєР°С‡Р°С‚СЊ РїСЂРёР»РѕР¶РµРЅРёРµ v%VERSION_PART%'; $content = $content -replace $buttonTextPattern, $buttonTextReplacement; Set-Content 'pages\MobileApp.tsx' -Value $content -Encoding UTF8"

REM РћР±РЅРѕРІР»СЏРµРј РІРµСЂСЃРёСЋ СЃРёСЃС‚РµРјС‹ РІ App.tsx
powershell -Command "$content = Get-Content 'App.tsx' -Raw -Encoding UTF8; $pattern = 'v[0-9.]+\([0-9]+\)'; $replacement = 'v%VERSION_PART%(%BUILD_PART%)'; $content = $content -replace $pattern, $replacement; Set-Content 'App.tsx' -Value $content -Encoding UTF8"

echo.
echo [вњ“] РњРѕР±РёР»СЊРЅРѕРµ РїСЂРёР»РѕР¶РµРЅРёРµ СѓСЃРїРµС€РЅРѕ Р·Р°РіСЂСѓР¶РµРЅРѕ!
echo.
echo Р’РµСЂСЃРёСЏ: %NEW_VERSION%
echo Р”Р°С‚Р°: %CURRENT_DATE%
echo.
if not defined SKIP_PAUSE pause


