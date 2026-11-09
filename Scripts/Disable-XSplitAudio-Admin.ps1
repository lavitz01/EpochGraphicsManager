#Requires -Version 5.1
# Run elevated: right-click PowerShell -> Run as administrator, then:
#   pwsh -File "C:\Users\ChaseVFX\Documents\EpochGraphicsManager\Scripts\Disable-XSplitAudio-Admin.ps1"
$ErrorActionPreference = 'Continue'
$ids = @(
    'ROOT\MEDIA\0000',
    'ROOT\MEDIA\0001',
    'SWD\MMDEVAPI\{0.0.0.00000000}.{E6C881C6-2A47-4DD8-95BD-7798B5468966}',
    'SWD\MMDEVAPI\{0.0.1.00000000}.{8F04DCC3-14AB-4191-AC81-DFA086BB0BC9}'
)
foreach ($id in $ids) {
    Write-Host "Disabling $id"
    pnputil.exe /disable-device "$id"
    try { Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop; Write-Host "  OK Disable-PnpDevice" }
    catch { Write-Host "  $($_.Exception.Message)" }
}
Write-Host "`nRemaining XSplit/Broadcaster devices:"
Get-PnpDevice -ErrorAction SilentlyContinue |
  Where-Object { $_.FriendlyName -match 'XSplit|Broadcaster' } |
  Format-Table Status, FriendlyName -AutoSize
Write-Host 'Done. Set Windows default output to Speakers (Realtek), then launch Wow.'
pause
