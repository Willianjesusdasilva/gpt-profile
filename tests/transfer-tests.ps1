$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('gpt-transfer-test-' + [guid]::NewGuid())
$cli = Join-Path (Split-Path -Parent $PSScriptRoot) 'chatgpt-profiles.ps1'
$password = ConvertTo-SecureString 'test-password-only-123' -AsPlainText -Force
function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
New-Item -ItemType Directory -Force -Path "$root\source", "$root\app\LocalCache" | Out-Null
git init --initial-branch=main "$root\source\demo" | Out-Null
git -C "$root\source\demo" -c user.name=Test -c user.email=test@example.com commit --allow-empty -m fixture | Out-Null
git clone --bare "$root\source\demo" "$root\remote.git"
git -C "$root\source\demo" remote add origin "$root\remote.git"
$env:CHATGPT_PROFILES_HOME = "$root\old-store"
$env:CHATGPT_PROFILES_PACKAGE_ROOT = "$root\app"
$env:CHATGPT_PROFILES_PACKAGE_NAME = 'OpenAI.Codex'
$env:CHATGPT_PROFILES_AUTH_FILE = "$root\auth.json"
Set-Content -LiteralPath "$root\app\LocalCache\session.txt" -Value 'fake-session-one'
Set-Content -LiteralPath "$root\auth.json" -Value '{"token":"fake-credential-one"}'
& $cli add one -NoLaunch
Set-Content -LiteralPath "$root\app\LocalCache\session.txt" -Value 'fake-session-two'
Set-Content -LiteralPath "$root\auth.json" -Value '{"token":"fake-credential-two"}'
& $cli add two -NoLaunch
& $cli backup "$root\accounts.gptbackup" -IncludeProfiles -Root "$root\source" -Password $password -NoLaunch
Assert-True ($LASTEXITCODE -eq 0) 'Backup failed'
$raw = [IO.File]::ReadAllBytes("$root\accounts.gptbackup")
Assert-True ([Text.Encoding]::UTF8.GetString($raw) -notmatch 'fake-credential') 'Credential visible in backup'
$env:CHATGPT_PROFILES_HOME = "$root\new-store"
$wrong = ConvertTo-SecureString 'incorrect-password-123' -AsPlainText -Force
& $cli restore "$root\accounts.gptbackup" -Password $wrong -NoLaunch -Root "$root\destination"
Assert-True ($LASTEXITCODE -eq 1) 'Wrong password accepted'
Assert-True (-not (Test-Path "$root\new-store")) 'Wrong password wrote files'
$raw[45] = $raw[45] -bxor 1
[IO.File]::WriteAllBytes("$root\tampered.gptbackup", $raw)
& $cli restore "$root\tampered.gptbackup" -Password $password -NoLaunch -Root "$root\destination"
Assert-True ($LASTEXITCODE -eq 1) 'Tampered backup accepted'
Assert-True (-not (Test-Path "$root\new-store")) 'Tampering wrote files'
# Simulate a fresh computer with no authentication file.
Remove-Item -LiteralPath "$root\auth.json" -Force
& $cli restore "$root\accounts.gptbackup" -Password $password -NoLaunch -Root "$root\destination"
Assert-True ($LASTEXITCODE -eq 0) 'Restore failed'
Assert-True (Test-Path "$root\destination\demo\.git") 'Repository not cloned'
Assert-True ((Get-Content -Raw "$root\auth.json") -match 'fake-credential-two') 'Active account not restored'
Assert-True ((Get-Content -Raw "$root\new-store\profiles\one\CodexAuth\auth.json") -match 'fake-credential-one') 'Other account missing'
& $cli switch one -NoLaunch
Assert-True ((Get-Content -Raw "$root\auth.json") -match 'fake-credential-one') 'Imported account cannot switch'
& $cli restore "$root\accounts.gptbackup" -Password $password -NoLaunch -Root "$root\destination"
Assert-True ($LASTEXITCODE -eq 1) 'Existing profile overwritten'
Assert-True ((Get-Content -Raw "$root\auth.json") -match 'fake-credential-one') 'Conflict changed active login'
Write-Host "Transfer tests passed. Synthetic fixtures: $root"
