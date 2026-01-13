[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)] [string] $VersionPart,
  [Parameter(Mandatory=$true)] [string] $BuildPart,
  [Parameter(Mandatory=$true)] [string] $ApkFilename,
  [Parameter(Mandatory=$true)] [string] $ServerIp
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Replace-TextFile {
  param(
    [Parameter(Mandatory=$true)] [string] $Path,
    [Parameter(Mandatory=$true)] [scriptblock] $Transform
  )

  $full = Join-Path $root $Path
  if (-not (Test-Path $full)) {
    throw "Файл не найден: $Path"
  }

  $content = Get-Content -Path $full -Raw -Encoding UTF8
  $new = & $Transform $content
  if ($new -ne $content) {
    Set-Content -Path $full -Value $new -Encoding UTF8
  }
}

# 1) pages/MobileApp.tsx
Replace-TextFile -Path 'pages\\MobileApp.tsx' -Transform {
  param($c)

  $url = "http://$ServerIp/mobile/$ApkFilename"

  # const downloadUrl
  $c = $c -replace "const\s+downloadUrl\s*=\s*'http://[^']+/mobile/[^']+';", "const downloadUrl = '$url';"

  # build string inside "Версия: X.Y.Z (build N)"
  $c = $c -replace "Версия:\s*\d+\.\d+\.\d+\s*\(build\s*\d+\)", ("Версия: $VersionPart (build $BuildPart)")

  # download attribute
  $c = $c -replace "download=\"es-td-ngo-mobile-[^\"]+\"", ("download=\"$ApkFilename\"")

  # button text "(build N)"
  $c = $c -replace "\(build\s*\d+\)\s*\(APK\)", ("(build $BuildPart) (APK)")

  return $c
}

# 2) backend/main.py (MOBILE_APP_BUILD + URL)
Replace-TextFile -Path 'backend\\main.py' -Transform {
  param($c)

  $c = $c -replace 'MOBILE_APP_BUILD\s*=\s*"\d+"', ("MOBILE_APP_BUILD = \"$BuildPart\"")
  $c = $c -replace 'MOBILE_APP_DOWNLOAD_URL\s*=\s*"http://[^\"]+/mobile/[^\"]+"', ("MOBILE_APP_DOWNLOAD_URL = \"http://$ServerIp/mobile/$ApkFilename\"")

  return $c
}

Write-Host "OK: MobileApp.tsx + backend/main.py обновлены под $VersionPart (build $BuildPart)" -ForegroundColor Green
