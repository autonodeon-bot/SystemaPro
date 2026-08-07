# Очистка диска и Docker на сервере (перед деплоем при нехватке места)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

. (Join-Path $PSScriptRoot "deploy-credentials.ps1")

$PLINK = Join-Path $ProjectRoot "tools\putty\plink.exe"
if (-not (Test-Path $PLINK)) { throw "plink.exe not found: $PLINK" }

$cleanupCmd = "echo '=== DISK BEFORE ==='; df -h /; echo '=== DOCKER DISK ==='; docker system df 2>/dev/null || true; echo '=== STOP HEAVY BUILDS ==='; pkill -f 'gradle|flutter build|docker-compose build' 2>/dev/null || true; sync; echo '=== PRUNE DOCKER ==='; docker container prune -f 2>/dev/null || true; docker image prune -af --filter 'until=168h' 2>/dev/null || true; docker builder prune -af 2>/dev/null || true; docker volume prune -f 2>/dev/null || true; echo '=== DISK AFTER ==='; df -h /; docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null | head -20; echo CLEANUP_DONE"

Write-Host "=== SERVER CLEANUP ===" -ForegroundColor Cyan
& $PLINK -batch -hostkey $DEPLOY_SSH_HOSTKEY -ssh -pw $DEPLOY_SSH_PASSWORD $DEPLOY_SERVER $cleanupCmd
if ($LASTEXITCODE -ne 0) { throw "Server cleanup failed (exit $LASTEXITCODE)" }
Write-Host "=== CLEANUP OK ===" -ForegroundColor Green
