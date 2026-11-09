#Requires -Version 7.0
<#
.SYNOPSIS
  Verify Project Epoch client integrity markers and installed graphics modifications.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ClientPath
)

. "$PSScriptRoot\Scripts\_bootstrap.ps1"
$logger = New-EgmLogger -Component 'Verify'
try {
    $result = Test-EgmInstalledFiles -ClientPath $ClientPath -Logger $logger
    Write-Host ''
    Write-Host (Format-EgmStatusReport -State (Get-EgmState))
    if (-not $result.Ok) {
        Write-Host 'Verification reported warnings/failures. Review log output above.' -ForegroundColor Yellow
        exit 2
    }
    Write-Host 'Verification passed.' -ForegroundColor Green
    exit 0
}
catch {
    $logger.Write($_.Exception.Message, 'ERROR')
    exit 1
}
