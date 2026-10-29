[CmdletBinding()]
param()
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-TransferPassword([Security.SecureString]$Password, [switch]$Confirm) {
    if ($null -eq $Password) {
        $Password = Read-Host 'Senha do backup' -AsSecureString
        if ($Confirm) {
            $second = Read-Host 'Repita a senha' -AsSecureString
            $a = [Net.NetworkCredential]::new('', $Password).Password
            $b = [Net.NetworkCredential]::new('', $second).Password
            if ($a -cne $b) { throw 'As senhas nao conferem.' }
            $a = $null; $b = $null
        }
    }
    if ($Password.Length -lt 12) { throw 'Use uma senha de pelo menos 12 caracteres.' }
    return $Password
}

# Encrypt-then-MAC: PBKDF2-SHA256, independent AES/HMAC keys, random salt and IV.
# Binary format: magic(8), salt(16), IV(16), ciphertext(n), HMAC-SHA256(32).
function Convert-TransferData([byte[]]$Data, [Security.SecureString]$Password, [switch]$Decrypt) {
    $magic = [Text.Encoding]::ASCII.GetBytes('GPTBKP01')
    $aes = [Security.Cryptography.Aes]::Create()
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $salt = New-Object byte[] 16
    $iv = New-Object byte[] 16
    $kdf = $null; $mac = $null; $transform = $null
    $plainPassword = [Net.NetworkCredential]::new('', $Password).Password
    try {
        if ($Decrypt) {
            if ($Data.Length -lt 88 -or [Text.Encoding]::ASCII.GetString($Data, 0, 8) -cne 'GPTBKP01') { throw 'Formato de backup invalido.' }
            [Array]::Copy($Data, 8, $salt, 0, 16)
            [Array]::Copy($Data, 24, $iv, 0, 16)
        } else { $rng.GetBytes($salt); $rng.GetBytes($iv) }
        $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($plainPassword, $salt, 210000, [Security.Cryptography.HashAlgorithmName]::SHA256)
        $aes.Key = $kdf.GetBytes(32); $aes.IV = $iv
        $mac = [Security.Cryptography.HMACSHA256]::new($kdf.GetBytes(32))
        if ($Decrypt) {
            $tag = $mac.ComputeHash($Data, 0, $Data.Length - 32)
            $difference = 0
            for ($i = 0; $i -lt 32; $i++) { $difference = $difference -bor ($tag[$i] -bxor $Data[$Data.Length - 32 + $i]) }
            if ($difference -ne 0) { throw 'Senha incorreta ou backup alterado. Nada foi restaurado.' }
            $transform = $aes.CreateDecryptor()
            return ,($transform.TransformFinalBlock($Data, 40, $Data.Length - 72))
        }
        $transform = $aes.CreateEncryptor()
        $ciphertext = $transform.TransformFinalBlock($Data, 0, $Data.Length)
        $body = $magic + $salt + $iv + $ciphertext
        return ,([byte[]]($body + $mac.ComputeHash([byte[]]$body)))
    } finally {
        $plainPassword = $null
        if ($transform) { $transform.Dispose() }
        if ($mac) { $mac.Dispose() }
        if ($kdf) { $kdf.Dispose() }
        $aes.Dispose(); $rng.Dispose()
    }
}

function Add-TransferEntry($Zip, [string]$EntryName, [byte[]]$Bytes) {
    $entry = $Zip.CreateEntry($EntryName)
    $stream = $entry.Open()
    try { $stream.Write($Bytes, 0, $Bytes.Length) } finally { $stream.Dispose() }
}
function Read-TransferEntry($Entry) {
    $inputStream = $Entry.Open(); $buffer = [IO.MemoryStream]::new()
    try { $inputStream.CopyTo($buffer); return ,($buffer.ToArray()) }
    finally { $inputStream.Dispose(); $buffer.Dispose() }
}
function Export-Transfer([string]$File, [string]$ReposRoot, [Security.SecureString]$Password) {
    if (Test-Path -LiteralPath $File) { throw 'O backup ja existe. Escolha outro arquivo para preservar o anterior.' }
    $profilesRoot = Get-ProfilesRoot
    if (-not (Test-Path -LiteralPath $profilesRoot)) { throw 'Nenhum perfil salvo. Use gpt-profile add <nome> antes do backup.' }
    $Password = Get-TransferPassword $Password -Confirm
    $package = Get-ChatGPTPackage
    Stop-ChatGPT
    Save-CurrentProfile $package
    $tempManifest = Join-Path ([IO.Path]::GetTempPath()) ('gpt-repos-' + [guid]::NewGuid() + '.json')
    $buffer = [IO.MemoryStream]::new()
    $zip = $null
    try {
        & (Join-Path $PSScriptRoot 'repositories.ps1') backup -Path $tempManifest -Root $ReposRoot
        if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel exportar os repositorios.' }
        $zip = [IO.Compression.ZipArchive]::new($buffer, [IO.Compression.ZipArchiveMode]::Create, $true)
        Add-TransferEntry $zip 'repositories.json' ([IO.File]::ReadAllBytes($tempManifest))
        $active = Get-ActiveProfile
        $profileNames = @(Get-ChildItem -LiteralPath $profilesRoot -Directory | ForEach-Object {
            Assert-ValidName $_.Name
            if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links nao sao permitidos nos perfis.' }
            $_.Name
        })
        if ($profileNames.Count -eq 0) { throw 'Nenhum perfil salvo.' }
        $metadata = @{ version = 1; active = $active; profiles = $profileNames; package = $package.Name } | ConvertTo-Json -Depth 5
        Add-TransferEntry $zip 'transfer.json' ([Text.Encoding]::UTF8.GetBytes($metadata))
        foreach ($profileName in $profileNames) {
            $profilePath = Join-Path $profilesRoot $profileName
            foreach ($item in Get-ChildItem -LiteralPath $profilePath -Recurse -Force) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links nao sao permitidos nos perfis.' }
                if (-not $item.PSIsContainer) {
                    $relative = $item.FullName.Substring($profilesRoot.Length + 1).Replace('\', '/')
                    Add-TransferEntry $zip ('profiles/' + $relative) ([IO.File]::ReadAllBytes($item.FullName))
                }
            }
        }
        $zip.Dispose(); $zip = $null
        $encrypted = Convert-TransferData ($buffer.ToArray()) $Password
        # CreateNew prevents accidental replacement even if another process creates the file.
        $outputStream = [IO.File]::Open($File, [IO.FileMode]::CreateNew)
        try { $outputStream.Write($encrypted, 0, $encrypted.Length) } finally { $outputStream.Dispose() }
        Write-Success "Backup protegido criado: $File ($($profileNames.Count) perfis e lista de repositorios)."
        Write-Host 'Na outra maquina: gpt-profile restore <arquivo.gptbackup>. Use a mesma senha.'
    } finally {
        if ($zip) { $zip.Dispose() }
        $buffer.Dispose()
        if (Test-Path -LiteralPath $tempManifest) { Remove-Item -LiteralPath $tempManifest -Force }
    }
}
function Import-Transfer([string]$File, [string]$ReposRoot, [Security.SecureString]$Password) {
    $Password = Get-TransferPassword $Password
    $bytes = Convert-TransferData ([IO.File]::ReadAllBytes($File)) $Password -Decrypt
    $buffer = [IO.MemoryStream]::new($bytes, $false)
    $zip = [IO.Compression.ZipArchive]::new($buffer, [IO.Compression.ZipArchiveMode]::Read)
    $tempManifest = Join-Path ([IO.Path]::GetTempPath()) ('gpt-repos-' + [guid]::NewGuid() + '.json')
    try {
        $metadata = [Text.Encoding]::UTF8.GetString((Read-TransferEntry ($zip.GetEntry('transfer.json')))) | ConvertFrom-Json
        if ($metadata.version -ne 1) { throw 'Versao de backup nao suportada.' }
        $package = Get-ChatGPTPackage
        if ($metadata.package -ne $package.Name) { throw 'Instale o mesmo aplicativo usado no backup antes de restaurar.' }
        $profilesRoot = Get-ProfilesRoot
        $names = @{}
        foreach ($profileName in $metadata.profiles) {
            Assert-ValidName $profileName
            if ($names.ContainsKey($profileName)) { throw 'Perfil duplicado no backup.' }
            $names[$profileName] = $true
            if (Test-Path -LiteralPath (Join-Path $profilesRoot $profileName)) { throw "O perfil '$profileName' ja existe. Nada foi importado. Use um armazenamento vazio para evitar perda de contas." }
        }
        if ($names.Count -eq 0 -or ($metadata.active -and -not $names.ContainsKey($metadata.active))) { throw 'Lista de perfis invalida.' }
        $seen = @{}
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            if ($seen.ContainsKey($name)) { throw 'Entrada duplicada no backup.' }
            $seen[$name] = $true
            if ($name -in @('repositories.json', 'transfer.json')) { continue }
            $parts = $name.Split('/')
            if ($parts.Count -lt 3 -or $parts[0] -ne 'profiles' -or -not $names.ContainsKey($parts[1])) { throw 'Entrada invalida no backup.' }
            foreach ($part in $parts) {
                if ([string]::IsNullOrWhiteSpace($part) -or $part -in @('.', '..') -or $part -match '[\\:*?"<>|]' -or $part.EndsWith('.') -or $part.EndsWith(' ')) { throw 'Caminho inseguro no backup.' }
            }
        }
        if (-not $seen.ContainsKey('repositories.json')) { throw 'Lista de repositorios ausente.' }
        foreach ($profileName in $metadata.profiles) {
            if ((Uses-ExternalAuth $package) -and -not $seen.ContainsKey("profiles/$profileName/CodexAuth/auth.json")) {
                throw "O perfil '$profileName' nao possui auth.json. Recapture a conta na origem antes do backup."
            }
        }
        # Do not import through junctions or symbolic links in an existing store.
        $ancestor = [IO.Path]::GetFullPath($profilesRoot)
        while ($ancestor) {
            if (Test-Path -LiteralPath $ancestor) {
                if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'O armazenamento de destino usa um link. Escolha uma pasta local.' }
            }
            $ancestor = Split-Path -Parent $ancestor
        }
        Stop-ChatGPT
        foreach ($profileName in $metadata.profiles) { New-Item -ItemType Directory -Path (Join-Path $profilesRoot $profileName) -Force | Out-Null }
        foreach ($entry in $zip.Entries) {
            if (-not $entry.FullName.StartsWith('profiles/')) { continue }
            $destination = Join-Path $profilesRoot ($entry.FullName.Substring(9).Replace('/', '\'))
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            [IO.File]::WriteAllBytes($destination, (Read-TransferEntry $entry))
        }
        [IO.File]::WriteAllBytes($tempManifest, (Read-TransferEntry ($zip.GetEntry('repositories.json'))))
        Write-Success 'Perfis e credenciais importados.'
        if ($metadata.active) { Switch-Profile $package $metadata.active }
        Write-Host 'Sessoes expiradas ou protegidas pelo Windows podem exigir novo login. Use gpt-profile open <nome> para as outras contas.'
        & (Join-Path $PSScriptRoot 'repositories.ps1') restore -Path $tempManifest -Root $ReposRoot
        if ($LASTEXITCODE -ne 0) { throw 'Perfis importados; alguns repositorios nao foram clonados. Consulte os avisos acima.' }
    } finally {
        $zip.Dispose(); $buffer.Dispose()
        if (Test-Path -LiteralPath $tempManifest) { Remove-Item -LiteralPath $tempManifest -Force }
    }
}
