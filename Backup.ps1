#Requires -Version 7.0
<#
.SYNOPSIS
  Full Project Epoch client backup (dry-run by default).
.PARAMETER ClientPath
  Path containing Wow.exe
.PARAMETER BackupRoot
  Optional backup root (default: %USERPROFILE%\EpochGraphicsBackups)
.PARAMETER Apply
  Actually create the backup. Without this switch, runs dry-run only.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ClientPath,
    [string]$BackupRoot,
    [switch]$Apply,
    [switch]$Force
)

. "$PSScriptRoot\Scripts\_bootstrap.ps1"
$logger = New-EgmLogger -Component 'Backup'
try {
    $result = New-EgmClientBackup -ClientPath $ClientPath -BackupRoot $BackupRoot -Apply:$Apply -Force:$Force -Logger $logger
    $result | Format-List | Out-String | ForEach-Object { $logger.Write($_.Trim()) }
    if ($result.DryRun) {
        Write-Host 'Dry-run complete. Re-run with -Apply to create the backup.' -ForegroundColor Yellow
    }
    exit 0
}
catch {
    $logger.Write($_.Exception.Message, 'ERROR')
    exit 1
}
