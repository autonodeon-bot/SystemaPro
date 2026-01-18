# Полная очистка и пересборка системы версии 3.8.1
$ErrorActionPreference = "Stop"

$server = "root@5.129.203.182"
$pw = "ydR9+CL3?S@dgH"
$appDir = "/opt/es-td-ngo"
$apkPath = "C:\DIANEKS\SYS\mobile\build\app\outputs\flutter-apk\app-release.apk"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ПОЛНАЯ ОЧИСТКА И ПЕРЕСБОРКА 3.8.1" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Шаг 1: Проверка и сборка APK
Write-Host "[1/8] Проверка APK..." -ForegroundColor Yellow
if (-not (Test-Path $apkPath)) {
    Write-Host "  APK не найден, собираю..." -ForegroundColor Yellow
    Set-Location "C:\DIANEKS\SYS\mobile"
    flutter build apk --release
    Set-Location "C:\DIANEKS\SYS"
    if (-not (Test-Path $apkPath)) {
        Write-Host "  ОШИБКА: Не удалось собрать APK!" -ForegroundColor Red
        exit 1
    }
}
Write-Host "  ✓ APK найден: $apkPath" -ForegroundColor Green
Write-Host ""

# Шаг 2: Полная остановка и удаление контейнеров
Write-Host "[2/8] Полная остановка и удаление контейнеров..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "cd $appDir; docker-compose down -v 2>&1"
plink -batch -ssh -pw $pw $server "docker ps -a | grep es_td_ngo | awk '{print `$1}' | xargs -r docker rm -f 2>&1"
Write-Host "  ✓ Контейнеры остановлены и удалены" -ForegroundColor Green
Write-Host ""

# Шаг 3: Удаление старых образов
Write-Host "[3/8] Удаление старых Docker образов..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "docker images | grep es-td-ngo | awk '{print `$3}' | xargs -r docker rmi -f 2>&1"
plink -batch -ssh -pw $pw $server "docker system prune -af --volumes 2>&1"
Write-Host "  ✓ Старые образы удалены" -ForegroundColor Green
Write-Host ""

# Шаг 4: Очистка кэша сборки на сервере
Write-Host "[4/8] Очистка кэша сборки..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "rm -rf $appDir/.docker 2>&1"
plink -batch -ssh -pw $pw $server "rm -rf $appDir/mobile-apk/* 2>&1"
Write-Host "  ✓ Кэш очищен" -ForegroundColor Green
Write-Host ""

# Шаг 5: Загрузка APK (реальный файл, не симлинк)
Write-Host "[5/8] Загрузка APK на сервер..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "mkdir -p $appDir/mobile-apk; rm -f $appDir/mobile-apk/app-release.apk"
pscp -batch -pw $pw $apkPath "${server}:$appDir/mobile-apk/app-release.apk"
plink -batch -ssh -pw $pw $server "chmod 644 $appDir/mobile-apk/app-release.apk; ls -lh $appDir/mobile-apk/app-release.apk"
Write-Host "  ✓ APK загружен" -ForegroundColor Green
Write-Host ""

# Шаг 6: Загрузка всех исходников в КОРЕНЬ проекта (контекст сборки)
Write-Host "[6/8] Загрузка исходников в корень проекта..." -ForegroundColor Yellow
# Backend
pscp -batch -pw $pw backend\main.py ${server}:$appDir/backend/
pscp -batch -pw $pw backend\models.py ${server}:$appDir/backend/ 2>$null
pscp -batch -pw $pw backend\word_generator.py ${server}:$appDir/backend/ 2>$null
pscp -batch -pw $pw backend\Dockerfile ${server}:$appDir/backend/ 2>$null

# Frontend - ВСЕ файлы в корень (frontend.Dockerfile использует context: .)
pscp -batch -pw $pw package.json ${server}:$appDir/
pscp -batch -pw $pw package-lock.json ${server}:$appDir/ 2>$null
pscp -batch -pw $pw App.tsx ${server}:$appDir/
pscp -batch -pw $pw -r pages\* ${server}:$appDir/pages/
pscp -batch -pw $pw -r src\* ${server}:$appDir/src/ 2>$null
pscp -batch -pw $pw -r contexts\* ${server}:$appDir/contexts/ 2>$null
pscp -batch -pw $pw -r components\* ${server}:$appDir/components/ 2>$null
pscp -batch -pw $pw vite.config.ts ${server}:$appDir/
pscp -batch -pw $pw tsconfig.json ${server}:$appDir/
pscp -batch -pw $pw index.html ${server}:$appDir/
pscp -batch -pw $pw index.tsx ${server}:$appDir/ 2>$null
pscp -batch -pw $pw index.css ${server}:$appDir/ 2>$null
pscp -batch -pw $pw tailwind.config.js ${server}:$appDir/ 2>$null
pscp -batch -pw $pw postcss.config.js ${server}:$appDir/ 2>$null
pscp -batch -pw $pw constants.ts ${server}:$appDir/ 2>$null
pscp -batch -pw $pw types.ts ${server}:$appDir/ 2>$null
pscp -batch -pw $pw frontend.Dockerfile ${server}:$appDir/
pscp -batch -pw $pw docker-compose.yml ${server}:$appDir/
pscp -batch -pw $pw -r nginx\* ${server}:$appDir/nginx/
Write-Host "  ✓ Исходники загружены" -ForegroundColor Green
Write-Host ""

# Шаг 7: Пересборка БЕЗ КЭША с pull
Write-Host "[7/8] Пересборка контейнеров БЕЗ КЭША..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "cd $appDir; docker-compose build --no-cache --pull backend frontend 2>&1"
Write-Host "  ✓ Контейнеры пересобраны" -ForegroundColor Green
Write-Host ""

# Шаг 8: Запуск контейнеров
Write-Host "[8/8] Запуск контейнеров..." -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "cd $appDir; docker-compose up -d 2>&1"
Write-Host "  ✓ Контейнеры запущены" -ForegroundColor Green
Write-Host ""

# Проверка результата
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ПРОВЕРКА РЕЗУЛЬТАТА" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Проверка контейнеров:" -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "docker ps | grep es_td_ngo"

Write-Host "`nПроверка APK файла:" -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "ls -lh $appDir/mobile-apk/app-release.apk"

Write-Host "`nПроверка версии в backend:" -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "docker exec es_td_ngo_backend grep -E 'version=|MOBILE_APP_VERSION' /app/main.py | head -3"

Write-Host "`nПроверка версии в frontend:" -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "docker exec es_td_ngo_frontend sh -c 'grep -r \"3.8.1\" /usr/share/nginx/html/*.html 2>/dev/null | head -2'"

Write-Host "`nПроверка доступности APK:" -ForegroundColor Yellow
plink -batch -ssh -pw $pw $server "curl -I http://127.0.0.1/mobile/app-release.apk 2>&1 | head -3"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  ДЕПЛОЙ ЗАВЕРШЕН" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Версия системы: 3.8.1" -ForegroundColor Green
Write-Host "APK доступен: http://5.129.203.182/mobile/app-release.apk" -ForegroundColor Green
Write-Host ""
Write-Host "ВАЖНО: Обновите страницу через Ctrl+Shift+R (жесткая перезагрузка)" -ForegroundColor Yellow
Write-Host ""
