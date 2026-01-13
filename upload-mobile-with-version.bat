@echo off
chcp 65001 >nul
setlocal

echo ========================================
echo  UPLOAD MOBILE APK (auto version)
echo ========================================
echo.

REM If NO_PAUSE=1 then do not pause
if "%NO_PAUSE%"=="1" set "SKIP_PAUSE=1"

REM Increment build in pubspec.yaml (skip: set SKIP_INCREMENT=1)
if "%SKIP_INCREMENT%"=="1" goto after_increment
call mobile\increment-version.bat
if errorlevel 1 goto error
:after_increment

echo.
echo [*] Build APK... (skip: set SKIP_BUILD=1)
if "%SKIP_BUILD%"=="1" goto after_build
pushd mobile
call flutter build apk --release
if errorlevel 1 (
  popd
  goto error
)
popd
:after_build

echo.
echo [*] Read version from mobile\pubspec.yaml
for /f "tokens=2 delims=: " %%a in ('findstr /C:"version:" "mobile\pubspec.yaml"') do set "NEW_VERSION=%%a"

for /f "tokens=1,2 delims=+" %%a in ("%NEW_VERSION%") do (
  set "VERSION_PART=%%a"
  set "BUILD_PART=%%b"
)

set "APK_FILENAME=es-td-ngo-mobile-%VERSION_PART%-%BUILD_PART%.apk"
echo APK filename: %APK_FILENAME%

echo.
echo [*] Upload APK to server
pscp -batch -pw "ydR9+CL3?S@dgH" "mobile\build\app\outputs\flutter-apk\app-release.apk" "root@5.129.203.182:/tmp/app-release.apk"
if errorlevel 1 goto error

echo.
echo [*] Move APK on server and update symlink
plink -batch -ssh -pw "ydR9+CL3?S@dgH" "root@5.129.203.182" "mv /tmp/app-release.apk /opt/es-td-ngo/mobile-apk/%APK_FILENAME% && ln -sf /opt/es-td-ngo/mobile-apk/%APK_FILENAME% /opt/es-td-ngo/mobile-apk/app-release.apk"
if errorlevel 1 goto error

echo.
echo [*] Update links and backend mobile version constants
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\update_mobile_release.ps1 -VersionPart "%VERSION_PART%" -BuildPart "%BUILD_PART%" -ApkFilename "%APK_FILENAME%" -ServerIp "5.129.203.182"
if errorlevel 1 goto error

echo.
echo OK: uploaded %NEW_VERSION% as %APK_FILENAME%
echo.
if not defined SKIP_PAUSE pause
endlocal
exit /b 0

:error
echo.
echo ERROR: upload/build failed
echo.
if not defined SKIP_PAUSE pause
endlocal
exit /b 1
