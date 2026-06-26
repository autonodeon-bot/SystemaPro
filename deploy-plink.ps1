# Deploy via PuTTY plink/pscp (password auth)
$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
if (-not $ProjectRoot) { $ProjectRoot = Get-Location.Path }
Set-Location $ProjectRoot

$SERVER = "root@5.129.203.182"
$REMOTE = "/opt/es-td-ngo"
$HOSTKEY = "SHA256:0le6080AaJ2eq4TG//RZ7kRC5J7PyfsloqaGt2N7VQM"
$PASSWORD = "ydR9+CL3?S@dgH"
$PLINK = Join-Path $ProjectRoot "tools\putty\plink.exe"
$PSCP = Join-Path $ProjectRoot "tools\putty\pscp.exe"

function Invoke-Remote([string]$Cmd) {
    & $PLINK -batch -hostkey $HOSTKEY -ssh -pw $PASSWORD $SERVER $Cmd
    if ($LASTEXITCODE -ne 0) { throw "Remote command failed: $Cmd" }
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
Write-Host "  Files copied" -ForegroundColor Green

Write-Host "[3.2/7] Copy mobile source for server build..." -ForegroundColor Yellow
Invoke-Remote "mkdir -p $REMOTE/mobile/lib $REMOTE/mobile/android $REMOTE/mobile/assets"
$mobileItems = @("lib", "android", "assets", "pubspec.yaml", "pubspec.lock", "analysis_options.yaml")
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
Write-Host "  Mobile source copied" -ForegroundColor Green

Write-Host "[3.5/7] Build APK on server (Flutter)..." -ForegroundColor Yellow
$buildScriptLocal = Join-Path $ProjectRoot "tools\build-apk-server.sh"
$content = [System.IO.File]::ReadAllText($buildScriptLocal).Replace("`r`n", "`n")
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($buildScriptLocal, $content, $utf8NoBom)
& $PSCP -batch -hostkey $HOSTKEY -pw $PASSWORD $buildScriptLocal "${SERVER}:/tmp/build-apk-server.sh"
Invoke-Remote "chmod +x /tmp/build-apk-server.sh; bash /tmp/build-apk-server.sh > /tmp/build-apk.log 2>&1"
Invoke-Remote "test -f $REMOTE/mobile-apk/es-td-ngo-3.7.4-41.apk"
Write-Host "  APK built on server" -ForegroundColor Green

Write-Host "[4/7] Docker build..." -ForegroundColor Yellow
$buildRef = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Invoke-Remote "cd $REMOTE; export BUILD_REF=$buildRef; docker-compose build backend"
Invoke-Remote "cd $REMOTE; export BUILD_REF=$buildRef; docker-compose build frontend"
Write-Host "  Build done" -ForegroundColor Green

Write-Host "[5/7] Start stack..." -ForegroundColor Yellow
Invoke-Remote "cd $REMOTE; docker-compose run --rm backend python add_certification_area_column.py 2>/dev/null; docker-compose run --rm backend python add_certification_areas_column.py 2>/dev/null; docker-compose run --rm backend python add_inspection_grouping_columns.py 2>/dev/null; docker-compose up -d --remove-orphans"
Write-Host "  Done" -ForegroundColor Green

Write-Host "[6/7] Verify..." -ForegroundColor Yellow
Invoke-Remote "cd $REMOTE; docker-compose ps"
Invoke-Remote "docker exec es_td_ngo_backend python -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:8000/health').read().decode())\" 2>/dev/null || true"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Site:   https://neftcontrol.ru/" -ForegroundColor White
Write-Host "Mobile: https://neftcontrol.ru/mobile/es-td-ngo-3.7.4-41.apk" -ForegroundColor White
