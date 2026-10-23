param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$manifestPath = Join-Path $Root "core.lock.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$failed = @()

foreach ($entry in $manifest.files) {
    $file = Join-Path $Root $entry.path
    if (-not (Test-Path -LiteralPath $file)) {
        $failed += "$($entry.path): missing"
        continue
    }
    $text = [IO.File]::ReadAllText($file).Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $digest = [Security.Cryptography.SHA256]::HashData($bytes)
    $hash = [BitConverter]::ToString($digest).Replace("-", "").ToLowerInvariant()
    if ($bytes.Length -ne [int64]$entry.size -or $hash -ne $entry.sha256) {
        $failed += "$($entry.path): changed"
    }
}

if ($failed.Count -gt 0) {
    Write-Host "Core verification failed:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" }
    exit 1
}

$protectedPath = Join-Path $Root "protected.lock.json"
$protected = Get-Content -LiteralPath $protectedPath -Raw | ConvertFrom-Json
$protectedFailed = @()

foreach ($entry in $protected.files) {
    $file = Join-Path $Root $entry.path
    if (-not (Test-Path -LiteralPath $file)) {
        $protectedFailed += "$($entry.path): missing"
        continue
    }
    $text = [IO.File]::ReadAllText($file).Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $digest = [Security.Cryptography.SHA256]::HashData($bytes)
    $hash = [BitConverter]::ToString($digest).Replace("-", "").ToLowerInvariant()
    if ($bytes.Length -ne [int64]$entry.size -or $hash -ne $entry.sha256) {
        $protectedFailed += "$($entry.path): protected chat baseline changed"
    }
}

if ($protectedFailed.Count -gt 0) {
    Write-Host "Protected chat verification failed:" -ForegroundColor Red
    $protectedFailed | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host "Core verification passed."
