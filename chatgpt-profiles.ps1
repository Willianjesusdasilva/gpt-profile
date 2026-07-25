[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("status", "list", "add", "switch", "remove", "open", "shared", "help")]
    [string]$Command = "status",

    [Parameter(Position = 1)]
    [string]$Name,

    [switch]$NoLaunch,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ManagedDirectories = @(
    "AC",
    "AppData",
    "LocalCache",
    "LocalState",
    "RoamingState",
    "Settings",
    "SystemAppData"
)

function Write-Info([string]$Message) {
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success([string]$Message) {
    Write-Host $Message -ForegroundColor Green
}

function Get-StoreRoot {
    if ($env:CHATGPT_PROFILES_HOME) {
        return [IO.Path]::GetFullPath($env:CHATGPT_PROFILES_HOME)
    }
    $current = Join-Path $env:USERPROFILE "gpt-profile"
    $legacy = Join-Path $env:USERPROFILE "gtp-profile"
    if (-not (Test-Path -LiteralPath $current) -and (Test-Path -LiteralPath $legacy)) {
        return $legacy
    }
    return $current
}

function Get-ProfilesRoot {
    return Join-Path (Get-StoreRoot) "profiles"
}

function Get-ActiveFile {
    return Join-Path (Get-StoreRoot) "active.json"
}

function Get-SharedRoot {
    return Join-Path (Get-StoreRoot) "shared"
}
function Get-ExternalAuthFile {
    if ($env:CHATGPT_PROFILES_AUTH_FILE) {
        return [IO.Path]::GetFullPath($env:CHATGPT_PROFILES_AUTH_FILE)
    }
    return Join-Path $env:USERPROFILE ".codex\auth.json"
}

function Uses-ExternalAuth($Package) {
    return ($Package.Name -eq "OpenAI.Codex" -or -not [string]::IsNullOrWhiteSpace($env:CHATGPT_PROFILES_AUTH_FILE))
}

function Get-ProfileAuthFile([string]$ProfilePath) {
    return Join-Path $ProfilePath "CodexAuth\auth.json"
}

function Get-ChatGPTPackage {
    if ($env:CHATGPT_PROFILES_PACKAGE_ROOT) {
        return [pscustomobject]@{
            Name              = if ($env:CHATGPT_PROFILES_PACKAGE_NAME) { $env:CHATGPT_PROFILES_PACKAGE_NAME } else { "OpenAI.ChatGPT-Test" }
            PackageFamilyName = if ($env:CHATGPT_PROFILES_PACKAGE_FAMILY) { $env:CHATGPT_PROFILES_PACKAGE_FAMILY } else { "OpenAI.ChatGPT-Test_test" }
            InstallLocation   = $null
            DataRoot          = [IO.Path]::GetFullPath($env:CHATGPT_PROFILES_PACKAGE_ROOT)
            AppId             = if ($env:CHATGPT_PROFILES_APP_ID) { $env:CHATGPT_PROFILES_APP_ID } else { "App" }
        }
    }

    $packages = @(Get-AppxPackage | Where-Object {
        $_.Name -in @("OpenAI.ChatGPT-Desktop", "OpenAI.ChatGPT", "OpenAI.Codex") -or
        $_.PackageFamilyName -like "OpenAI.ChatGPT*"
    } | Sort-Object -Property @{ Expression = {
        if ($_.Name -eq "OpenAI.ChatGPT-Desktop") { 0 }
        elseif ($_.Name -eq "OpenAI.ChatGPT") { 1 }
        else { 2 }
    }})

    if ($packages.Count -eq 0) {
        throw "O app ChatGPT da Microsoft Store nao foi encontrado para este usuario."
    }

    $package = $packages[0]
    $manifestPath = Join-Path $package.InstallLocation "AppxManifest.xml"
    [xml]$manifest = Get-Content -LiteralPath $manifestPath
    $appId = @($manifest.Package.Applications.Application)[0].Id

    return [pscustomobject]@{
        Name              = $package.Name
        PackageFamilyName = $package.PackageFamilyName
        InstallLocation   = $package.InstallLocation
        DataRoot          = Join-Path $env:LOCALAPPDATA ("Packages\" + $package.PackageFamilyName)
        AppId             = $appId
    }
}

function Assert-ValidName([string]$ProfileName) {
    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        throw "Informe o nome do perfil."
    }
    if ($ProfileName -notmatch "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,49}$") {
        throw "Nome invalido. Use 1-50 letras, numeros, ponto, hifen ou sublinhado."
    }
}

function Get-ProfilePath([string]$ProfileName) {
    Assert-ValidName $ProfileName
    return Join-Path (Get-ProfilesRoot) $ProfileName
}

function Get-ActiveProfile {
    $path = Get-ActiveFile
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    try {
        return (Get-Content -Raw -LiteralPath $path | ConvertFrom-Json).name
    } catch {
        throw "O arquivo de estado '$path' esta corrompido."
    }
}

function Set-ActiveProfile([string]$ProfileName, $Package) {
    $data = [ordered]@{
        name = $ProfileName
        packageFamilyName = $Package.PackageFamilyName
        switchedAt = (Get-Date).ToUniversalTime().ToString("o")
    }
    New-Item -ItemType Directory -Force -Path (Get-StoreRoot) | Out-Null
    $temporary = (Get-ActiveFile) + ".tmp"
    $data | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -Force -LiteralPath $temporary -Destination (Get-ActiveFile)
}

function Stop-ChatGPT {
    if ($env:CHATGPT_PROFILES_PACKAGE_ROOT) { return }
    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -in @("ChatGPT", "OpenAI.ChatGPT", "Codex")
    })
    if ($processes.Count -eq 0) {
        return
    }

    Write-Info "Encerrando o ChatGPT para salvar os dados com consistencia..."
    $processes | Stop-Process
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $remaining = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -in @("ChatGPT", "OpenAI.ChatGPT", "Codex")
        })
    } while ($remaining.Count -gt 0 -and (Get-Date) -lt $deadline)

    if ($remaining.Count -gt 0) {
        if (-not $Force) {
            throw "O ChatGPT ainda esta em execucao. Feche-o ou repita com -Force."
        }
        $remaining | Stop-Process -Force
    }
}

function Copy-AppData([string]$SourceRoot, [string]$DestinationRoot) {
    $parent = Split-Path -Parent $DestinationRoot
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $staging = "$DestinationRoot.staging-$PID"
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $staging | Out-Null

    try {
        foreach ($directory in $script:ManagedDirectories) {
            $source = Join-Path $SourceRoot $directory
            if (Test-Path -LiteralPath $source) {
                Copy-Item -LiteralPath $source -Destination $staging -Recurse -Force
            }
        }
        if (Test-Path -LiteralPath $DestinationRoot) {
            Remove-Item -LiteralPath $DestinationRoot -Recurse -Force
        }
        Move-Item -LiteralPath $staging -Destination $DestinationRoot
    } catch {
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force
        }
        throw
    }
}

function Restore-AppData([string]$ProfilePath, [string]$DataRoot) {
    foreach ($directory in $script:ManagedDirectories) {
        $destination = Join-Path $DataRoot $directory
        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Recurse -Force
        }
        $source = Join-Path $ProfilePath $directory
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $DataRoot -Recurse -Force
        } else {
            New-Item -ItemType Directory -Force -Path $destination | Out-Null
        }
    }
}

function Save-ExternalAuth($Package, [string]$ProfilePath) {
    if (-not (Uses-ExternalAuth $Package)) { return }
    $source = Get-ExternalAuthFile
    if (-not (Test-Path -LiteralPath $source)) {
        throw "A credencial externa do Codex nao foi encontrada: $source"
    }
    $destination = Get-ProfileAuthFile $ProfilePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Restore-ExternalAuth($Package, [string]$ProfilePath) {
    if (-not (Uses-ExternalAuth $Package)) { return }
    $source = Get-ProfileAuthFile $ProfilePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "O perfil nao possui a credencial Codex. Entre nessa conta e recapture com: gpt-profile add <nome> -Force"
    }
    $destination = Get-ExternalAuthFile
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    $temporary = "$destination.gpt-profile-$PID.tmp"
    Copy-Item -LiteralPath $source -Destination $temporary -Force
    Move-Item -LiteralPath $temporary -Destination $destination -Force
}
function Save-CurrentProfile($Package) {
    $active = Get-ActiveProfile
    if (-not $active) {
        return
    }
    $destination = Get-ProfilePath $active
    Write-Info "Salvando alteracoes do perfil '$active'..."
    Copy-AppData $Package.DataRoot $destination
    Save-ExternalAuth $Package $destination
}

function Add-Profile($Package, [string]$ProfileName) {
    Assert-ValidName $ProfileName
    Stop-ChatGPT
    $destination = Get-ProfilePath $ProfileName
    if ((Test-Path -LiteralPath $destination) -and -not $Force) {
        throw "O perfil '$ProfileName' ja existe. Use -Force para sobrescreve-lo."
    }
    Copy-AppData $Package.DataRoot $destination
    Save-ExternalAuth $Package $destination
    Set-ActiveProfile $ProfileName $Package
    Write-Success "Perfil '$ProfileName' salvo e marcado como ativo."
}

function Switch-Profile($Package, [string]$ProfileName) {
    $source = Get-ProfilePath $ProfileName
    if (-not (Test-Path -LiteralPath $source)) {
        throw "O perfil '$ProfileName' nao existe."
    }
    if ((Uses-ExternalAuth $Package) -and -not (Test-Path -LiteralPath (Get-ProfileAuthFile $source))) {
        throw "O perfil '$ProfileName' foi criado por uma versao antiga e nao possui auth.json. Entre nessa conta e execute: gpt-profile add $ProfileName -Force"
    }

    Stop-ChatGPT
    $active = Get-ActiveProfile
    if ($active -and $active -ne $ProfileName) {
        Save-CurrentProfile $Package
    } elseif (-not $active) {
        $backupName = "_backup-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        Write-Info "Criando backup inicial '$backupName'..."
        $backupPath = Get-ProfilePath $backupName
        Copy-AppData $Package.DataRoot $backupPath
        Save-ExternalAuth $Package $backupPath
    }

    Write-Info "Ativando o perfil '$ProfileName'..."
    Restore-AppData $source $Package.DataRoot
    Restore-ExternalAuth $Package $source
    Set-ActiveProfile $ProfileName $Package

    if (-not $NoLaunch) {
        Start-ChatGPT $Package
    }
    Write-Success "Perfil ativo: $ProfileName"
}

function Remove-Profile([string]$ProfileName) {
    $path = Get-ProfilePath $ProfileName
    if (-not (Test-Path -LiteralPath $path)) {
        throw "O perfil '$ProfileName' nao existe."
    }
    if ((Get-ActiveProfile) -eq $ProfileName) {
        throw "Nao e possivel remover o perfil ativo. Troque de perfil primeiro."
    }
    if (-not $Force) {
        throw "A remocao e destrutiva. Repita com -Force para confirmar."
    }
    Remove-Item -LiteralPath $path -Recurse -Force
    Write-Success "Perfil '$ProfileName' removido."
}

function Start-ChatGPT($Package) {
    if ($env:CHATGPT_PROFILES_PACKAGE_ROOT) {
        Write-Info "Modo de teste: inicializacao ignorada."
        return
    }
    $application = "shell:AppsFolder\$($Package.PackageFamilyName)!$($Package.AppId)"
    Start-Process explorer.exe -ArgumentList $application
}

function Open-SharedWorkspace {
    $sharedRoot = Get-SharedRoot
    New-Item -ItemType Directory -Force -Path $sharedRoot | Out-Null

    $readme = Join-Path $sharedRoot "LEIA-ME.txt"
    if (-not (Test-Path -LiteralPath $readme)) {
        @"
WORKSPACE COMPARTILHADO

Os arquivos desta pasta sao comuns a todos os perfis gerenciados.
Use esta pasta ao anexar documentos em chats de qualquer conta.

Importante:
- anexar um arquivo cria uma copia na conta/projeto selecionado;
- chats e memoria pessoal continuam vinculados a cada conta;
- para colaborar na nuvem, convide ambas as contas para um Projeto compartilhado.
"@ | Set-Content -LiteralPath $readme -Encoding UTF8
    }

    Write-Success "Workspace compartilhado: $sharedRoot"
    if (-not $NoLaunch -and -not $env:CHATGPT_PROFILES_PACKAGE_ROOT) {
        Start-Process explorer.exe -ArgumentList "`"$sharedRoot`""
    }
}

function Show-Status($Package) {
    $active = Get-ActiveProfile
    $profiles = @()
    if (Test-Path -LiteralPath (Get-ProfilesRoot)) {
        $profiles = @(Get-ChildItem -LiteralPath (Get-ProfilesRoot) -Directory | Sort-Object Name)
    }

    Write-Host ""
    Write-Host "ChatGPT Profiles" -ForegroundColor White
    Write-Host "App:     $($Package.Name)"
    Write-Host "Dados:   $($Package.DataRoot)"
    Write-Host "Ativo:   $(if ($active) { $active } else { '(ainda nao gerenciado)' })"
    Write-Host "Comum:   $(Get-SharedRoot)"
    Write-Host ""

    if ($profiles.Count -eq 0) {
        Write-Host "Nenhum perfil salvo. Use: .\chatgpt-profiles.ps1 add pessoal"
        return
    }
    foreach ($profile in $profiles) {
        $marker = if ($profile.Name -eq $active) { "*" } else { " " }
        Write-Host "$marker $($profile.Name)"
    }
}

function Get-FriendlySize([long]$Bytes) {
    if ($Bytes -ge 1GB) { return ("{0:N1} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N1} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N1} KB" -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Show-Profiles {
    $active = Get-ActiveProfile
    $profiles = @()
    if (Test-Path -LiteralPath (Get-ProfilesRoot)) {
        $profiles = @(Get-ChildItem -LiteralPath (Get-ProfilesRoot) -Directory | Sort-Object Name)
    }

    if ($profiles.Count -eq 0) {
        Write-Host "Nenhum perfil salvo. Use: gpt-profile add pessoal"
        return
    }

    $rows = foreach ($profile in $profiles) {
        $files = @(Get-ChildItem -LiteralPath $profile.FullName -File -Recurse -ErrorAction SilentlyContinue)
        $bytes = ($files | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $bytes) { $bytes = 0 }
        [pscustomobject]@{
            Perfil       = $profile.Name
            Ativo        = if ($profile.Name -eq $active) { "sim" } else { "" }
            Atualizado   = $profile.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            DadosLocais  = Get-FriendlySize $bytes
            UsoDaConta   = "ver no app"
        }
    }
    $rows | Format-Table -AutoSize
    Write-Host "Uso da conta: o ChatGPT nao expoe quotas por uma API publica." -ForegroundColor DarkGray
}

function Show-Help {
    @"
ChatGPT Profiles - perfis locais para o app ChatGPT no Windows

Uso:
  gpt-profile add <nome>              Salva a sessao aberta
  gpt-profile open <nome>             Ativa o perfil e abre o ChatGPT
  gpt-profile switch <nome>           Mesmo comportamento de open <nome>
  gpt-profile list                    Lista os perfis e o estado
  gpt-profile shared                  Abre o workspace comum
  gpt-profile open                    Abre o perfil atualmente ativo
  gpt-profile remove <nome> -Force    Remove um perfil
  gpt-profile status                  Mostra o diagnostico

O app e encerrado durante add/switch para evitar corrupcao. Os perfis ficam em:
  $(Get-StoreRoot)
"@ | Write-Host
}

try {
    if ($Command -eq "help") {
        Show-Help
        exit 0
    }

    $package = Get-ChatGPTPackage
    if (-not (Test-Path -LiteralPath $package.DataRoot)) {
        throw "A pasta de dados do app nao existe: $($package.DataRoot)"
    }

    switch ($Command) {
        "status" { Show-Status $package }
        "list"   { Show-Profiles }
        "add"    { Add-Profile $package $Name }
        "switch" { Switch-Profile $package $Name }
        "remove" { Remove-Profile $Name }
        "shared" { Open-SharedWorkspace }
        "open"   {
            if ([string]::IsNullOrWhiteSpace($Name)) {
                Start-ChatGPT $package
            } else {
                Switch-Profile $package $Name
            }
        }
    }
} catch {
    Write-Host "Erro: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
