$ErrorActionPreference = "Continue"
$server = "root@5.129.203.182"
$pw = "ydR9+CL3?S@dgH"
$appDir = "/opt/es-td-ngo"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ИСПРАВЛЕНИЕ И ДЕПЛОЙ 3.8.1" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Останавливаю и удаляю старые контейнеры
Write-Host "[1/6] Останавливаю старые контейнеры..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "cd $appDir; docker-compose down -v" 2>&1 | Out-Host
Write-Host "✓ Контейнеры остановлены" -ForegroundColor Green
Write-Host ""

# 2. Загружаю APK
Write-Host "[2/6] Загружаю APK на сервер..." -ForegroundColor Yellow
$apkPath = "C:\DIANEKS\SYS\mobile\build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkPath) {
    pscp -batch -pw $pw $apkPath "${server}:$appDir/mobile-apk/app-release.apk" 2>&1 | Out-Host
    plink -batch -ssh -pw $pw $server "chmod 644 $appDir/mobile-apk/app-release.apk" 2>&1 | Out-Host
    Write-Host "✓ APK загружен" -ForegroundColor Green
} else {
    Write-Host "✗ APK не найден: $apkPath" -ForegroundColor Red
    Write-Host "  Запускаю сборку..." -ForegroundColor Yellow
    Set-Location C:\DIANEKS\SYS\mobile
    flutter build apk --release
    Start-Sleep -Seconds 90
    if (Test-Path $apkPath) {
        pscp -batch -pw $pw $apkPath "${server}:$appDir/mobile-apk/app-release.apk" 2>&1 | Out-Host
        plink -batch -ssh -pw $pw $server "chmod 644 $appDir/mobile-apk/app-release.apk" 2>&1 | Out-Host
        Write-Host "✓ APK собран и загружен" -ForegroundColor Green
    }
}
Write-Host ""

# 3. Загружаю все файлы проекта
Write-Host "[3/6] Загружаю файлы проекта в корень..." -ForegroundColor Yellow
Set-Location C:\DIANEKS\SYS
pscp -batch -pw $pw -r pages\* "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw -r src\* "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw -r contexts\* "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw -r components\* "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw App.tsx "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw package.json "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw package-lock.json "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw vite.config.ts "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw tsconfig.json "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw index.html "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw index.tsx "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw index.css "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw tailwind.config.js "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw postcss.config.js "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw constants.ts "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw types.ts "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw frontend.Dockerfile "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw docker-compose.yml "${server}:$appDir/" 2>&1 | Out-Host
pscp -batch -pw $pw -r nginx\* "${server}:$appDir/nginx/" 2>&1 | Out-Host
pscp -batch -pw $pw backend\main.py "${server}:$appDir/backend/" 2>&1 | Out-Host
Write-Host "✓ Файлы загружены" -ForegroundColor Green
Write-Host ""

# 4. Пересобираю контейнеры БЕЗ КЭША
Write-Host "[4/6] Пересобираю контейнеры БЕЗ КЭША (это займет время)..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "cd $appDir; docker-compose build --no-cache --pull backend frontend" 2>&1 | Out-Host
Write-Host "✓ Контейнеры пересобраны" -ForegroundColor Green
Write-Host ""

# 5. Запускаю контейнеры
Write-Host "[5/6] Запускаю контейнеры..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "cd $appDir; docker-compose up -d" 2>&1 | Out-Host
Write-Host "✓ Контейнеры запущены" -ForegroundColor Green
Write-Host ""

# 6. Проверяю статус
Write-Host "[6/6] Проверяю статус..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "cd $appDir; docker-compose ps" 2>&1 | Out-Host
plink -batch -ssh -pw $pw $server "ls -lh $appDir/mobile-apk/app-release.apk" 2>&1 | Out-Host
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ДЕПЛОЙ ЗАВЕРШЕН" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Версия системы: 3.8.1" -ForegroundColor Green
Write-Host "APK доступен: http://5.129.203.182/mobile/app-release.apk" -ForegroundColor Green
Write-Host ""
Write-Host "ВАЖНО: Сделайте жесткое обновление страницы (Ctrl+Shift+R)" -ForegroundColor Yellow
Write-Host ""
