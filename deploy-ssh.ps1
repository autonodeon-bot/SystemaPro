# Deploy to server via SSH key (no password)
# See DEPLOY-SSH.md for SSH key setup

$ErrorActionPreference = "Stop"
$SERVER = "root@5.129.203.182"
$REMOTE = "/opt/es-td-ngo"

$ProjectRoot = $PSScriptRoot
if (-not $ProjectRoot) { $ProjectRoot = Get-Location.Path }
Set-Location $ProjectRoot

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY VIA SSH" -ForegroundColor Cyan
Write-Host "  Project: $ProjectRoot" -ForegroundColor Gray
Write-Host "  Server:  $SERVER" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/7] Checking SSH connection..." -ForegroundColor Yellow
try {
    $null = ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new $SERVER "echo OK"
} catch {
    Write-Host "ERROR: Cannot connect via SSH. Add key to server. See DEPLOY-SSH.md" -ForegroundColor Red
    exit 1
}
Write-Host "  OK" -ForegroundColor Green
Write-Host ""

Write-Host "[2/7] Creating remote directories..." -ForegroundColor Yellow
ssh $SERVER "mkdir -p $REMOTE/backend $REMOTE/nginx $REMOTE/pages $REMOTE/components $REMOTE/contexts $REMOTE/utils $REMOTE/styles $REMOTE/mobile-apk"
Write-Host "  Done" -ForegroundColor Green
Write-Host ""

Write-Host "[3/7] Copying files..." -ForegroundColor Yellow
$dest = "${SERVER}`:${REMOTE}"
scp -r backend/* "${dest}/backend/"
scp -r nginx/* "${dest}/nginx/"
scp -r pages/* "${dest}/pages/"
if (Test-Path "components") { scp -r components/* "${dest}/components/" }
if (Test-Path "contexts") { scp -r contexts/* "${dest}/contexts/" }
if (Test-Path "utils") { scp -r utils/* "${dest}/utils/" }
if (Test-Path "styles") { scp -r styles/* "${dest}/styles/" }

$rootFiles = @(
    "docker-compose.yml", "frontend.Dockerfile", "App.tsx", "index.html", "index.tsx", "index.css",
    "package.json", "vite.config.ts", "tsconfig.json", "tailwind.config.js", "postcss.config.js",
    "constants.ts", "types.ts"
)
foreach ($f in $rootFiles) {
    if (Test-Path $f) {
        scp $f "${dest}/"
    }
}
if (Test-Path "package-lock.json") { scp package-lock.json "${dest}/" }
Write-Host "  Files copied" -ForegroundColor Green
Write-Host ""

# Mobile app: force build APK and upload
$apkPath = "mobile\build\app\outputs\flutter-apk\app-release.apk"
Write-Host "[3.5/7] Building mobile APK (Flutter)..." -ForegroundColor Yellow
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutterCmd) {
    $buildOk = $true
    Push-Location (Join-Path $ProjectRoot "mobile")
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
        flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }
    } catch {
        $buildOk = $false
        Write-Host "  Warning: APK rebuild failed. Existing file will be uploaded if present." -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
    if ($buildOk) {
        Write-Host "  APK rebuilt successfully" -ForegroundColor Green
    }
} else {
    Write-Host "  Flutter not found in PATH. Existing APK will be uploaded if present." -ForegroundColor Yellow
}
if (Test-Path $apkPath) {
    Write-Host "[3.5/7] Uploading mobile APK to server..." -ForegroundColor Yellow
    scp $apkPath "${dest}/mobile-apk/app-release.apk"
    $versionLine = Get-Content "mobile\pubspec.yaml" | Where-Object { $_.TrimStart().StartsWith("version:") } | Select-Object -First 1
    if ($versionLine) {
        $parts = $versionLine.Split(":", 2)
        $verRaw = if ($parts.Count -ge 2) { $parts[1].Trim() } else { "" }
        if ($verRaw.Length -gt 0) {
            $ver = $verRaw.Replace("+", "-")
            $name = "es-td-ngo-$ver.apk"
            ssh $SERVER "cp $REMOTE/mobile-apk/app-release.apk $REMOTE/mobile-apk/$name"
        }
    }
    ssh $SERVER "chmod -R a+rX $REMOTE/mobile-apk"
    Write-Host "  APK загружен -> http://5.129.203.182/mobile/app-release.apk" -ForegroundColor Green
}
Write-Host ""

Write-Host "[4/7] Building containers (no cache)..." -ForegroundColor Yellow
ssh $SERVER "cd $REMOTE; docker-compose build --no-cache backend frontend"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Build failed. Check output above." -ForegroundColor Red
    exit 1
}
Write-Host "  Build done" -ForegroundColor Green
Write-Host ""

Write-Host "[5/7] Building, migrating and starting (single SSH session)..." -ForegroundColor Yellow
ssh $SERVER "cd $REMOTE && docker-compose build --no-cache backend frontend && (docker-compose run --rm backend python add_certification_area_column.py || true) && (docker-compose run --rm backend python add_certification_areas_column.py || true) && (docker-compose run --rm backend python add_inspection_grouping_columns.py || true) && docker-compose up -d"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Build or start failed. Check output above." -ForegroundColor Red
    exit 1
}
Write-Host "  Done" -ForegroundColor Green
Write-Host ""

Write-Host "[6/7] Verifying..." -ForegroundColor Yellow
ssh $SERVER "cd $REMOTE && docker-compose ps"
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DEPLOY COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Site:   https://neftcontrol.ru/ (HTTP: http://5.129.203.182/)" -ForegroundColor White
Write-Host "API:    https://neftcontrol.ru/api/ (HTTP: http://5.129.203.182:8000/)" -ForegroundColor White
Write-Host "Mobile: https://neftcontrol.ru/mobile/app-release.apk" -ForegroundColor White
Write-Host ""
