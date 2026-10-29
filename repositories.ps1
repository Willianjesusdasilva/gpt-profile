[CmdletBinding()]
param(
    [ValidateSet('backup', 'restore')][string]$Command,
    [string]$Path,
    [string]$Root = 'C:\git',
    [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Invoke-Git([string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $result = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Git falhou: $result" }
    return @($result | ForEach-Object { $_.ToString() })
}
function Assert-Remote([string]$Remote) {
    if ([string]::IsNullOrWhiteSpace($Remote) -or $Remote.StartsWith('-')) { throw 'Remote invalido.' }
    if ($Remote -match '^https?://[^/]*@' -or $Remote -match '[?#]') {
        throw 'Remote com credencial ou parametros: use uma URL sem token antes de exportar.'
    }
}
try {
    Get-Command git -ErrorAction Stop | Out-Null
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($Command -eq 'restore') { throw 'Informe o arquivo: gpt-profile restore backup.json -Root D:\git' }
        $Path = Join-Path (Get-Location) 'gpt-profile-repos.json'
    }
    $file = [IO.Path]::GetFullPath($Path)
    if ($Command -eq 'backup') {
        if (-not (Test-Path -LiteralPath $base -PathType Container)) { throw "Pasta inexistente: $base" }
        if ((Test-Path -LiteralPath $file) -and -not $Force) { throw 'Arquivo ja existe. Use -Force para substituir.' }
        $repos = [Collections.Generic.List[object]]::new()
        $pending = [Collections.Generic.Stack[string]]::new()
        $pending.Push($base)
        while ($pending.Count -gt 0) {
            $folder = $pending.Pop()
            if (Test-Path -LiteralPath (Join-Path $folder '.git')) {
                $remote = [string](Invoke-Git @('-C', $folder, 'remote', 'get-url', 'origin'))
                Assert-Remote $remote
                $branch = [string](Invoke-Git @('-C', $folder, 'symbolic-ref', '--quiet', '--short', 'HEAD'))
                $relative = if ($folder -eq $base) { '.' } else { $folder.Substring($base.Length + 1) }
                $dirty = @(Invoke-Git @('-C', $folder, 'status', '--porcelain'))
                if ($dirty.Count) { Write-Warning "Alteracoes locais nao incluidas: $relative" }
                $repos.Add([ordered]@{ path = $relative; remote = $remote; branch = $branch })
                continue
            }
            foreach ($dir in Get-ChildItem -LiteralPath $folder -Directory -Force) {
                if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($dir.Name -in @('node_modules', '.git', '.venv', 'venv')) { continue }
                $pending.Push($dir.FullName)
            }
        }
        [ordered]@{ version = 1; repositories = @($repos.ToArray()) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file -Encoding UTF8
        Write-Host "Backup criado: $file ($($repos.Count) repositorios). Contem URLs e branches; nao contem arquivos nem sessoes."
    } else {
        $manifest = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        if ($manifest.version -ne 1) { throw 'Versao de backup nao suportada.' }
        # Validate the entire manifest before cloning anything.
        $targets = @{}
        foreach ($repo in $manifest.repositories) {
            Assert-Remote $repo.remote
            if ([IO.Path]::IsPathRooted($repo.path) -or $repo.path -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Caminho inseguro no backup.' }
            $target = [IO.Path]::GetFullPath((Join-Path $base $repo.path))
            if ($target -ne $base -and -not $target.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Caminho fora da pasta de destino.' }
            if ($targets.ContainsKey($target)) { throw 'Destino duplicado no backup.' }
            $targets[$target] = $true
        }
        $failures = 0
        foreach ($repo in $manifest.repositories) {
            $target = [IO.Path]::GetFullPath((Join-Path $base $repo.path))
            try {
                if (Test-Path -LiteralPath $target) { throw "Destino ja existe, preservado: $target" }
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
                Invoke-Git @('clone', '--branch', $repo.branch, '--', $repo.remote, $target) | Out-Host
            } catch { $failures++; Write-Warning $_.Exception.Message }
        }
        if ($failures) { throw "$failures repositorio(s) nao restaurado(s). Os demais foram processados." }
        Write-Host 'Restauracao concluida.'
    }
    exit 0
} catch { Write-Host "Erro: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }


