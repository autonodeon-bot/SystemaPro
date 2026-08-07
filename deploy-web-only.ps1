# Быстрый деплой веб + backend (без сборки APK на сервере)
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

Write-Host "=== RECOVER: free disk (optional) ===" -ForegroundColor Yellow
Invoke-Remote "docker container prune -f 2>/dev/null; docker builder prune -af 2>/dev/null; df -h /; echo RECOVERED" -AllowFail

Write-Host "=== COPY WEB + BACKEND ===" -ForegroundColor Yellow
Copy-Remote "backend\*" "$REMOTE/backend/"
Copy-Remote "nginx\*" "$REMOTE/nginx/"
Copy-Remote "pages\*" "$REMOTE/pages/"
if (Test-Path "components") { Copy-Remote "components\*" "$REMOTE/components/" }
if (Test-Path "contexts") { Copy-Remote "contexts\*" "$REMOTE/contexts/" }
if (Test-Path "utils") { Copy-Remote "utils\*" "$REMOTE/utils/" }
if (Test-Path "styles") { Copy-Remote "styles\*" "$REMOTE/styles/" }
if (Test-Path "lib") { Copy-Remote "lib\*" "$REMOTE/lib/" }

$rootFiles = @(
    "docker-compose.yml", "frontend.Dockerfile", "App.tsx", "index.html", "index.tsx", "index.css",
    "package.json", "vite.config.ts", "tsconfig.json", "tailwind.config.js", "postcss.config.js",
    "constants.ts", "types.ts", "vite-env.d.ts"
)
foreach ($f in $rootFiles) {
    if (Test-Path $f) {
        & $PSCP -batch -hostkey $HOSTKEY -pw $PASSWORD $f "${SERVER}:${REMOTE}/"
    }
}
if (Test-Path "package-lock.json") { & $PSCP -batch -hostkey $HOSTKEY -pw $PASSWORD "package-lock.json" "${SERVER}:${REMOTE}/" }

Write-Host "=== DOCKER BUILD (backend, then frontend) ===" -ForegroundColor Yellow
$buildRef = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Invoke-Remote "cd $REMOTE; export BUILD_REF=$buildRef; docker-compose build backend"
Invoke-Remote "cd $REMOTE; export BUILD_REF=$buildRef; docker-compose build frontend"

Write-Host "=== START STACK ===" -ForegroundColor Yellow
Invoke-Remote "cd $REMOTE; docker-compose up -d --remove-orphans"

Write-Host "=== VERIFY ===" -ForegroundColor Yellow
Invoke-Remote "cd $REMOTE; docker-compose ps"
Invoke-Remote "docker exec es_td_ngo_backend curl -sf http://127.0.0.1:8000/health || echo FAIL"

Write-Host "=== WEB DEPLOY DONE ===" -ForegroundColor Green
Write-Host "https://neftcontrol.ru/" -ForegroundColor White
