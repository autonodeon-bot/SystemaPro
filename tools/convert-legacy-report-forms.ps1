$ErrorActionPreference = 'Stop'
$formsDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../backend/report_forms'))
$wordApp = New-Object -ComObject Word.Application
$wordApp.Visible = $false
$wordApp.DisplayAlerts = 0
try {
    foreach ($formNumber in @(11, 19, 20, 21, 37)) {
        $inputFile = Join-Path $formsDirectory "to-$formNumber.doc"
        $outputFile = Join-Path $formsDirectory "to-$formNumber.docx"
        if (Test-Path -LiteralPath $outputFile) { throw "Output already exists: $outputFile" }
        $document = $wordApp.Documents.Open($inputFile, $false, $true)
        try {
            $document.SaveAs2($outputFile, 16)
            Write-Output "Converted to-$formNumber.docx"
        } finally { $document.Close(0) }
    }
} finally { $wordApp.Quit() }
