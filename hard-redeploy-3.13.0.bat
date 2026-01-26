@echo off
chcp 65001 >nul
echo ========================================
echo   FULL CLEANUP AND REBUILD 3.13.0
echo ========================================
echo.

set "SERVER=root@5.129.203.182"
set "PASSWORD=ydR9+CL3?S@dgH"
set "APP_DIR=/opt/es-td-ngo"
set "APK_FILE=mobile\build\app\outputs\flutter-apk\app-release.apk"

echo [1/9] Checking and building APK...
if not exist "%APK_FILE%" (
    echo   APK not found, building...
    cd mobile
    call flutter build apk --release
    cd ..
    if not exist "%APK_FILE%" (
        echo   ERROR: Failed to build APK!
        pause
        exit /b 1
    )
)
echo   [OK] APK found
echo.

echo [2/9] Stopping and removing containers...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR% && docker-compose down -v"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker ps -a | grep es_td_ngo | awk '{print $1}' | xargs -r docker rm -f"
echo   [OK] Containers stopped and removed
echo.

echo [3/9] Removing old Docker images...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker images | grep es-td-ngo | awk '{print $3}' | grep -v SIZE | xargs -r docker rmi -f 2>&1"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker system prune -af --volumes"
echo   [OK] Old images removed
echo.

echo [4/9] Cleaning build cache on server...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "rm -rf %APP_DIR%/.docker"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "rm -rf %APP_DIR%/mobile-apk/*"
echo   [OK] Cache cleaned
echo.

echo [5/9] Uploading APK to server...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "mkdir -p %APP_DIR%/mobile-apk && rm -f %APP_DIR%/mobile-apk/app-release.apk"
pscp -batch -pw "%PASSWORD%" "%APK_FILE%" "%SERVER%:%APP_DIR%/mobile-apk/app-release.apk"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "chmod 644 %APP_DIR%/mobile-apk/app-release.apk"
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "ls -lh %APP_DIR%/mobile-apk/app-release.apk"
echo   [OK] APK uploaded
echo.

echo [6/9] Uploading all source files to project root...
echo   Uploading backend...
pscp -batch -pw "%PASSWORD%" backend\main.py "%SERVER%:%APP_DIR%/backend/"
pscp -batch -pw "%PASSWORD%" backend\models.py "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" backend\report_generator.py "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" backend\word_generator.py "%SERVER%:%APP_DIR%/backend/" 2>nul
pscp -batch -pw "%PASSWORD%" backend\Dockerfile "%SERVER%:%APP_DIR%/backend/" 2>nul

echo   Uploading frontend to root (build context)...
pscp -batch -pw "%PASSWORD%" package.json "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" package-lock.json "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" App.tsx "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" -r pages\* "%SERVER%:%APP_DIR%/pages/"
if exist src (pscp -batch -pw "%PASSWORD%" -r src\* "%SERVER%:%APP_DIR%/src/" 2>nul)
if exist contexts (pscp -batch -pw "%PASSWORD%" -r contexts\* "%SERVER%:%APP_DIR%/contexts/" 2>nul)
if exist components (pscp -batch -pw "%PASSWORD%" -r components\* "%SERVER%:%APP_DIR%/components/" 2>nul)
pscp -batch -pw "%PASSWORD%" vite.config.ts "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" tsconfig.json "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" index.html "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" index.tsx "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" index.css "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" tailwind.config.js "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" postcss.config.js "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" constants.ts "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" types.ts "%SERVER%:%APP_DIR%/" 2>nul
pscp -batch -pw "%PASSWORD%" frontend.Dockerfile "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" docker-compose.yml "%SERVER%:%APP_DIR%/"
pscp -batch -pw "%PASSWORD%" -r nginx\* "%SERVER%:%APP_DIR%/nginx/"
echo   [OK] Source files uploaded
echo.

echo [7/9] Rebuilding containers WITHOUT CACHE...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR% && docker-compose build --no-cache --pull backend frontend"
echo   [OK] Containers rebuilt
echo.

echo [8/9] Starting containers...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "cd %APP_DIR% && docker-compose up -d"
echo   [OK] Containers started
echo.

echo [9/9] Cleaning nginx cache and restarting...
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_frontend sh -c 'rm -rf /var/cache/nginx/* && nginx -s reload'"
echo   [OK] Nginx cache cleaned
echo.

echo ========================================
echo   RESULT CHECK
echo ========================================
echo.

echo Checking containers:
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker ps | grep es_td_ngo"

echo.
echo Checking APK file:
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "ls -lh %APP_DIR%/mobile-apk/app-release.apk"

echo.
echo Checking version in backend:
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_backend grep -E 'version=|MOBILE_APP_VERSION' /app/main.py | head -3"

echo.
echo Checking version in frontend:
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "docker exec es_td_ngo_frontend sh -c 'grep -r \"3.13.0\" /usr/share/nginx/html/*.html 2>/dev/null | head -2'"

echo.
echo Checking APK availability:
plink -batch -ssh -pw "%PASSWORD%" "%SERVER%" "curl -I http://127.0.0.1/mobile/app-release.apk 2>&1 | head -3"

echo.
echo ========================================
echo   DEPLOYMENT COMPLETED
echo ========================================
echo.
echo System version: 3.13.0
echo APK available at: http://5.129.203.182/mobile/app-release.apk
echo.
echo IMPORTANT: Refresh page with Ctrl+Shift+R (hard reload)
echo.
pause
