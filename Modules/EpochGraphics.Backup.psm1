#Requires -Version 7.0
Set-StrictMode -Version Latest

# Dependencies are loaded by Scripts\_bootstrap.ps1 — do not Import-Module here.

function Get-EgmBackupRoot {
    param([string]$BackupRoot)
    if ($BackupRoot) { return $BackupRoot }
    return (Join-Path $env:USERPROFILE 'EpochGraphicsBackups')
}

function New-EgmClientBackup {
    param(
        [Parameter(Mandatory)][string]$ClientPath,
        [string]$BackupRoot,
        [switch]$Apply,
        [switch]$Force,
        [object]$Logger
    )

    if (-not $Logger) { $Logger = New-EgmLogger -Component 'Backup' }
    $detection = Test-EgmClientPath -Path $ClientPath
    if (-not $detection.Ok) {
        throw "Refusing backup of invalid client: $($detection.Reasons -join '; ')"
    }

    $root = Get-EgmBackupRoot -BackupRoot $BackupRoot
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $target = Join-Path $root ("epoch-client-backup-" + $stamp)
    $manifestPath = Join-Path $target 'backup-manifest.json'
    $isDry = Test-EgmDryRun -Apply:$Apply

    if (-not $isDry -and -not (Confirm-EgmAction -Message "Create full client backup at '$target'?" -Force:$Force)) {
        throw 'Backup cancelled by user.'
    }

    $Logger.Write("Backup target: $target")
    if ($isDry) {
        $Logger.Write("Would mirror entire client tree from '$ClientPath' to '$target'", 'DRY')
        return [pscustomobject]@{
            Ok         = $true
            DryRun     = $true
            BackupPath = $target
            Manifest   = $null
        }
    }

    New-Item -ItemType Directory -Force -Path $target | Out-Null

    # Full client mirror — never deletes source files.
    $robolog = Join-Path $target 'robocopy.log'
    $args = @(
        $ClientPath,
        $target,
        '/E', '/COPY:DAT', '/R:2', '/W:2', '/NFL', '/NDL', '/NP',
        "/LOG:$robolog"
    )
    $rc = Start-Process -FilePath 'robocopy.exe' -ArgumentList $args -Wait -PassThru
    # Robocopy exit codes 0-7 are success/partial success.
    if ($rc.ExitCode -ge 8) {
        throw "Robocopy failed with exit code $($rc.ExitCode). See $robolog"
    }

    $fileCount = (Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    $manifest = [pscustomobject]@{
        createdAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
        sourcePath     = $ClientPath
        backupPath     = $target
        detectedVersion= $detection.Build.Version
        fileCount      = $fileCount
        robocopyExit   = $rc.ExitCode
        originalMpqs   = $detection.OriginalMpqs
        neverModify    = $detection.NeverModify
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $state = Get-EgmState
    $state.clientPath = $ClientPath
    $state.backupPath = $target
    $state.detectedVersion = $detection.Build.Version
    Save-EgmState -State $state

    $Logger.Write("Backup complete: $fileCount files -> $target")
    return [pscustomobject]@{
        Ok         = $true
        DryRun     = $false
        BackupPath = $target
        Manifest   = $manifest
    }
}

Export-ModuleMember -Function @('Get-EgmBackupRoot', 'New-EgmClientBackup')
