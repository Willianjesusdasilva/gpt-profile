[CmdletBinding()]
param(
    [switch]$RemoveProfiles
)

$ErrorActionPreference = "Stop"
$installRoot = Join-Path $env:LOCALAPPDATA "Programs\ChatGPTProfiles"

if (Test-Path -LiteralPath $installRoot) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$entries = @($userPath -split ";" | Where-Object {
    $_ -and $_.TrimEnd("\") -ne $installRoot.TrimEnd("\")
})
[Environment]::SetEnvironmentVariable("Path", ($entries -join ";"), "User")

if ($RemoveProfiles) {
    $current = Join-Path $env:USERPROFILE "gpt-profile"
    $legacy = Join-Path $env:USERPROFILE "gtp-profile"
    foreach ($profileRoot in @($current, $legacy)) {
        if (Test-Path -LiteralPath $profileRoot) {
            Remove-Item -LiteralPath $profileRoot -Recurse -Force
        }
    }
    Write-Host "Aplicativo, perfis e workspace removidos." -ForegroundColor Yellow
} else {
    Write-Host "Aplicativo removido. Perfis e workspace foram preservados." -ForegroundColor Green
}

Write-Host "Abra um novo terminal para atualizar o PATH."
