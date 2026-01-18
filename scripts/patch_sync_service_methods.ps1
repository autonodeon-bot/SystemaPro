param(
  [string]$Path = "mobile\lib\services\sync_service.dart"
)

$ErrorActionPreference = "Stop"

$content = Get-Content -Path $Path -Raw -Encoding UTF8

if ($content -notmatch "saveEngineersOffline\(") {
  $methods = @'

  /// Сохранить список инженеров для офлайн-режима
  Future<void> saveEngineersOffline(List<Map<String, dynamic>> engineers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = engineers.map((e) => json.encode(e)).toList();
      await prefs.setStringList(_prefsKeyOfflineEngineers, items);
    } catch (e) {
      throw Exception('Ошибка сохранения инженеров локально: $e');
    }
  }

  /// Получить список инженеров из локального хранилища
  Future<List<Map<String, dynamic>>> getOfflineEngineers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = prefs.getStringList(_prefsKeyOfflineEngineers) ?? [];
      return items.map((e) {
        final m = json.decode(e);
        return Map<String, dynamic>.from(m as Map);
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Сохранить список оборудования поверок для офлайн-режима
  Future<void> saveVerificationEquipmentOffline(List<Map<String, dynamic>> equipment) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = equipment.map((e) => json.encode(e)).toList();
      await prefs.setStringList(_prefsKeyOfflineVerificationEquipment, items);
    } catch (e) {
      throw Exception('Ошибка сохранения поверочного оборудования локально: $e');
    }
  }

  /// Получить список оборудования поверок из локального хранилища
  Future<List<Map<String, dynamic>>> getOfflineVerificationEquipment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = prefs.getStringList(_prefsKeyOfflineVerificationEquipment) ?? [];
      return items.map((e) {
        final m = json.decode(e);
        return Map<String, dynamic>.from(m as Map);
      }).toList();
    } catch (e) {
      return [];
    }
  }
'@

  $content = [regex]::Replace(
    $content,
    "(?s)(Future<List<Assignment>> getOfflineAssignments\\(\\) async \\{.*?\\n\\s*\\}\\n)",
    "`$1$methods",
    1
  )
}

Set-Content -Path $Path -Value $content -Encoding UTF8
Write-Host "SyncService methods patched"
