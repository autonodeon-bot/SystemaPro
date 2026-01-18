$server = "root@5.129.203.182"
$pw = "ydR9+CL3?S@dgH"
$appDir = "/opt/es-td-ngo"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ПОЛНЫЙ ДЕПЛОЙ ВЕРСИИ 3.8.1" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Загрузка APK
Write-Host "[1/7] Загрузка APK на сервер..." -ForegroundColor Yellow
$apkPath = "C:\DIANEKS\SYS\mobile\build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkPath) {
    pscp -batch -pw $pw $apkPath "${server}:$appDir/mobile-apk/app-release.apk"
    plink -batch -ssh -pw $pw $server "chmod 644 $appDir/mobile-apk/app-release.apk"
    Write-Host "✓ APK загружен" -ForegroundColor Green
} else {
    Write-Host "✗ APK не найден: $apkPath" -ForegroundColor Red
}
Write-Host ""

# 2. Остановка контейнеров
Write-Host "[2/7] Остановка контейнеров..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "cd $appDir; docker-compose down"
Write-Host "✓ Контейнеры остановлены" -ForegroundColor Green
Write-Host ""

# 3. Загрузка backend
Write-Host "[3/7] Загрузка backend файлов..." -ForegroundColor Yellow
pscp -batch -pw $pw backend\main.py "${server}:$appDir/backend/"
Write-Host "✓ Backend файлы загружены" -ForegroundColor Green
Write-Host ""

# 4. Загрузка frontend исходников (в корень проекта, т.к. контекст сборки - корень)
Write-Host "[4/7] Загрузка frontend исходников..." -ForegroundColor Yellow
pscp -batch -pw $pw -r pages\* "${server}:$appDir/"
pscp -batch -pw $pw -r src\* "${server}:$appDir/" 2>$null
pscp -batch -pw $pw -r contexts\* "${server}:$appDir/" 2>$null
pscp -batch -pw $pw -r components\* "${server}:$appDir/" 2>$null
pscp -batch -pw $pw App.tsx "${server}:$appDir/"
pscp -batch -pw $pw package.json "${server}:$appDir/"
pscp -batch -pw $pw package-lock.json "${server}:$appDir/" 2>$null
pscp -batch -pw $pw vite.config.ts "${server}:$appDir/"
pscp -batch -pw $pw tsconfig.json "${server}:$appDir/"
pscp -batch -pw $pw index.html "${server}:$appDir/"
pscp -batch -pw $pw index.tsx "${server}:$appDir/" 2>$null
pscp -batch -pw $pw index.css "${server}:$appDir/" 2>$null
pscp -batch -pw $pw tailwind.config.js "${server}:$appDir/" 2>$null
pscp -batch -pw $pw postcss.config.js "${server}:$appDir/" 2>$null
pscp -batch -pw $pw constants.ts "${server}:$appDir/" 2>$null
pscp -batch -pw $pw types.ts "${server}:$appDir/" 2>$null
Write-Host "✓ Frontend исходники загружены" -ForegroundColor Green
Write-Host ""

# 5. Загрузка Docker файлов
Write-Host "[5/7] Загрузка Docker конфигурации..." -ForegroundColor Yellow
pscp -batch -pw $pw frontend.Dockerfile "${server}:$appDir/"
pscp -batch -pw $pw docker-compose.yml "${server}:$appDir/"
pscp -batch -pw $pw -r nginx\* "${server}:$appDir/nginx/"
Write-Host "✓ Docker конфигурация загружена" -ForegroundColor Green
Write-Host ""

# 6. Пересборка контейнеров БЕЗ КЭША
Write-Host "[6/7] Пересборка контейнеров БЕЗ КЭША (это займет время)..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "cd $appDir; docker-compose build --no-cache --pull backend frontend"
Write-Host "✓ Контейнеры пересобраны" -ForegroundColor Green
Write-Host ""

# 7. Запуск контейнеров
Write-Host "[7/7] Запуск контейнеров..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "cd $appDir; docker-compose up -d"
Write-Host "✓ Контейнеры запущены" -ForegroundColor Green
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ДЕПЛОЙ ЗАВЕРШЕН" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Версия системы: 3.8.1" -ForegroundColor Green
Write-Host "APK доступен: http://5.129.203.182/mobile/app-release.apk" -ForegroundColor Green
Write-Host ""
Write-Host "Проверяю статус контейнеров..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "cd $appDir; docker-compose ps"
