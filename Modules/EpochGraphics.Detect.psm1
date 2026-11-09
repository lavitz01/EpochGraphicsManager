#Requires -Version 7.0
Set-StrictMode -Version Latest

# Dependencies are loaded by Scripts\_bootstrap.ps1 — do not Import-Module here.

function Get-EgmCandidateRoots {
    $sources = Get-EgmSources
    $drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root
    $candidates = [System.Collections.Generic.List[string]]::new()

    # Previously detected / saved path
    try {
        $state = Get-EgmState
        if ($state.clientPath) { $candidates.Add([string]$state.clientPath) }
    }
    catch { }

    # Known user install from this machine
    $candidates.Add((Join-Path $env:USERPROFILE 'Pictures\project epoch wow\ChromieCraft_3.3.5a'))
    $candidates.Add((Join-Path $env:USERPROFILE 'Pictures\project epoch wow'))
    $candidates.Add((Join-Path $env:USERPROFILE 'Documents\project epoch wow\ChromieCraft_3.3.5a'))
    $candidates.Add((Join-Path $env:USERPROFILE 'Games\ChromieCraft_3.3.5a'))
    $candidates.Add((Join-Path $env:USERPROFILE 'Games\epoch_live'))

    foreach ($drive in $drives) {
        foreach ($rel in $sources.projectEpoch.commonRoots) {
            $candidates.Add((Join-Path $drive $rel))
        }
        foreach ($name in @($sources.projectEpoch.searchFolderNames + @('ChromieCraft_3.3.5a', 'project epoch wow', 'Project Epoch', 'Epoch'))) {
            $candidates.Add((Join-Path $drive $name))
            $candidates.Add((Join-Path $drive "Games\$name"))
            $candidates.Add((Join-Path $drive "Pictures\$name"))
        }
        $candidates.Add((Join-Path $drive 'Pictures\project epoch wow\ChromieCraft_3.3.5a'))
        $candidates.Add((Join-Path $drive 'Users\ChaseVFX\Pictures\project epoch wow\ChromieCraft_3.3.5a'))
    }

    $pf = ${env:ProgramFiles}
    $pf86 = ${env:ProgramFiles(x86)}
    foreach ($base in @($pf, $pf86, $env:LOCALAPPDATA, $env:USERPROFILE)) {
        if ($base) {
            $candidates.Add((Join-Path $base 'Ascension Launcher\resources\epoch_live'))
        }
    }

    # If Project Epoch launcher sits next to a client folder, include siblings
    foreach ($launcherDir in @(
            (Join-Path $env:USERPROFILE 'Pictures\project epoch wow'),
            (Join-Path $env:USERPROFILE 'Documents\project epoch wow'),
            (Join-Path $env:USERPROFILE 'Games')
        )) {
        if (-not (Test-Path -LiteralPath $launcherDir)) { continue }
        Get-ChildItem -LiteralPath $launcherDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $candidates.Add($_.FullName)
        }
        $launcher = Join-Path $launcherDir 'ProjectEpochLauncher.exe'
        if (Test-Path -LiteralPath $launcher) {
            Get-ChildItem -LiteralPath $launcherDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $candidates.Add($_.FullName)
            }
        }
    }

    return @($candidates | Where-Object { $_ } | Select-Object -Unique)
}

function Test-EgmWowBuild12340 {
    param([Parameter(Mandatory)][string]$WowExePath)

    if (-not (Test-Path -LiteralPath $WowExePath)) {
        return [pscustomobject]@{ Ok = $false; Version = $null; Reason = 'Wow.exe missing' }
    }

    $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($WowExePath)
    $product = @($info.ProductVersion, $info.FileVersion, $info.FileDescription, $info.ProductName) -join ' '
    $versionText = if ($info.ProductVersion) { $info.ProductVersion } elseif ($info.FileVersion) { $info.FileVersion } else { 'unknown' }

    # 3.3.5a build 12340 commonly appears as 3.3.5.12340 in version resources.
    $ok = $false
    $reason = 'Version resource did not clearly identify build 12340'
    if ($product -match '12340') {
        $ok = $true
        $reason = 'Build 12340 found in version resource'
    }
    elseif ($versionText -match '^3\.3\.5') {
        $ok = $true
        $reason = "Product reports $versionText; confirm build 12340 if launcher did not stamp 12340 into the EXE"
    }

    return [pscustomobject]@{
        Ok          = $ok
        Version     = $versionText
        ProductInfo = $product
        Reason      = $reason
        Path        = $WowExePath
    }
}

function Get-EgmOriginalEpochMpqs {
    param([Parameter(Mandatory)][string]$ClientPath)
    $sources = Get-EgmSources
    $data = Join-Path $ClientPath 'Data'
    $found = @()
    if (-not (Test-Path -LiteralPath $data)) { return $found }

    foreach ($name in $sources.projectEpoch.launcherManagedMpqs) {
        $match = Get-ChildItem -LiteralPath $data -Filter $name -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($match) {
            $found += [pscustomobject]@{
                Name = $match.Name
                Path = $match.FullName
                Size = $match.Length
                Role = 'launcher-managed'
            }
        }
    }
    return $found
}

function Get-EgmCustomGraphicsMpqs {
    param([Parameter(Mandatory)][string]$ClientPath)
    $sources = Get-EgmSources
    $data = Join-Path $ClientPath 'Data'
    if (-not (Test-Path -LiteralPath $data)) { return @() }

    $expected = @($sources.epochAuthenticHd.expectedMpqFiles)
    $results = @()
    foreach ($name in $expected) {
        $match = Get-ChildItem -LiteralPath $data -Filter $name -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($match) {
            $results += [pscustomobject]@{
                Name = $match.Name
                Path = $match.FullName
                Size = $match.Length
                Role = 'epoch-authentic-hd-candidate'
            }
        }
    }
    return $results
}

function Find-EgmProtectedNotes {
    param([Parameter(Mandatory)][string]$ClientPath)
    $notes = [System.Collections.Generic.List[string]]::new()
    $sources = Get-EgmSources
    $data = Join-Path $ClientPath 'Data'
    if (-not (Test-Path -LiteralPath $data)) { return @() }

    foreach ($protected in $sources.epochAuthenticHd.protectedEpochMpqs) {
        $item = Get-ChildItem -LiteralPath $data -Filter $protected -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($item) {
            $notes.Add("Protected Epoch MPQ present (will not overwrite): $($item.Name)")
        }
    }
    return @($notes | Select-Object -Unique)
}

function Find-EgmConflicts {
    param([Parameter(Mandatory)][string]$ClientPath)
    $conflicts = [System.Collections.Generic.List[string]]::new()

    $versionDll = Join-Path $ClientPath 'version.dll'
    $lumenveil = Join-Path $ClientPath 'CoAVolFog.dll'
    if ((Test-Path -LiteralPath $versionDll) -and -not (Test-Path -LiteralPath $lumenveil)) {
        $conflicts.Add('version.dll is present without CoAVolFog.dll — another loader may conflict with Lumenveil.')
    }

    $d3d9 = Join-Path $ClientPath 'd3d9.dll'
    if (Test-Path -LiteralPath $d3d9) {
        # Could be DXVK or ReShade D3D9 route — report presence for operator awareness.
        $conflicts.Add('d3d9.dll is present. Confirm whether it is DXVK (Vulkan path) or ReShade D3D9 before installing the other.')
    }

    return @($conflicts | Select-Object -Unique)
}

function Test-EgmClientPath {
    param([Parameter(Mandatory)][string]$Path)
    $sources = Get-EgmSources
    $wow = Join-Path $Path 'Wow.exe'
    $data = Join-Path $Path 'Data'
    $reasons = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-Path -LiteralPath $wow)) { $reasons.Add('Wow.exe not found') }
    if (-not (Test-Path -LiteralPath $data)) { $reasons.Add('Data folder not found') }

    $markers = 0
    foreach ($hint in @('ClientExtensions.dll', 'Project-Epoch.exe', 'patch-D.MPQ', 'patch-M.MPQ')) {
        $p1 = Join-Path $Path $hint
        $p2 = Join-Path $data $hint
        if ((Test-Path -LiteralPath $p1) -or (Test-Path -LiteralPath $p2)) { $markers++ }
    }
    if ($Path -match 'epoch_live') { $markers++ }

    $build = if (Test-Path -LiteralPath $wow) { Test-EgmWowBuild12340 -WowExePath $wow } else { $null }
    $ok = ($reasons.Count -eq 0) -and ($null -ne $build) -and $build.Ok

    return [pscustomobject]@{
        Ok               = $ok
        Path             = $Path
        WowExe           = $wow
        Build            = $build
        EpochMarkers     = $markers
        OriginalMpqs     = if (Test-Path -LiteralPath $data) { Get-EgmOriginalEpochMpqs -ClientPath $Path } else { @() }
        CustomGraphics   = if (Test-Path -LiteralPath $data) { Get-EgmCustomGraphicsMpqs -ClientPath $Path } else { @() }
        Conflicts        = if ($ok) { Find-EgmConflicts -ClientPath $Path } else { @() }
        ProtectedNotes   = if ($ok) { Find-EgmProtectedNotes -ClientPath $Path } else { @() }
        Reasons          = @($reasons)
        RequiredBuild    = $sources.projectEpoch.requiredBuild
        NeverModify      = $sources.projectEpoch.neverModify
        DllPolicyNote    = $sources.projectEpoch.dllPolicyNote
    }
}

function Find-EgmClient {
    param([string]$Path)

    if ($Path) {
        return Test-EgmClientPath -Path $Path
    }

    # Prefer last-known good path from state
    try {
        $state = Get-EgmState
        if ($state.clientPath -and (Test-Path -LiteralPath (Join-Path $state.clientPath 'Wow.exe'))) {
            $fromState = Test-EgmClientPath -Path ([string]$state.clientPath)
            if ($fromState.Ok) {
                Add-Member -InputObject $fromState -NotePropertyName DetectedVia -NotePropertyValue 'saved-state' -Force
                return $fromState
            }
        }
    }
    catch { }

    $hits = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in Get-EgmCandidateRoots) {
        $wow = Join-Path $candidate 'Wow.exe'
        if (Test-Path -LiteralPath $wow) {
            $hits.Add((Test-EgmClientPath -Path $candidate))
        }
    }

    $hitCount = @($hits).Count
    if ($hitCount -eq 0) {
        return [pscustomobject]@{
            Ok         = $false
            Path       = $null
            Reasons    = @(
                'No Project Epoch client found in common locations.',
                'Use Browse Client and select the folder that contains Wow.exe',
                '(example: ...\Pictures\project epoch wow\ChromieCraft_3.3.5a).'
            )
            Candidates = @()
        }
    }

    $best = @($hits) | Sort-Object -Property @{ Expression = { if ($_.Ok) { 1 } else { 0 } }; Descending = $true }, EpochMarkers -Descending |
        Select-Object -First 1
    Add-Member -InputObject $best -NotePropertyName Candidates -NotePropertyValue @($hits) -Force
    Add-Member -InputObject $best -NotePropertyName DetectedVia -NotePropertyValue 'filesystem-scan' -Force
    return $best
}

Export-ModuleMember -Function @(
    'Get-EgmCandidateRoots',
    'Test-EgmWowBuild12340',
    'Get-EgmOriginalEpochMpqs',
    'Get-EgmCustomGraphicsMpqs',
    'Find-EgmProtectedNotes',
    'Find-EgmConflicts',
    'Test-EgmClientPath',
    'Find-EgmClient'
)
