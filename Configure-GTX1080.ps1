#Requires -Version 7.0
<#
.SYNOPSIS
  Apply GTX 1080 1440p maximum-compatible Config.wtf / dxvk.conf / ReShade preset (dry-run by default).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ClientPath,
    [switch]$Apply,
    [switch]$Force
)

. "$PSScriptRoot\Scripts\_bootstrap.ps1"
$logger = New-EgmLogger -Component 'Configure-GTX1080'
try {
    $result = Set-EgmHardwareProfile -ClientPath $ClientPath -ProfileId 'GTX1080' -Apply:$Apply -Force:$Force -Logger $logger
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
