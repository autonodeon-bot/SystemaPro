@echo off
chcp 65001 >nul
echo ========================================
echo  РЈР’Р•Р›РР§Р•РќРР• Р’Р•Р РЎРР РњРћР‘РР›Р¬РќРћР“Рћ РџР РР›РћР–Р•РќРРЇ
echo ========================================
echo.

REM Р•СЃР»Рё СѓСЃС‚Р°РЅРѕРІР»РµРЅР° РїРµСЂРµРјРµРЅРЅР°СЏ РѕРєСЂСѓР¶РµРЅРёСЏ NO_PAUSE=1 вЂ” РЅРµ РѕСЃС‚Р°РЅР°РІР»РёРІР°РµРјСЃСЏ РЅР° pause
if "%NO_PAUSE%"=="1" (
    set "SKIP_PAUSE=1"
)

set PUBSPEC_FILE=mobile\pubspec.yaml

if not exist "%PUBSPEC_FILE%" (
    echo РћС€РёР±РєР°: Р¤Р°Р№Р» %PUBSPEC_FILE% РЅРµ РЅР°Р№РґРµРЅ!
    if not defined SKIP_PAUSE pause
    exit /b 1
)

echo [*] Р§С‚РµРЅРёРµ С‚РµРєСѓС‰РµР№ РІРµСЂСЃРёРё РёР· %PUBSPEC_FILE%...

for /f "tokens=2 delims=: " %%a in ('findstr /C:"version:" "%PUBSPEC_FILE%"') do (
    set CURRENT_VERSION=%%a
)

echo РўРµРєСѓС‰Р°СЏ РІРµСЂСЃРёСЏ: %CURRENT_VERSION%

REM РџР°СЂСЃРёРј РІРµСЂСЃРёСЋ (С„РѕСЂРјР°С‚: X.Y.Z+BUILD)
for /f "tokens=1,2 delims=+" %%a in ("%CURRENT_VERSION%") do (
    set VERSION_PART=%%a
    set BUILD_PART=%%b
)

REM РЈРІРµР»РёС‡РёРІР°РµРј build number
set /a NEW_BUILD=%BUILD_PART%+1
set NEW_VERSION=%VERSION_PART%+%NEW_BUILD%

echo РќРѕРІР°СЏ РІРµСЂСЃРёСЏ: %NEW_VERSION%

REM Обновляем строку version: в pubspec.yaml (без regex-ошибок из-за символа '+')
powershell -NoProfile -Command "$c = Get-Content -Path '%PUBSPEC_FILE%' -Raw -Encoding UTF8; $c = [regex]::Replace($c, '(?m)^version:\s*.*$', 'version: %NEW_VERSION%'); Set-Content -Path '%PUBSPEC_FILE%' -Value $c -Encoding UTF8"

echo.
echo [вњ“] Р’РµСЂСЃРёСЏ СѓСЃРїРµС€РЅРѕ РѕР±РЅРѕРІР»РµРЅР°!
echo.
echo РЎС‚Р°СЂР°СЏ РІРµСЂСЃРёСЏ: %CURRENT_VERSION%
echo РќРѕРІР°СЏ РІРµСЂСЃРёСЏ:  %NEW_VERSION%
echo.
if not defined SKIP_PAUSE pause














