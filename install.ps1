[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$destinationRoot = Join-Path $env:LOCALAPPDATA "Programs\ChatGPTProfiles"
$destinationScript = Join-Path $destinationRoot "chatgpt-profiles.ps1"
$launcher = Join-Path $destinationRoot "gpt-profile.cmd"

New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "chatgpt-profiles.ps1") -Destination $destinationScript -Force

Copy-Item -LiteralPath (Join-Path $PSScriptRoot "repositories.ps1") -Destination $destinationRoot -Force

Copy-Item -LiteralPath (Join-Path $PSScriptRoot "transfer.ps1") -Destination $destinationRoot -Force

Copy-Item -LiteralPath (Join-Path $PSScriptRoot "file-dialog.ps1") -Destination $destinationRoot -Force

$launcherContent = "@echo off`r`npowershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File `"$destinationScript`" %*`r`n"
[IO.File]::WriteAllText($launcher, $launcherContent, [Text.Encoding]::ASCII)

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$entries = @($userPath -split ";" | Where-Object { $_ })
if ($destinationRoot -notin $entries) {
    $newPath = (($entries + $destinationRoot) -join ";")
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
}

Write-Host "Instalado em $destinationRoot" -ForegroundColor Green
Write-Host "Abra um novo terminal e execute: gpt-profile help"
