#Requires -Version 7.0
Set-StrictMode -Version Latest

# Dependencies are loaded by Scripts\_bootstrap.ps1 — do not Import-Module here.

function Restore-EgmClient {
    param(
        [Parameter(Mandatory)][string]$ClientPath,
        [Parameter(Mandatory)][string]$BackupPath,
        [switch]$Apply,
        [switch]$Force,
        [object]$Logger
    )

    if (-not $Logger) { $Logger = New-EgmLogger -Component 'Restore' }
    $isDry = Test-EgmDryRun -Apply:$Apply

    if (-not (Test-Path -LiteralPath $BackupPath)) {
        throw "Backup path not found: $BackupPath"
    }
    $manifest = Join-Path $BackupPath 'backup-manifest.json'
    if (-not (Test-Path -LiteralPath $manifest)) {
        $Logger.Write("backup-manifest.json missing in $BackupPath — restore still possible but less verified.", 'WARN')
    }

    if (-not $isDry -and -not (Confirm-EgmAction -Message "Restore client from '$BackupPath' into '$ClientPath'? This overwrites modified files with backup copies but does not delete unmatched new files." -Force:$Force)) {
        throw 'Restore cancelled by user.'
    }

    # Safety copy of current client before restore write.
    $pre = Join-Path (Split-Path -Parent $BackupPath) ("pre-restore-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    if ($isDry) {
        $Logger.Write("Would snapshot current client to '$pre' then robocopy backup -> client", 'DRY')
        return [pscustomobject]@{ Ok = $true; DryRun = $true; PreRestoreSnapshot = $pre }
    }

    New-Item -ItemType Directory -Force -Path $pre | Out-Null
    $snapArgs = @($ClientPath, $pre, '/E', '/COPY:DAT', '/R:2', '/W:2', '/NFL', '/NDL', '/NP')
    $snap = Start-Process -FilePath 'robocopy.exe' -ArgumentList $snapArgs -Wait -PassThru
    if ($snap.ExitCode -ge 8) {
        throw "Failed to snapshot current client before restore. Exit $($snap.ExitCode)"
    }

    $restoreArgs = @($BackupPath, $ClientPath, '/E', '/COPY:DAT', '/R:2', '/W:2', '/NFL', '/NDL', '/NP', '/XF', 'backup-manifest.json', 'robocopy.log')
    $rc = Start-Process -FilePath 'robocopy.exe' -ArgumentList $restoreArgs -Wait -PassThru
    if ($rc.ExitCode -ge 8) {
        throw "Restore robocopy failed with exit code $($rc.ExitCode)"
    }

    $state = Get-EgmState
    $state.clientPath = $ClientPath
    $state.backupPath = $BackupPath
    $state.installedMods = @([pscustomobject]@{
            name = 'Restore'
            status = 'restored-from-backup'
            details = @{ backup = $BackupPath; preRestoreSnapshot = $pre }
            updatedAt = (Get-Date).ToUniversalTime().ToString('o')
        })
    Save-EgmState -State $state

    $Logger.Write("Restore complete from $BackupPath (pre-restore snapshot: $pre)")
    return [pscustomobject]@{
        Ok                 = $true
        DryRun             = $false
        PreRestoreSnapshot = $pre
        BackupPath         = $BackupPath
    }
}

Export-ModuleMember -Function @('Restore-EgmClient')
