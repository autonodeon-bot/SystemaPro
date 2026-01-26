@echo off
chcp 65001 >nul
echo ========================================
echo   HARD REDEPLOY 3.12.0
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "APP_DIR=/opt/es-td-ngo"
set "APK_FILE=C:\DIANEKS\SYS\mobile\build\app\outputs\flutter-apk\app-release.apk"

echo [1/10] Build APK if missing...
if not exist "%APK_FILE%" (
    echo   APK not found, building...
    cd C:\DIANEKS\SYS\mobile
    call flutter clean
    call flutter pub get
    call flutter build apk --release
    cd C:\DIANEKS\SYS
    if not exist "%APK_FILE%" (
        echo   ERROR: APK build failed.
        pause
        exit /b 1
    )
)
echo   APK ready
echo.

echo [2/10] Stop and remove containers...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose down -v"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker ps -a | grep es_td_ngo | awk '{print $1}' | xargs -r docker rm -f"
echo   Containers stopped
echo.

echo [3/10] Remove old images...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker images | grep es-td-ngo | awk '{print $3}' | grep -v SIZE | xargs -r docker rmi -f 2>&1"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker system prune -af --volumes"
echo   Images removed
echo.

echo [4/10] Clear server build cache...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "rm -rf %APP_DIR%/.docker"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "rm -rf %APP_DIR%/mobile-apk/*"
echo   Cache cleared
echo.

echo [5/10] Upload APK to server...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "mkdir -p %APP_DIR%/mobile-apk; rm -f %APP_DIR%/mobile-apk/app-release.apk"
pscp -batch -pw "%PASSWORD%" "%APK_FILE%" "%SERVER%:%APP_DIR%/mobile-apk/app-release.apk"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "chmod 644 %APP_DIR%/mobile-apk/app-release.apk"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "ls -lh %APP_DIR%/mobile-apk/app-release.apk"
echo   APK uploaded
echo.

echo [6/10] Upload backend sources...
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\backend\main.py" "%SERVER%:%APP_DIR%/backend/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\backend\models.py" "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\backend\word_generator.py" "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\backend\report_generator.py" "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\backend\Dockerfile" "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\backend\requirements.txt" "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\backend\migrate_verification_scans.py" "%SERVER%:%APP_DIR%/backend/" 2>nul
echo   Backend uploaded
echo.

echo [7/10] Upload frontend sources...
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\package.json" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\package-lock.json" "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\App.tsx" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" -r "C:\DIANEKS\SYS\pages\*" "%SERVER%:%APP_DIR%/pages/"
if exist "C:\DIANEKS\SYS\src" (pscp -batch -pw "%PASSWORD%" -r "C:\DIANEKS\SYS\src\*" "%SERVER%:%APP_DIR%/src/" 2>nul)
if exist "C:\DIANEKS\SYS\contexts" (pscp -batch -pw "%PASSWORD%" -r "C:\DIANEKS\SYS\contexts\*" "%SERVER%:%APP_DIR%/contexts/" 2>nul)
if exist "C:\DIANEKS\SYS\components" (pscp -batch -pw "%PASSWORD%" -r "C:\DIANEKS\SYS\components\*" "%SERVER%:%APP_DIR%/components/" 2>nul)
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\vite.config.ts" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\tsconfig.json" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\index.html" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\index.tsx" "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\index.css" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\tailwind.config.js" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\postcss.config.js" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\constants.ts" "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\types.ts" "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\frontend.Dockerfile" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" "C:\DIANEKS\SYS\docker-compose.yml" "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" -r "C:\DIANEKS\SYS\nginx\*" "%SERVER%:%APP_DIR%/nginx/"
echo   Frontend uploaded
echo.

echo [8/10] Copy APK to nginx...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cp %APP_DIR%/mobile-apk/app-release.apk %APP_DIR%/nginx/html/mobile/app-release.apk"
echo   APK copied
echo.

echo [9/10] Rebuild containers (no cache)...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose build --no-cache --pull backend frontend"
echo   Containers built
echo.

echo [10/10] Start containers...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR%; docker-compose up -d"
echo   Containers running
echo.

echo [11/10] Clear nginx cache and reload...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_frontend sh -c 'rm -rf /var/cache/nginx/*; nginx -s reload'" 2>nul
echo   Nginx cache cleared
echo.

echo ========================================
echo   DEPLOY COMPLETE
echo ========================================
echo Version: 3.12.0
echo Mobile:  3.12.0 (build 10)
echo APK URL: http://5.129.203.182/mobile/app-release.apk
echo.
pause
