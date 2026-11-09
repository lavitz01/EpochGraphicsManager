#Requires -Version 7.0
Set-StrictMode -Version Latest

# Dependencies are loaded by Scripts\_bootstrap.ps1 — do not Import-Module here.

function Get-EgmConfigWtfPath {
    param([Parameter(Mandatory)][string]$ClientPath)
    $wtfDir = Join-Path $ClientPath 'WTF'
    return Join-Path $wtfDir 'Config.wtf'
}

function Read-EgmConfigWtf {
    param([Parameter(Mandatory)][string]$Path)
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        if ($_ -match '^\s*SET\s+(\S+)\s+"(.*)"\s*$') {
            $map[$Matches[1]] = $Matches[2]
        }
    }
    return $map
}

function Write-EgmConfigWtf {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Settings,
        [switch]$Apply,
        [object]$Logger
    )
    $lines = foreach ($key in ($Settings.Keys | Sort-Object)) {
        'SET {0} "{1}"' -f $key, $Settings[$key]
    }
    $text = ($lines -join "`r`n") + "`r`n"
    if (Test-EgmDryRun -Apply:$Apply) {
        if ($Logger) { $Logger.Write("Would write $($Settings.Count) SET lines to $Path", 'DRY') }
        return
    }
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
    if ($Logger) { $Logger.Write("Wrote Config.wtf ($($Settings.Count) keys) -> $Path") }
}

function Merge-EgmConfigSettings {
    param(
        [System.Collections.IDictionary]$Existing,
        [Parameter(Mandatory)][object]$ProfileSettings
    )
    $merged = [ordered]@{}
    if ($Existing) {
        foreach ($k in $Existing.Keys) { $merged[$k] = [string]$Existing[$k] }
    }
    foreach ($prop in $ProfileSettings.PSObject.Properties) {
        $merged[$prop.Name] = [string]$prop.Value
    }
    return $merged
}

function Write-EgmDxvkConf {
    param(
        [Parameter(Mandatory)][string]$ClientPath,
        [Parameter(Mandatory)][object]$ProfileDxvk,
        [switch]$Apply,
        [object]$Logger
    )
    $path = Join-Path $ClientPath 'dxvk.conf'
    $lines = foreach ($prop in $ProfileDxvk.PSObject.Properties) {
        '{0} = {1}' -f $prop.Name, $prop.Value
    }
    $text = ($lines -join "`r`n") + "`r`n"
    if (Test-EgmDryRun -Apply:$Apply) {
        if ($Logger) { $Logger.Write("Would write dxvk.conf -> $path", 'DRY') }
        return
    }
    if (Test-Path -LiteralPath $path) {
        $backupDir = Join-Path (Get-EgmRoot) 'State\prewrite'
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        Copy-Item -LiteralPath $path -Destination (Join-Path $backupDir 'dxvk.conf.bak') -Force
    }
    Set-Content -LiteralPath $path -Value $text -Encoding UTF8
    if ($Logger) { $Logger.Write("Wrote dxvk.conf -> $path") }
}

function Copy-EgmReshadePreset {
    param(
        [Parameter(Mandatory)][string]$ClientPath,
        [Parameter(Mandatory)][string]$PresetFileName,
        [switch]$Apply,
        [object]$Logger
    )
    $src = Join-Path (Get-EgmRoot) "Assets\presets\$PresetFileName"
    if (-not (Test-Path -LiteralPath $src)) {
        throw "Missing preset asset: $src"
    }
    $dest = Join-Path $ClientPath $PresetFileName
    $backupDir = Join-Path (Get-EgmRoot) 'State\prewrite'
    if (-not (Test-EgmDryRun -Apply:$Apply) -and (Test-Path -LiteralPath $dest)) {
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        Copy-Item -LiteralPath $dest -Destination (Join-Path $backupDir $PresetFileName) -Force
    }
    Copy-EgmSafeItem -Source $src -Destination $dest -Apply:$Apply -Logger $Logger
}

function Set-EgmHardwareProfile {
    param(
        [Parameter(Mandatory)][string]$ClientPath,
        [Parameter(Mandatory)][ValidateSet('RTX4090', 'GTX1080')][string]$ProfileId,
        [switch]$Apply,
        [switch]$Force,
        [object]$Logger
    )

    if (-not $Logger) { $Logger = New-EgmLogger -Component "Configure-$ProfileId" }
    $detection = Test-EgmClientPath -Path $ClientPath
    if (-not $detection.Ok) {
        throw "Invalid client path: $($detection.Reasons -join '; ')"
    }

    $profile = Get-EgmProfile -ProfileId $ProfileId
    $isDry = Test-EgmDryRun -Apply:$Apply
    if (-not $isDry -and -not (Confirm-EgmAction -Message "Apply hardware profile $($profile.displayName) to Config.wtf / dxvk.conf / ReShade preset?" -Force:$Force)) {
        throw 'Profile configuration cancelled.'
    }

    $configPath = Get-EgmConfigWtfPath -ClientPath $ClientPath
    $existing = Read-EgmConfigWtf -Path $configPath
    $merged = Merge-EgmConfigSettings -Existing $existing -ProfileSettings $profile.configWtf

    if (-not $isDry -and (Test-Path -LiteralPath $configPath)) {
        $backupDir = Join-Path (Get-EgmRoot) ("State\prewrite\" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        Copy-Item -LiteralPath $configPath -Destination (Join-Path $backupDir 'Config.wtf') -Force
        $Logger.Write("Backed up Config.wtf to $backupDir")
    }

    Write-EgmConfigWtf -Path $configPath -Settings $merged -Apply:$Apply -Logger $Logger
    Write-EgmDxvkConf -ClientPath $ClientPath -ProfileDxvk $profile.dxvkConf -Apply:$Apply -Logger $Logger
    Copy-EgmReshadePreset -ClientPath $ClientPath -PresetFileName $profile.reshadePreset -Apply:$Apply -Logger $Logger

    $guide = Join-Path $ClientPath ("EpochGraphics-$ProfileId-NOTES.txt")
    $guideText = @"
Epoch Graphics Manager — $($profile.displayName)
Generated: $((Get-Date).ToUniversalTime().ToString('o'))

Profile notes:
$(($profile.notes | ForEach-Object { "- $_" }) -join "`r`n")

Lumenveil:
- $($profile.lumenveilHints.note)
- Compare: $($profile.lumenveilHints.compareKey)
- Settings: $($profile.lumenveilHints.settingsKey)

ReShade depth preprocessor definitions (set in ReShade Home tab):
$(($profile.reshadeDepthDefines.PSObject.Properties | ForEach-Object { "- $($_.Name)=$($_.Value)" }) -join "`r`n")

Remember: close the game before editing Config.wtf. Never replace Wow.exe.
"@
    if ($isDry) {
        $Logger.Write("Would write profile notes -> $guide", 'DRY')
    }
    else {
        Set-Content -LiteralPath $guide -Value $guideText -Encoding UTF8
        $Logger.Write("Wrote profile notes -> $guide")
    }

    $state = Get-EgmState
    $state.clientPath = $ClientPath
    $state.lastProfile = $ProfileId
    Add-EgmInstalledMod -State $state -Name "Profile-$ProfileId" -Status $(if ($isDry) { 'dry-run' } else { 'configured' }) -Details @{
        resolution = $profile.hardware.resolution
        refreshHz  = $profile.hardware.refreshHz
        preset     = $profile.reshadePreset
    }
    Save-EgmState -State $state

    return [pscustomobject]@{
        Ok       = $true
        DryRun   = $isDry
        Profile  = $ProfileId
        Config   = $configPath
        Preset   = $profile.reshadePreset
    }
}

Export-ModuleMember -Function @(
    'Get-EgmConfigWtfPath',
    'Read-EgmConfigWtf',
    'Write-EgmConfigWtf',
    'Set-EgmHardwareProfile'
)
