#Requires -Version 7.0
<#
.SYNOPSIS
  Apply RTX 4090 4K maximum-quality Config.wtf / dxvk.conf / ReShade preset (dry-run by default).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ClientPath,
    [switch]$Apply,
    [switch]$Force
)

. "$PSScriptRoot\Scripts\_bootstrap.ps1"
$logger = New-EgmLogger -Component 'Configure-RTX4090'
try {
    $result = Set-EgmHardwareProfile -ClientPath $ClientPath -ProfileId 'RTX4090' -Apply:$Apply -Force:$Force -Logger $logger
    $result | Format-List | Out-String | ForEach-Object { $logger.Write($_.Trim()) }
    if ($result.DryRun) {
        Write-Host 'Dry-run complete. Re-run with -Apply to write configuration.' -ForegroundColor Yellow
    }
    exit 0
}
catch {
    $logger.Write($_.Exception.Message, 'ERROR')
    exit 1
}
