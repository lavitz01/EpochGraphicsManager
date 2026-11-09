#Requires -Version 7.0
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$modules = Join-Path $root 'Modules'

# Always drop prior copies so GUI/CLI pick up fixes (ZipPath, StrictMode, etc.).
Get-Module -Name 'EpochGraphics.*' -All -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
@(
    'EpochGraphics.Common',
    'EpochGraphics.Detect',
    'EpochGraphics.Backup',
    'EpochGraphics.Verify',
    'EpochGraphics.Restore',
    'EpochGraphics.Configure',
    'EpochGraphics.Download',
    'EpochGraphics.Install'
) | ForEach-Object {
    Remove-Module -Name $_ -Force -ErrorAction SilentlyContinue
}

Import-Module (Join-Path $modules 'EpochGraphics.Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $modules 'EpochGraphics.Detect.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $modules 'EpochGraphics.Backup.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $modules 'EpochGraphics.Verify.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $modules 'EpochGraphics.Restore.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $modules 'EpochGraphics.Configure.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $modules 'EpochGraphics.Download.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $modules 'EpochGraphics.Install.psm1') -Force -DisableNameChecking

Initialize-EgmEnvironment
