function Select-BackupFile {
    [CmdletBinding()]
    param(
        [ValidateSet('backup', 'restore')][string]$Mode,
        [switch]$ProfilesOnly
    )
    # A dedicated STA runspace also supports callers running in PowerShell MTA.
    $runspace = [RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
    $powershell = [PowerShell]::Create()
    try {
        $runspace.Open()
        $powershell.Runspace = $runspace
        [void]$powershell.AddScript({
            param($Mode, $ProfilesOnly)
            Add-Type -AssemblyName System.Windows.Forms
            $owner = [Windows.Forms.Form]::new()
            $owner.TopMost = $true
            $dialog = $null
            try {
                if ($Mode -eq 'backup') {
                    $dialog = [Windows.Forms.SaveFileDialog]::new()
                    $dialog.Title = 'Salvar backup do gpt-profile'
                    $dialog.FileName = 'gpt-profile-' + (Get-Date -Format 'yyyy-MM-dd-HHmmss')
                    # Existing backups are preserved by the export command.
                    $dialog.OverwritePrompt = $false
                } else {
                    $dialog = [Windows.Forms.OpenFileDialog]::new()
                    $dialog.Title = 'Selecionar backup para restaurar'
                    $dialog.CheckFileExists = $true
                    $dialog.Multiselect = $false
                }
                $dialog.Filter = 'Contas e repositorios (*.gptbackup)|*.gptbackup'
                if (-not $ProfilesOnly) { $dialog.Filter += '|Somente repositorios (*.json)|*.json' }
                $dialog.DefaultExt = 'gptbackup'
                $dialog.AddExtension = $true
                $dialog.CheckPathExists = $true
                $dialog.RestoreDirectory = $true
                $dialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
                if ($dialog.ShowDialog($owner) -eq [Windows.Forms.DialogResult]::OK) {
                    return $dialog.FileName
                }
            } finally {
                if ($dialog) { $dialog.Dispose() }
                $owner.Dispose()
            }
        }).AddArgument($Mode).AddArgument([bool]$ProfilesOnly)
        $result = $powershell.Invoke()
        if ($powershell.HadErrors) { throw "Nao foi possivel abrir a janela de arquivos: $($powershell.Streams.Error[0])" }
        if ($result.Count -gt 0) { return [string]$result[0] }
        return $null
    } finally {
        $powershell.Dispose()
        $runspace.Dispose()
    }
}
