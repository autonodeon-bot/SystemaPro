param(
  [string]$Path = "mobile\lib\services\sync_service.dart"
)

$ErrorActionPreference = "Stop"

$content = Get-Content -Path $Path -Raw -Encoding UTF8

$marker = "addAttachmentIfPresent('control_scheme_image');"
if ($content -match [regex]::Escape($marker)) {
  $insert = @'
      // VIK defect photos (if any)
      final visualDefects = checklistJson['visual_defects'];
      if (visualDefects is List) {
        for (var i = 0; i < visualDefects.length; i++) {
          final d = visualDefects[i];
          if (d is Map) {
            final photos = d['photos'];
            if (photos is List) {
              for (var j = 0; j < photos.length; j++) {
                final p = photos[j];
                if (p is String && p.trim().isNotEmpty) {
                  final key = 'vik_defect_${i + 1}_${j + 1}';
                  structuredDocumentFiles[key] = {
                    'file_path': p,
                    'file_name': Path.basename(p),
                  };
                }
              }
            }
          }
        }
      }
'@
  $content = $content.Replace($marker, "$marker`r`n$insert")
}

Set-Content -Path $Path -Value $content -Encoding UTF8
Write-Host "Inserted VIK defect photo uploads"
