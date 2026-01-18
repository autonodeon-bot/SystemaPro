$server = "root@5.129.203.182"
$pw = "ydR9+CL3?S@dgH"
$apkPath = "C:\DIANEKS\SYS\mobile\build\app\outputs\flutter-apk\app-release.apk"

if (Test-Path $apkPath) {
    $file = Get-Item $apkPath
    Write-Host "Найден APK: $($file.Name)"
    Write-Host "Размер: $([math]::Round($file.Length/1MB, 2)) MB"
    Write-Host "Загружаю на сервер..."
    
    pscp -batch -pw $pw $apkPath "${server}:/opt/es-td-ngo/mobile-apk/app-release.apk"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "APK скопирован на сервер"
        plink -batch -ssh -pw $pw $server "chmod 644 /opt/es-td-ngo/mobile-apk/app-release.apk"
        plink -batch -ssh -pw $pw $server "ls -lh /opt/es-td-ngo/mobile-apk/app-release.apk"
        Write-Host "`n✓ APK успешно загружен!"
        Write-Host "Файл доступен по адресу: http://5.129.203.182/mobile/app-release.apk"
    } else {
        Write-Host "Ошибка при загрузке APK"
    }
} else {
    Write-Host "APK не найден: $apkPath"
    Write-Host "Запускаю сборку..."
    Set-Location C:\DIANEKS\SYS\mobile
    flutter build apk --release
    
    Start-Sleep -Seconds 90
    
    if (Test-Path $apkPath) {
        Write-Host "APK собран, загружаю на сервер..."
        pscp -batch -pw $pw $apkPath "${server}:/opt/es-td-ngo/mobile-apk/app-release.apk"
        plink -batch -ssh -pw $pw $server "chmod 644 /opt/es-td-ngo/mobile-apk/app-release.apk"
        Write-Host "✓ APK загружен!"
    } else {
        Write-Host "Ошибка: APK не собран"
    }
}
