#Requires -Version 7.0
Set-StrictMode -Version Latest

# Dependencies are loaded by Scripts\_bootstrap.ps1 — do not Import-Module here.

function Test-EgmInstalledFiles {
    param(
        [Parameter(Mandatory)][string]$ClientPath,
        [object]$Logger
    )
    if (-not $Logger) { $Logger = New-EgmLogger -Component 'Verify' }
    $sources = Get-EgmSources
    $checks = [System.Collections.Generic.List[object]]::new()

    function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) {
        $checks.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
        $level = if ($Ok) { 'INFO' } else { 'WARN' }
        $Logger.Write("$Name : $Detail", $level)
    }

    $detection = Test-EgmClientPath -Path $ClientPath
    Add-Check 'Client detection' $detection.Ok ("Path=$ClientPath; version=$($detection.Build.Version); $($detection.Build.Reason)")

    foreach ($protected in $sources.projectEpoch.neverModify) {
        $p = Join-Path $ClientPath $protected
        $exists = Test-Path -LiteralPath $p
        if ($protected -eq 'Wow.exe') {
            Add-Check 'Wow.exe present' $exists $p
        }
        else {
            Add-Check "Launcher file note: $protected" $true $(if ($exists) { "Present (left untouched): $p" } else { "Not present: $p" })
        }
    }

    foreach ($mpq in $sources.epochAuthenticHd.protectedEpochMpqs) {
        $path = Join-Path $ClientPath "Data\$mpq"
        $exists = Test-Path -LiteralPath $path
        Add-Check "Protected Epoch MPQ $mpq" $true $(if ($exists) { "Present and must not be overwritten: $path" } else { "Not found (launcher may restore later): $path" })
    }

    $hd = @(Get-EgmCustomGraphicsMpqs -ClientPath $ClientPath)
    $expectedCount = @($sources.epochAuthenticHd.expectedMpqFiles).Count
    Add-Check 'EpochAuthenticHD MPQs' ($hd.Count -gt 0) ("Found $($hd.Count)/${expectedCount}: $(($hd.Name) -join ', ')")

    $lvMarkers = @($sources.lumenveil.markerFiles | ForEach-Object { Join-Path $ClientPath $_ })
    $lvPresent = @($lvMarkers | Where-Object { Test-Path -LiteralPath $_ })
    $lvDetail = if ($lvPresent.Count -eq 0) {
        'Not installed'
    }
    elseif ($lvPresent.Count -eq $lvMarkers.Count) {
        'Installed marker set complete'
    }
    else {
        "Partial install: $($lvPresent -join ', ')"
    }
    Add-Check 'Lumenveil markers' ($lvPresent.Count -eq 0 -or $lvPresent.Count -eq $lvMarkers.Count) $lvDetail

    $dxvk = Join-Path $ClientPath 'd3d9.dll'
    $dxvkConf = Join-Path $ClientPath 'dxvk.conf'
    if (Test-Path -LiteralPath $dxvk) {
        Add-Check 'DXVK/ReShade d3d9.dll' $true "Present: $dxvk"
        Add-Check 'dxvk.conf' (Test-Path -LiteralPath $dxvkConf) $(if (Test-Path -LiteralPath $dxvkConf) { $dxvkConf } else { 'Missing (optional but recommended with DXVK)' })
    }
    else {
        Add-Check 'DXVK d3d9.dll' $true 'Not installed'
    }

    $reshadeIni = @(Get-ChildItem -LiteralPath $ClientPath -Filter 'ReShade*.ini' -File -ErrorAction SilentlyContinue)
    Add-Check 'ReShade preset files' $true $(if ($reshadeIni.Count -gt 0) { ($reshadeIni.Name -join ', ') } else { 'No ReShade*.ini found in client root' })

    $conflicts = @(Find-EgmConflicts -ClientPath $ClientPath)
    $protected = @(Find-EgmProtectedNotes -ClientPath $ClientPath)
    Add-Check 'Conflict scan' ($conflicts.Count -eq 0) $(if ($conflicts.Count -eq 0) { 'No conflicts detected' } else { ($conflicts -join ' | ') })
    Add-Check 'Protected Epoch content' $true $(if ($protected.Count -eq 0) { 'No protected Epoch MPQ notes' } else { ($protected -join ' | ') })

    $state = Get-EgmState
    $state.clientPath = $ClientPath
    if ($detection.Build) { $state.detectedVersion = $detection.Build.Version }
    $state.conflicts = $conflicts
    Save-EgmState -State $state

    $failed = @($checks | Where-Object { -not $_.ok })
    return [pscustomobject]@{
        Ok            = ($failed.Count -eq 0)
        Checks        = @($checks)
        Failures      = $failed
        Conflicts     = $conflicts
        ProtectedNotes= $protected
    }
}

Export-ModuleMember -Function @('Test-EgmInstalledFiles')
