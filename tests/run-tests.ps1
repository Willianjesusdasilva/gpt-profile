$ErrorActionPreference = "Stop"

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("chatgpt-profiles-test-" + [guid]::NewGuid())
$packageRoot = Join-Path $temporaryRoot "package"
$storeRoot = Join-Path $temporaryRoot "store"
$authFile = Join-Path $temporaryRoot "auth.json"

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "LocalCache") | Out-Null
    Set-Content -LiteralPath (Join-Path $packageRoot "LocalCache\session.txt") -Value "account-a"
    Set-Content -LiteralPath $authFile -Value '{"account":"a"}'

    $env:CHATGPT_PROFILES_PACKAGE_ROOT = $packageRoot
    $env:CHATGPT_PROFILES_HOME = $storeRoot
    $env:CHATGPT_PROFILES_AUTH_FILE = $authFile
    $scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "chatgpt-profiles.ps1"

    & $scriptPath add personal -NoLaunch

    Set-Content -LiteralPath (Join-Path $packageRoot "LocalCache\session.txt") -Value "account-b"
    Set-Content -LiteralPath $authFile -Value '{"account":"b"}'
    & $scriptPath add work -NoLaunch

    & $scriptPath switch personal -NoLaunch
    $value = (Get-Content -Raw -LiteralPath (Join-Path $packageRoot "LocalCache\session.txt")).Trim()
    if ($value -ne "account-a") { throw "Esperado account-a; recebido $value" }
    if ((Get-Content -Raw -LiteralPath $authFile) -notmatch '"a"') { throw "Auth A nao foi restaurado" }

    Set-Content -LiteralPath (Join-Path $packageRoot "LocalCache\new.txt") -Value "saved-on-switch"
    & $scriptPath switch work -NoLaunch
    if (-not (Test-Path -LiteralPath (Join-Path $storeRoot "profiles\personal\LocalCache\new.txt"))) {
        throw "Alteracoes do perfil ativo nao foram salvas"
    }
    $value = (Get-Content -Raw -LiteralPath (Join-Path $packageRoot "LocalCache\session.txt")).Trim()
    if ($value -ne "account-b") { throw "Esperado account-b; recebido $value" }
    if ((Get-Content -Raw -LiteralPath $authFile) -notmatch '"b"') { throw "Auth B nao foi restaurado" }

    & $scriptPath open personal -NoLaunch
    $value = (Get-Content -Raw -LiteralPath (Join-Path $packageRoot "LocalCache\session.txt")).Trim()
    if ($value -ne "account-a") { throw "open nao ativou personal" }

    & $scriptPath list -NoLaunch

    & $scriptPath shared -NoLaunch
    if (-not (Test-Path -LiteralPath (Join-Path $storeRoot "shared\LEIA-ME.txt"))) {
        throw "Workspace compartilhado nao foi criado"
    }

    Write-Host "Todos os testes passaram." -ForegroundColor Green
} finally {
    Remove-Item Env:CHATGPT_PROFILES_PACKAGE_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:CHATGPT_PROFILES_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:CHATGPT_PROFILES_AUTH_FILE -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
