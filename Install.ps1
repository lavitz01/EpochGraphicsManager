#Requires -Version 7.0
<#
.SYNOPSIS
  Project Epoch Graphics Manager — CLI orchestrator.
.DESCRIPTION
  Dry-run by default. Pass -Apply to perform writes. DLL stages require -ApproveDllMods.
.EXAMPLE
  pwsh .\Install.ps1 -Action Detect
  pwsh .\Install.ps1 -Action Backup -ClientPath 'D:\Games\epoch_live' -Apply
  pwsh .\Install.ps1 -Action InstallDxvk -ClientPath 'D:\Games\epoch_live' -ApproveDllMods -Apply
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(
        'Detect', 'Backup', 'Verify', 'Restore',
        'InstallHd', 'InstallLumenveil', 'InstallDxvk', 'InstallReshade',
        'ConfigureRtx4090', 'ConfigureGtx1080', 'Gui', 'Status'
    )]
    [string]$Action,

    [string]$ClientPath,
    [string]$BackupPath,
    [string]$BackupRoot,
    [string]$StagingPath,
    [ValidateSet('2.7.1', '3.1.1')][string]$DxvkVersion = '2.7.1',
    [switch]$IncludeIcons,
    [switch]$RunLumenveilSetup,
    [switch]$ApproveDllMods,
    [switch]$Apply,
    [switch]$Force
)

. "$PSScriptRoot\Scripts\_bootstrap.ps1"
$logger = New-EgmLogger -Component 'Install'

function Resolve-Client {
    param([string]$Path)
    if ($Path) { return (Test-EgmClientPath -Path $Path) }
    $state = Get-EgmState
    if ($state.clientPath) { return (Test-EgmClientPath -Path $state.clientPath) }
    return (Find-EgmClient)
}

try {
    switch ($Action) {
        'Gui' {
            & "$PSScriptRoot\Gui\Launch-Gui.ps1"
            break
        }
        'Status' {
            Write-Host (Format-EgmStatusReport -State (Get-EgmState))
            break
        }
        'Detect' {
            $det = Resolve-Client -Path $ClientPath
            if ($det.Ok) {
                $state = Get-EgmState
                $state.clientPath = $det.Path
                $state.detectedVersion = $det.Build.Version
                $state.conflicts = $det.Conflicts
                Save-EgmState -State $state
                $logger.Write("Detected client: $($det.Path) ($($det.Build.Version))")
                $logger.Write("Original Epoch MPQs: $((@($det.OriginalMpqs.Name) -join ', '))")
                $logger.Write("Custom HD MPQs: $((@($det.CustomGraphics.Name) -join ', '))")
                if (@($det.Conflicts).Count -gt 0) { $logger.Write(("Conflicts: " + (@($det.Conflicts) -join ' | ')), 'WARN') }
                Write-Host $det.DllPolicyNote -ForegroundColor DarkYellow
            }
            else {
                $logger.Write("Detection failed: $($det.Reasons -join '; ')", 'ERROR')
                if ($det.Candidates) {
                    $det.Candidates | ForEach-Object { $logger.Write("Candidate: $($_.Path) ok=$($_.Ok)") }
                }
                exit 1
            }
            break
        }
        'Backup' {
            $det = Resolve-Client -Path $ClientPath
            if (-not $det.Ok) { throw "Client not valid: $($det.Reasons -join '; ')" }
            New-EgmClientBackup -ClientPath $det.Path -BackupRoot $BackupRoot -Apply:$Apply -Force:$Force -Logger $logger | Out-Null
            break
        }
        'Verify' {
            $det = Resolve-Client -Path $ClientPath
            if (-not $det.Path) { throw 'No client path.' }
            $v = Test-EgmInstalledFiles -ClientPath $det.Path -Logger $logger
            Write-Host (Format-EgmStatusReport -State (Get-EgmState))
            if (-not $v.Ok) { exit 2 }
            break
        }
        'Restore' {
            $det = Resolve-Client -Path $ClientPath
            if (-not $det.Path) { throw 'No client path.' }
            if (-not $BackupPath) {
                $BackupPath = (Get-EgmState).backupPath
            }
            if (-not $BackupPath) { throw 'Provide -BackupPath or create a backup first.' }
            Restore-EgmClient -ClientPath $det.Path -BackupPath $BackupPath -Apply:$Apply -Force:$Force -Logger $logger | Out-Null
            break
        }
        'InstallHd' {
            $det = Resolve-Client -Path $ClientPath
            if (-not $det.Ok) { throw "Client not valid: $($det.Reasons -join '; ')" }
            Install-EgmHdGraphics -ClientPath $det.Path -StagingPath $StagingPath -IncludeIcons:$IncludeIcons -Apply:$Apply -Force:$Force -Logger $logger | Out-Null
            break
        }
        'InstallLumenveil' {
            $det = Resolve-Client -Path $ClientPath
            if (-not $det.Ok) { throw "Client not valid: $($det.Reasons -join '; ')" }
            Install-EgmLumenveil -ClientPath $det.Path -Apply:$Apply -ApproveDllMods:$ApproveDllMods -Force:$Force -RunSetup:$RunLumenveilSetup -Logger $logger | Out-Null
            break
        }
        'InstallDxvk' {
            $det = Resolve-Client -Path $ClientPath
            if (-not $det.Ok) { throw "Client not valid: $($det.Reasons -join '; ')" }
            Install-EgmDxvk -ClientPath $det.Path -Version $DxvkVersion -Apply:$Apply -ApproveDllMods:$ApproveDllMods -Force:$Force -Logger $logger | Out-Null
            break
        }
        'InstallReshade' {
            $det = Resolve-Client -Path $ClientPath
            if (-not $det.Ok) { throw "Client not valid: $($det.Reasons -join '; ')" }
            $profile = if ((Get-EgmState).lastProfile) { (Get-EgmState).lastProfile } else { 'RTX4090' }
            Install-EgmReshade -ClientPath $det.Path -ProfileId $profile -Apply:$Apply -ApproveDllMods:$ApproveDllMods -Force:$Force -Logger $logger | Out-Null
            break
        }
        'ConfigureRtx4090' {
            $det = Resolve-Client -Path $ClientPath
            if (-not $det.Ok) { throw "Client not valid: $($det.Reasons -join '; ')" }
            Set-EgmHardwareProfile -ClientPath $det.Path -ProfileId 'RTX4090' -Apply:$Apply -Force:$Force -Logger $logger | Out-Null
            break
        }
        'ConfigureGtx1080' {
            $det = Resolve-Client -Path $ClientPath
            if (-not $det.Ok) { throw "Client not valid: $($det.Reasons -join '; ')" }
            Set-EgmHardwareProfile -ClientPath $det.Path -ProfileId 'GTX1080' -Apply:$Apply -Force:$Force -Logger $logger | Out-Null
            break
        }
    }

    if ($Action -ne 'Gui' -and -not $Apply -and $Action -notin @('Detect', 'Verify', 'Status')) {
        Write-Host 'Mode: DRY-RUN (pass -Apply to write changes).' -ForegroundColor Cyan
    }
    if ($Action -ne 'Gui') { exit 0 }
}
catch {
    $logger.Write($_.Exception.Message, 'ERROR')
    exit 1
}
