@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo  РђР’РўРћРњРђРўРР§Р•РЎРљРР™ Р”Р•РџР›РћР™ РќРђ РЎР•Р Р’Р•Р 
echo ========================================
echo.

REM Р•СЃР»Рё СѓСЃС‚Р°РЅРѕРІР»РµРЅР° РїРµСЂРµРјРµРЅРЅР°СЏ РѕРєСЂСѓР¶РµРЅРёСЏ NO_PAUSE=1 вЂ” РЅРµ РѕСЃС‚Р°РЅР°РІР»РёРІР°РµРјСЃСЏ РЅР° pause
if "%NO_PAUSE%"=="1" (
    set "SKIP_PAUSE=1"
)

set SERVER_IP=5.129.203.182
set SERVER_USER=root
set SERVER_PASS=ydR9+CL3?S@dgH
set APP_DIR=/opt/es-td-ngo

echo [1/8] РџСЂРѕРІРµСЂРєР° РЅРµРѕР±С…РѕРґРёРјС‹С… С„Р°Р№Р»РѕРІ...
if not exist "backend\main.py" (
    echo [вќЊ] РћС€РёР±РєР°: backend\main.py РЅРµ РЅР°Р№РґРµРЅ
    if not defined SKIP_PAUSE pause
    exit /b 1
)
if not exist "docker-compose.yml" (
    echo [вќЊ] РћС€РёР±РєР°: docker-compose.yml РЅРµ РЅР°Р№РґРµРЅ
    if not defined SKIP_PAUSE pause
    exit /b 1
)
echo [вњ“] Р’СЃРµ С„Р°Р№Р»С‹ РЅР° РјРµСЃС‚Рµ
echo.

echo [2/8] РџСЂРѕРІРµСЂРєР° РїРѕРґРєР»СЋС‡РµРЅРёСЏ Рє СЃРµСЂРІРµСЂСѓ...
ping -n 1 %SERVER_IP% >nul 2>&1
if errorlevel 1 (
    echo [вќЊ] РЎРµСЂРІРµСЂ %SERVER_IP% РЅРµРґРѕСЃС‚СѓРїРµРЅ
    if not defined SKIP_PAUSE pause
    exit /b 1
)
echo [вњ“] РЎРµСЂРІРµСЂ РґРѕСЃС‚СѓРїРµРЅ
echo.

echo [3/8] РџРѕРґРєР»СЋС‡РµРЅРёРµ Рє СЃРµСЂРІРµСЂСѓ Рё СЃРѕР·РґР°РЅРёРµ РґРёСЂРµРєС‚РѕСЂРёР№...
echo y | plink -ssh -pw %SERVER_PASS% %SERVER_USER%@%SERVER_IP% "mkdir -p %APP_DIR% && mkdir -p %APP_DIR%/backend && mkdir -p %APP_DIR%/backend/reports && mkdir -p %APP_DIR%/backend/certs && mkdir -p %APP_DIR%/frontend && mkdir -p %APP_DIR%/nginx" 2>nul
if errorlevel 1 (
    echo [вљ ] РџСЂРѕРІРµСЂСЏСЋ Р°Р»СЊС‚РµСЂРЅР°С‚РёРІРЅС‹Р№ РјРµС‚РѕРґ РїРѕРґРєР»СЋС‡РµРЅРёСЏ...
    plink -ssh -batch -pw %SERVER_PASS% %SERVER_USER%@%SERVER_IP% "mkdir -p %APP_DIR% && mkdir -p %APP_DIR%/backend && mkdir -p %APP_DIR%/backend/reports && mkdir -p %APP_DIR%/backend/certs && mkdir -p %APP_DIR%/frontend && mkdir -p %APP_DIR%/nginx" 2>nul
)
echo [вњ“] Р”РёСЂРµРєС‚РѕСЂРёРё СЃРѕР·РґР°РЅС‹
echo.

echo [4/8] РљРѕРїРёСЂРѕРІР°РЅРёРµ backend С„Р°Р№Р»РѕРІ...
pscp -batch -pw %SERVER_PASS% -r backend\*.py %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/ 2>nul
pscp -batch -pw %SERVER_PASS% backend\requirements.txt %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/ 2>nul
pscp -batch -pw %SERVER_PASS% backend\Dockerfile %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/ 2>nul
if exist "backend\test_data.py" (
    pscp -batch -pw %SERVER_PASS% backend\test_data.py %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/ 2>nul
)
if exist "backend\auth.py" (
    pscp -batch -pw %SERVER_PASS% backend\auth.py %SERVER_USER%@%SERVER_IP%:%APP_DIR%/backend/ 2>nul
)
echo [вњ“] Backend С„Р°Р№Р»С‹ СЃРєРѕРїРёСЂРѕРІР°РЅС‹
echo.

echo [5/8] РљРѕРїРёСЂРѕРІР°РЅРёРµ frontend С„Р°Р№Р»РѕРІ...
REM ВАЖНО: копируем директории целиком (не pages\*), иначе структура ломается и на сервере остаются старые файлы в pages/
if exist "src" (
    pscp -batch -pw %SERVER_PASS% -r src %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "pages" (
    pscp -batch -pw %SERVER_PASS% -r pages %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "components" (
    pscp -batch -pw %SERVER_PASS% -r components %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "contexts" (
    pscp -batch -pw %SERVER_PASS% -r contexts %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "styles" (
    pscp -batch -pw %SERVER_PASS% -r styles %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "public" (
    pscp -batch -pw %SERVER_PASS% -r public %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "App.tsx" (
    pscp -batch -pw %SERVER_PASS% App.tsx %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "index.tsx" (
    pscp -batch -pw %SERVER_PASS% index.tsx %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "index.css" (
    pscp -batch -pw %SERVER_PASS% index.css %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "constants.ts" (
    pscp -batch -pw %SERVER_PASS% constants.ts %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "types.ts" (
    pscp -batch -pw %SERVER_PASS% types.ts %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "package.json" (
    pscp -batch -pw %SERVER_PASS% package.json %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "package-lock.json" (
    pscp -batch -pw %SERVER_PASS% package-lock.json %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "postcss.config.js" (
    pscp -batch -pw %SERVER_PASS% postcss.config.js %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "tailwind.config.js" (
    pscp -batch -pw %SERVER_PASS% tailwind.config.js %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "vite.config.ts" (
    pscp -batch -pw %SERVER_PASS% vite.config.ts %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "tsconfig.json" (
    pscp -batch -pw %SERVER_PASS% tsconfig.json %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "index.html" (
    pscp -batch -pw %SERVER_PASS% index.html %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
if exist "frontend.Dockerfile" (
    pscp -batch -pw %SERVER_PASS% frontend.Dockerfile %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
)
echo [вњ“] Frontend С„Р°Р№Р»С‹ СЃРєРѕРїРёСЂРѕРІР°РЅС‹
echo.

echo [6/8] РљРѕРїРёСЂРѕРІР°РЅРёРµ РєРѕРЅС„РёРіСѓСЂР°С†РёРѕРЅРЅС‹С… С„Р°Р№Р»РѕРІ...
pscp -batch -pw %SERVER_PASS% docker-compose.yml %SERVER_USER%@%SERVER_IP%:%APP_DIR%/ 2>nul
if exist "nginx" (
    pscp -batch -pw %SERVER_PASS% -r nginx\* %SERVER_USER%@%SERVER_IP%:%APP_DIR%/nginx/ 2>nul
)
echo [вњ“] РљРѕРЅС„РёРіСѓСЂР°С†РёРѕРЅРЅС‹Рµ С„Р°Р№Р»С‹ СЃРєРѕРїРёСЂРѕРІР°РЅС‹
echo.

echo [7/8] РЎРѕР·РґР°РЅРёРµ СЃРєСЂРёРїС‚Р° РґРµРїР»РѕСЏ РЅР° СЃРµСЂРІРµСЂРµ...
pscp -batch -pw %SERVER_PASS% deploy-simple.sh %SERVER_USER%@%SERVER_IP%:%APP_DIR%/deploy.sh 2>nul
plink -batch -ssh -pw %SERVER_PASS% %SERVER_USER%@%SERVER_IP% "chmod +x %APP_DIR%/deploy.sh && dos2unix %APP_DIR%/deploy.sh 2>/dev/null || sed -i 's/\r$//' %APP_DIR%/deploy.sh" 2>nul
echo [вњ“] РЎРєСЂРёРїС‚ РґРµРїР»РѕСЏ СЃРѕР·РґР°РЅ
echo.

echo [8/8] Р—Р°РїСѓСЃРє РґРµРїР»РѕСЏ РЅР° СЃРµСЂРІРµСЂРµ...
echo [*] Р­С‚Рѕ РјРѕР¶РµС‚ Р·Р°РЅСЏС‚СЊ РЅРµСЃРєРѕР»СЊРєРѕ РјРёРЅСѓС‚...
plink -batch -ssh -pw %SERVER_PASS% %SERVER_USER%@%SERVER_IP% "cd %APP_DIR% && ./deploy.sh"
if errorlevel 1 (
    echo [вљ ] РћС€РёР±РєР° РїСЂРё РІС‹РїРѕР»РЅРµРЅРёРё РґРµРїР»РѕСЏ РЅР° СЃРµСЂРІРµСЂРµ
    echo [*] РџРѕРїСЂРѕР±СѓР№С‚Рµ РїРѕРґРєР»СЋС‡РёС‚СЊСЃСЏ РІСЂСѓС‡РЅСѓСЋ:
    echo     ssh %SERVER_USER%@%SERVER_IP%
    echo     cd %APP_DIR%
    echo     ./deploy.sh
    goto :end
)

echo.
echo ========================================
echo  Р”Р•РџР›РћР™ Р—РђР’Р•Р РЁР•Рќ РЈРЎРџР•РЁРќРћ!
echo ========================================
echo.
echo РџСЂРѕРІРµСЂСЊС‚Рµ СЃС‚Р°С‚СѓСЃ:
echo   ssh %SERVER_USER%@%SERVER_IP%
echo   cd %APP_DIR%
echo   docker-compose ps
echo   docker-compose logs -f backend
echo.
echo API РґРѕСЃС‚СѓРїРµРЅ РїРѕ Р°РґСЂРµСЃСѓ:
echo   http://%SERVER_IP%:8000
echo   http://%SERVER_IP%:8000/health
echo.
echo Frontend РґРѕСЃС‚СѓРїРµРЅ РїРѕ Р°РґСЂРµСЃСѓ:
echo   http://%SERVER_IP%
echo.

:end
if not defined SKIP_PAUSE pause
endlocal

