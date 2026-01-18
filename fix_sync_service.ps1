$file = "mobile\lib\services\sync_service.dart"
$content = Get-Content $file -Raw

# Находим место где класс закрывается преждевременно (после getOfflineAssignments)
# и удаляем лишнюю закрывающую скобку перед методами saveOpoSurveyOffline

# Ищем паттерн: закрывающая скобка метода, затем закрывающая скобка класса, затем пустая строка, затем комментарий метода
$pattern = '(?s)(\s+}\s+)(})(\s+/// Сохранить опросник ОПО)'
$replacement = '$1$3'

if ($content -match $pattern) {
    $newContent = $content -replace $pattern, $replacement
    Set-Content $file -Value $newContent -NoNewline -Encoding UTF8
    Write-Host "Исправлено: удалена лишняя закрывающая скобка класса"
} else {
    Write-Host "Паттерн не найден, проверяю структуру..."
    # Альтернативный подход: просто удаляем закрывающую скобку на строке 442
    $lines = Get-Content $file
    $newLines = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq 441 -and $lines[$i].Trim() -eq '}') {
            # Пропускаем эту строку (лишняя закрывающая скобка)
            Write-Host "Удалена лишняя закрывающая скобка на строке $($i+1)"
            continue
        }
        $newLines += $lines[$i]
    }
    Set-Content $file -Value ($newLines -join "`n") -Encoding UTF8
    Write-Host "Файл исправлен"
}
