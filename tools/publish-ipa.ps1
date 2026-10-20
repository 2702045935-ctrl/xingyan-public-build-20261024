param(
    [string]$RunId = "",
    [string]$Password = "Luchat@2026",
    [string]$OutDir = "C:\Users\Administrator\Documents\Codex\2026-09-24\jie\work\ipa-publish"
)

$ErrorActionPreference = "Stop"
$Repo = "2702045935-ctrl/chris-chat-native"
$OpenSsl = "C:\Program Files\Git\usr\bin\openssl.exe"
$Scp = "C:\Program Files\Git\usr\bin\scp.exe"
$Ssh = "C:\Program Files\Git\usr\bin\ssh.exe"
$Key = "C:\Users\Administrator\.ssh\chris_cloud"
$HostAddr = "root@206.187.208.79"
$PublicDir = "/opt/chris/app/public"
$Stamp = [int][double]::Parse((Get-Date -UFormat %s))   # computed locally, avoids shell quirks

if (-not $RunId) {
    $RunId = (gh run list --repo $Repo --workflow build-ios --status success --limit 1 `
              --json databaseId --jq '.[0].databaseId')
}
if (-not $RunId) { throw "No successful build found (billing blocked, or the build is still running)." }
$RunNumber = (gh run view $RunId --repo $Repo --json number --jq '.number')
Write-Host "run=$RunId  build=B$RunNumber"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = Join-Path $OutDir ("run-" + $RunId + "-" + [int][double]::Parse((Get-Date -UFormat %s)))
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
gh run download $RunId --repo $Repo --dir $OutDir
if ($LASTEXITCODE -ne 0) { throw "下载 CI 产物失败（gh 退出码 $LASTEXITCODE）" }

$enc = Get-ChildItem $OutDir -Recurse -Filter "*.enc" | Select-Object -First 1
if (-not $enc) { throw "Artifact has no .enc file - did this build fail?" }
Write-Host ("encrypted artifact: " + $enc.FullName + "  " + $enc.Length + " bytes")

$ipa = Join-Path $OutDir "Luchat.ipa"
& $OpenSsl enc -d -aes-256-cbc -pbkdf2 -in $enc.FullName -out $ipa -pass "pass:$Password"
if (-not (Test-Path $ipa)) { throw "Decrypt failed (wrong password?)" }
$size = (Get-Item $ipa).Length
$sha = (Get-FileHash $ipa -Algorithm SHA256).Hash
Write-Host "decrypted: $size bytes  SHA256=$sha"

$head = [System.IO.File]::ReadAllBytes($ipa)[0..3]
$zipOk = ($head[0] -eq 0x50 -and $head[1] -eq 0x4B -and $head[2] -eq 0x03 -and $head[3] -eq 0x04)
Write-Host ("zip magic check: " + $(if ($zipOk) { "OK" } else { "FAILED - artifact is corrupt" }))
if (-not $zipOk) { throw "Not a valid IPA; aborting." }

Write-Host "Uploading to the server (keeping a timestamped backup) ..."
& $Ssh -i $Key -o StrictHostKeyChecking=no $HostAddr `
    "cp -p $PublicDir/Luchat.ipa $PublicDir/Luchat.ipa.bak-$Stamp 2>/dev/null || true"
& $Scp -i $Key -o StrictHostKeyChecking=no $ipa "${HostAddr}:$PublicDir/Luchat.ipa"

Write-Host "Verifying the live file ..."
& $Ssh -i $Key -o StrictHostKeyChecking=no $HostAddr `
    "ls -la $PublicDir/Luchat.ipa; sha256sum $PublicDir/Luchat.ipa"

Write-Host ""
Write-Host "Published -> https://aa.x8iu.com/Luchat.ipa"
Write-Host ("  build B$RunNumber (About page shows B$RunNumber) - $size bytes - SHA256 $sha")
