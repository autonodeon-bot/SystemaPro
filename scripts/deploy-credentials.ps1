# Загрузка учётных данных деплоя (не коммитить пароли в git).
# Скопируйте deploy-credentials.local.ps1.example → deploy-credentials.local.ps1

$ErrorActionPreference = "Stop"
$ScriptsDir = $PSScriptRoot
if (-not $ScriptsDir) { $ScriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

$localFile = Join-Path $ScriptsDir "deploy-credentials.local.ps1"
if (Test-Path $localFile) {
    . $localFile
}

if ($env:DEPLOY_SSH_PASSWORD) { $script:DEPLOY_SSH_PASSWORD = $env:DEPLOY_SSH_PASSWORD }
if ($env:DEPLOY_SERVER) { $script:DEPLOY_SERVER = $env:DEPLOY_SERVER }
if ($env:DEPLOY_SSH_HOSTKEY) { $script:DEPLOY_SSH_HOSTKEY = $env:DEPLOY_SSH_HOSTKEY }
if ($env:DEPLOY_REMOTE_PATH) { $script:DEPLOY_REMOTE_PATH = $env:DEPLOY_REMOTE_PATH }

if (-not $DEPLOY_SERVER) { $DEPLOY_SERVER = "root@5.129.203.182" }
if (-not $DEPLOY_REMOTE_PATH) { $DEPLOY_REMOTE_PATH = "/opt/es-td-ngo" }
if (-not $DEPLOY_SSH_HOSTKEY) {
    $DEPLOY_SSH_HOSTKEY = "SHA256:0le6080AaJ2eq4TG//RZ7kRC5J7PyfsloqaGt2N7VQM"
}

if (-not $DEPLOY_SSH_PASSWORD) {
    throw @"
DEPLOY_SSH_PASSWORD не задан.
Создайте файл: scripts/deploy-credentials.local.ps1
(см. scripts/deploy-credentials.local.ps1.example)
или задайте переменную окружения DEPLOY_SSH_PASSWORD.
"@
}
