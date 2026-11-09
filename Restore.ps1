#Requires -Version 7.0
<#
.SYNOPSIS
  Restore Project Epoch client files from a manager backup (dry-run by default).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ClientPath,
    [Parameter(Mandatory)][string]$BackupPath,
    [switch]$Apply,
    [switch]$Force
)

. "$PSScriptRoot\Scripts\_bootstrap.ps1"
$logger = New-EgmLogger -Component 'Restore'
try {
    $result = Restore-EgmClient -ClientPath $ClientPath -BackupPath $BackupPath -Apply:$Apply -Force:$Force -Logger $logger
    $result | Format-List | Out-String | ForEach-Object { $logger.Write($_.Trim()) }
    if ($result.DryRun) {
        Write-Host 'Dry-run complete. Re-run with -Apply to restore.' -ForegroundColor Yellow
    }
    exit 0
}
catch {
    $logger.Write($_.Exception.Message, 'ERROR')
    exit 1
}
