# tools/backup_release.ps1
# Резервная копия DictaPro перед релизной сборкой.
# Требование Славана: перед сборкой релиза — бэкап рабочей версии,
# никогда не терять последнюю рабочую.
#
# Что копирует:
#   1. Исходники (git-архив HEAD, без build/ и .git) -> <dest>\src
#   2. Git-состояние (ветка, коммит, дата, статус)   -> <dest>\GIT_STATE.txt
#   3. Собранные APK/AAB, если есть                  -> <dest>\artifacts
# Куда: D:\Projects\Backups\dictapro_YYYY-MM-DD_<версия>
# Плюс строка в реестр: D:\Projects\Backups\backups_registry.csv
#
# Запуск из корня проекта:
#   powershell -ExecutionPolicy Bypass -File tools\backup_release.ps1

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$backupRoot  = 'D:\Projects\Backups'

# Версия из pubspec.yaml (строка вида "version: 1.0.0+47")
$pubspec = Join-Path $projectRoot 'pubspec.yaml'
if (-not (Test-Path $pubspec)) { throw "pubspec.yaml не найден: $pubspec" }
$versionLine = Select-String -Path $pubspec -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if ($null -eq $versionLine) { throw 'Не удалось прочитать версию из pubspec.yaml' }
$version = ($versionLine.Matches[0].Groups[1].Value -replace '\+', 'p')

$date = Get-Date -Format 'yyyy-MM-dd'
$dest = Join-Path $backupRoot "dictapro_${date}_${version}"

if (Test-Path $dest) {
    Write-Host "Бэкап уже существует: $dest" -ForegroundColor Yellow
    exit 0
}

New-Item -ItemType Directory -Path $dest -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $dest 'src') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $dest 'artifacts') -Force | Out-Null

# 1. Исходники — то, что в git (tracked). key.properties и прочие
#    незакоммиченные секреты НЕ копируются — они живут только на машине сборки.
Push-Location $projectRoot
try {
    git archive HEAD | tar -x -C (Join-Path $dest 'src')
} finally {
    Pop-Location
}

# 2. Git-состояние
$head = (git -C $projectRoot rev-parse HEAD)
$branch = (git -C $projectRoot rev-parse --abbrev-ref HEAD)
$status = (git -C $projectRoot status --porcelain)
$gitState = @(
    "branch: $branch"
    "head: $head"
    "date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    '--- git status --porcelain (пусто = чистое дерево) ---'
    $status
) -join "`r`n"
$gitState | Out-File (Join-Path $dest 'GIT_STATE.txt') -Encoding utf8

# 3. Собранные артефакты (если есть)
$apkDir = Join-Path $projectRoot 'build\app\outputs\flutter-apk'
$aabDir = Join-Path $projectRoot 'build\app\outputs\bundle\release'
if (Test-Path $apkDir) {
    Copy-Item (Join-Path $apkDir '*.apk') (Join-Path $dest 'artifacts') -ErrorAction SilentlyContinue
}
if (Test-Path $aabDir) {
    Copy-Item (Join-Path $aabDir '*.aab') (Join-Path $dest 'artifacts') -ErrorAction SilentlyContinue
}

# 4. Реестр бэкапов
$registry = Join-Path $backupRoot 'backups_registry.csv'
if (-not (Test-Path $registry)) {
    'date;version;path;head' | Out-File $registry -Encoding utf8
}
"$date;$version;$dest;$head" | Out-File $registry -Append -Encoding utf8

Write-Host "Бэкап готов: $dest" -ForegroundColor Green
