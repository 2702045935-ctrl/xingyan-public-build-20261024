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
    $item = Get-Item -LiteralPath $file
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($item.Length -ne [int64]$entry.size -or $hash -ne $entry.sha256) {
        $failed += "$($entry.path): changed"
    }
}

if ($failed.Count -gt 0) {
    Write-Host "Core verification failed:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host "Core verification passed."
