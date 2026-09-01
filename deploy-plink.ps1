# Deploy via PuTTY plink/pscp (password auth)
$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
if (-not $ProjectRoot) { $ProjectRoot = Get-Location.Path }
Set-Location $ProjectRoot

. (Join-Path $ProjectRoot "scripts\deploy-credentials.ps1")

$SERVER = $DEPLOY_SERVER
$REMOTE = $DEPLOY_REMOTE_PATH
$HOSTKEY = $DEPLOY_SSH_HOSTKEY
$PASSWORD = $DEPLOY_SSH_PASSWORD
$PLINK = Join-Path $ProjectRoot "tools\putty\plink.exe"
$PSCP = Join-Path $ProjectRoot "tools\putty\pscp.exe"

function Invoke-Remote([string]$Cmd, [switch]$AllowFail) {
    & $PLINK -batch -hostkey $HOSTKEY -ssh -pw $PASSWORD $SERVER $Cmd
    if (-not $AllowFail -and $LASTEXITCODE -ne 0) { throw "Remote command failed: $Cmd" }
}

function Copy-Remote([string]$Local, [string]$RemotePath) {
    & $PSCP -batch -hostkey $HOSTKEY -pw $PASSWORD -r $Local "${SERVER}:${RemotePath}"
    if ($LASTEXITCODE -ne 0) { throw "Copy failed: $Local -> $RemotePath" }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY VIA PLINK" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "[1/7] SSH check..." -ForegroundColor Yellow
Invoke-Remote "echo OK"
Write-Host "  OK" -ForegroundColor Green

Write-Host "[2/7] Remote directories..." -ForegroundColor Yellow
Invoke-Remote "mkdir -p $REMOTE/backend $REMOTE/nginx $REMOTE/pages $REMOTE/components $REMOTE/contexts $REMOTE/utils $REMOTE/styles $REMOTE/lib $REMOTE/mobile-apk $REMOTE/mobile"
Write-Host "  Done" -ForegroundColor Green

Write-Host "[2.5/7] .env..." -ForegroundColor Yellow
$localEnv = Join-Path $ProjectRoot ".env"
if (Test-Path $localEnv) {
    & $PSCP -batch -hostkey $HOSTKEY -pw $PASSWORD $localEnv "${SERVER}:${REMOTE}/.env"
    Write-Host "  .env copied" -ForegroundColor Green
} else {
    Write-Host "  keep server .env" -ForegroundColor Gray
}
Write-Host "[2.6/7] Server version env 3.7.30+67..." -ForegroundColor Yellow
Invoke-Remote "cd $REMOTE; touch .env; grep -q '^APP_VERSION=' .env && sed -i 's/^APP_VERSION=.*/APP_VERSION=3.7.30/' .env || echo APP_VERSION=3.7.30 >> .env; grep -q '^MOBILE_APP_VERSION=' .env && sed -i 's/^MOBILE_APP_VERSION=.*/MOBILE_APP_VERSION=3.7.30/' .env || echo MOBILE_APP_VERSION=3.7.30 >> .env; grep -q '^MOBILE_APP_BUILD=' .env && sed -i 's/^MOBILE_APP_BUILD=.*/MOBILE_APP_BUILD=67/' .env || echo MOBILE_APP_BUILD=67 >> .env; grep -E '^(APP_VERSION|MOBILE_APP_VERSION|MOBILE_APP_BUILD)=' .env"
Write-Host "  Version env updated" -ForegroundColor Green

Write-Host "[3/7] Copy files..." -ForegroundColor Yellow
Copy-Remote "backend\*" "$REMOTE/backend/"
Copy-Remote "nginx\*" "$REMOTE/nginx/"
Copy-Remote "pages\*" "$REMOTE/pages/"
if (Test-Path "components") { Copy-Remote "components\*" "$REMOTE/components/" }
if (Test-Path "contexts") { Copy-Remote "contexts\*" "$REMOTE/contexts/" }
if (Test-Path "utils") { Copy-Remote "utils\*" "$REMOTE/utils/" }
if (Test-Path "styles") { Copy-Remote "styles\*" "$REMOTE/styles/" }
if (Test-Path "lib") { Copy-Remote "lib\*" "$REMOTE/lib/" }

$rootFiles = @(
    "docker-compose.yml", "docker-compose.staging.yml", "frontend.Dockerfile", "App.tsx", "index.html", "index.tsx", "index.css",
    "package.json", "vite.config.ts", "tsconfig.json", "tailwind.config.js", "postcss.config.js",
    "constants.ts", "types.ts", "vite-env.d.ts"
)
foreach ($f in $rootFiles) {
    if (Test-Path $f) {
        & $PSCP -batch -hostkey $HOSTKEY -pw $PASSWORD $f "${SERVER}:${REMOTE}/"
    }
}
if (Test-Path "package-lock.json") { & $PSCP -batch -hostkey $HOSTKEY -pw $PASSWORD "package-lock.json" "${SERVER}:${REMOTE}/" }
if (Test-Path ".dockerignore") { & $PSCP -batch -hostkey $HOSTKEY -pw $PASSWORD ".dockerignore" "${SERVER}:${REMOTE}/.dockerignore" }

# pscp передаёт кириллические имена файлов как CP1251-байты (невалидный UTF-8),
# из-за чего docker build падает: "string field contains invalid UTF-8".
# Все формы имеют ASCII-алиасы to-N.docx, поэтому кириллические дубликаты удаляем.
Invoke-Remote "LC_ALL=C find $REMOTE/backend/report_forms -name '*[^ -~]*' -type f -delete" -AllowFail
Write-Host "  Files copied" -ForegroundColor Green

Write-Host "[3.2/7] Copy mobile source for server build..." -ForegroundColor Yellow
Invoke-Remote "mkdir -p $REMOTE/mobile/lib $REMOTE/mobile/android/app $REMOTE/mobile/assets"
$mobileItems = @("lib", "assets", "pubspec.yaml", "pubspec.lock", "analysis_options.yaml")
foreach ($item in $mobileItems) {
    $path = Join-Path "mobile" $item
    if (Test-Path $path) {
        if ((Get-Item $path).PSIsContainer) {
            Copy-Remote "$path\*" "$REMOTE/mobile/$item/"
        } else {
            & $PSCP -batch -hostkey $HOSTKEY -pw $PASSWORD $path "${SERVER}:${REMOTE}/mobile/"
        }
    }
}
$androidItems = @(
    "android\build.gradle", "android\build.gradle.kts", "android\settings.gradle", "android\settings.gradle.kts",
    "android\gradle.properties", "android\gradlew", "android\gradlew.bat", "android\init.gradle", "android\.gitignore"
)
foreach ($item in $androidItems) {
    if (Test-Path $item) {
        $remoteDir = Split-Path "$REMOTE/mobile/$($item -replace '\\','/')" -Parent
        Invoke-Remote "mkdir -p $remoteDir"
        & $PSCP -batch -hostkey $HOSTKEY -pw $PASSWORD $item "${SERVER}:${REMOTE}/mobile/$($item -replace '\\','/')"
    }
}
if (Test-Path "mobile\android\app") {
    Copy-Remote "mobile\android\app\*" "$REMOTE/mobile/android/app/"
}
if (Test-Path "mobile\android\gradle\wrapper") {
    Invoke-Remote "mkdir -p $REMOTE/mobile/android/gradle/wrapper"
    Copy-Remote "mobile\android\gradle\wrapper\*" "$REMOTE/mobile/android/gradle/wrapper/"
}
Write-Host "  Mobile source copied" -ForegroundColor Green

Write-Host "[4/7] Docker build (web first)..." -ForegroundColor Yellow
$buildRef = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Invoke-Remote "cd $REMOTE; export BUILD_REF=$buildRef; docker-compose build backend"
Invoke-Remote "cd $REMOTE; export BUILD_REF=$buildRef; docker-compose build frontend"
Write-Host "  Build done" -ForegroundColor Green

Write-Host "[5/7] Start stack..." -ForegroundColor Yellow
Invoke-Remote "cd $REMOTE; docker-compose run --rm backend python add_certification_area_column.py 2>/dev/null; docker-compose run --rm backend python add_certification_areas_column.py 2>/dev/null; docker-compose run --rm backend python add_inspection_grouping_columns.py 2>/dev/null; docker-compose up -d --remove-orphans"
Write-Host "  Done" -ForegroundColor Green

Write-Host "[3.5/7] Build APK on server (Flutter, optional)..." -ForegroundColor Yellow
try {
    $buildScriptLocal = Join-Path $ProjectRoot "tools\build-apk-server.sh"
    $content = [System.IO.File]::ReadAllText($buildScriptLocal).Replace("`r`n", "`n")
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($buildScriptLocal, $content, $utf8NoBom)
    & $PSCP -batch -hostkey $HOSTKEY -pw $PASSWORD $buildScriptLocal "${SERVER}:/tmp/build-apk-server.sh"
    Invoke-Remote "nohup bash /tmp/build-apk-server.sh > /tmp/build-apk.log 2>&1 &"
    Write-Host "  APK build started in background (see /tmp/build-apk.log)" -ForegroundColor Green
} catch {
    Write-Host "  APK build skipped: $_" -ForegroundColor Red
}

Write-Host "[6/7] Verify..." -ForegroundColor Yellow
Invoke-Remote "cd $REMOTE; docker-compose ps"
Invoke-Remote "curl -fsS http://127.0.0.1:8000/health" -AllowFail

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Site:   https://neftcontrol.ru/" -ForegroundColor White
Write-Host "Mobile: https://neftcontrol.ru/mobile/app.apk" -ForegroundColor White
Write-Host "Mobile: https://neftcontrol.ru/mobile/es-td-ngo-3.7.30-67.apk" -ForegroundColor White
