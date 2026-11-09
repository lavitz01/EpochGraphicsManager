#Requires -Version 7.0
Set-StrictMode -Version Latest

# Dependencies are loaded by Scripts\_bootstrap.ps1 — do not Import-Module here.

function Assert-EgmDllApproval {
    param(
        [switch]$ApproveDllMods,
        [switch]$Force
    )
    $state = Get-EgmState
    $sources = Get-EgmSources
    if ($ApproveDllMods) {
        if (-not $Force -and -not (Confirm-EgmAction -Message @"
DLL WARNING
$($sources.projectEpoch.dllPolicyNote)

Type YES to approve optional DLL-based stages (Lumenveil / DXVK / ReShade) for this session.
"@ )) {
            throw 'DLL modifications not approved.'
        }
        # Confirm-EgmAction uses y/yes; for DLL we want explicit awareness — also set state flag after y/yes.
        $state.dllApproval = $true
        Save-EgmState -State $state
        return
    }
    if (-not $state.dllApproval) {
        throw 'DLL modifications are locked. Re-run with -ApproveDllMods after reading Project Epoch rules, or approve in the GUI.'
    }
}

function Install-EgmHdGraphics {
    param(
        [Parameter(Mandatory)][string]$ClientPath,
        [string]$StagingPath,
        [switch]$IncludeIcons,
        [switch]$Apply,
        [switch]$Force,
        [object]$Logger
    )
    if (-not $Logger) { $Logger = New-EgmLogger -Component 'Install-HD' }
    $sources = Get-EgmSources
    $isDry = Test-EgmDryRun -Apply:$Apply
    $detection = Test-EgmClientPath -Path $ClientPath
    if (-not $detection.Ok) { throw "Invalid client: $($detection.Reasons -join '; ')" }

    if (-not $StagingPath) {
        $StagingPath = Join-Path (Get-EgmRoot) 'Staging\EpochAuthenticHD'
    }
    if (-not (Test-Path -LiteralPath $StagingPath)) {
        Open-EgmEpochAuthenticHdDownloadPage -Logger $Logger | Out-Null
        throw "Stage EpochAuthenticHD files into '$StagingPath' first (extract MPQs from the official Google Drive pack)."
    }

    $dataDir = Join-Path $ClientPath 'Data'
    $protected = @($sources.epochAuthenticHd.protectedEpochMpqs | ForEach-Object { $_.ToLowerInvariant() })
    $mpqs = @(Get-ChildItem -LiteralPath $StagingPath -Recurse -File -Include *.MPQ, *.mpq -ErrorAction SilentlyContinue)
    if ($mpqs.Count -eq 0) {
        throw "No .MPQ files found under staging path '$StagingPath'."
    }

    $plan = @()
    foreach ($mpq in $mpqs) {
        $name = $mpq.Name
        if ($protected -contains $name.ToLowerInvariant()) {
            throw "Refusing to install '$name' — this letter is reserved for Epoch's original PATCH-D / PATCH-M. Do not overwrite without explicit manual confirmation outside this tool."
        }
        # Detect accidental use of old lettering from pre-11/08/2026 packs.
        if ($name -match '^(?i)patch-[DEM]\.MPQ$') {
            $Logger.Write("Staged file $name uses a letter that Epoch may own or that AuthenticHD remapped. Verify against current README before applying.", 'WARN')
        }
        $dest = Join-Path $dataDir $name
        if (Test-Path -LiteralPath $dest) {
            $Logger.Write("Destination already exists: $dest — will backup then replace only with -Apply", 'WARN')
        }
        $plan += [pscustomobject]@{ Source = $mpq.FullName; Destination = $dest; Name = $name }
    }

    if (-not $isDry -and -not (Confirm-EgmAction -Message "Install $($plan.Count) HD MPQ file(s) into Data? Original files are never deleted; existing targets are backed up first." -Force:$Force)) {
        throw 'HD install cancelled.'
    }

    $preDir = Join-Path (Get-EgmRoot) ("State\prewrite\hd-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    foreach ($item in $plan) {
        if (-not $isDry -and (Test-Path -LiteralPath $item.Destination)) {
            New-Item -ItemType Directory -Force -Path $preDir | Out-Null
            Copy-Item -LiteralPath $item.Destination -Destination (Join-Path $preDir $item.Name) -Force
        }
        Copy-EgmSafeItem -Source $item.Source -Destination $item.Destination -Apply:$Apply -Logger $Logger
    }

    if ($IncludeIcons) {
        $icons = Get-ChildItem -LiteralPath $StagingPath -Directory -Filter 'Icons' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($icons) {
            $destIcons = Join-Path $ClientPath 'Interface\Icons'
            if ($isDry) {
                $Logger.Write("Would copy Icons folder -> $destIcons", 'DRY')
            }
            else {
                New-Item -ItemType Directory -Force -Path $destIcons | Out-Null
                Copy-Item -Path (Join-Path $icons.FullName '*') -Destination $destIcons -Recurse -Force
                $Logger.Write("Copied Icons -> $destIcons")
            }
        }
        else {
            $Logger.Write('IncludeIcons requested but no Icons folder found in staging.', 'WARN')
        }
    }

    $state = Get-EgmState
    Add-EgmInstalledMod -State $state -Name 'EpochAuthenticHD' -Status $(if ($isDry) { 'dry-run' } else { 'files-copied' }) -Details @{
        mpqCount = $plan.Count
        names    = @($plan.Name)
    }
    Save-EgmState -State $state

    if (-not $isDry) {
        $verify = Test-EgmInstalledFiles -ClientPath $ClientPath -Logger $Logger
        if (-not ($verify.Checks | Where-Object { $_.name -eq 'EpochAuthenticHD MPQs' -and $_.ok })) {
            throw 'HD files were copied but verification did not confirm expected MPQs.'
        }
        $Logger.Write('HD graphics install verified.')
    }

    return [pscustomobject]@{ Ok = $true; DryRun = $isDry; Planned = $plan }
}

function Install-EgmLumenveil {
    param(
        [Parameter(Mandatory)][string]$ClientPath,
        [switch]$Apply,
        [switch]$ApproveDllMods,
        [switch]$Force,
        [switch]$RunSetup,
        [object]$Logger
    )
    if (-not $Logger) { $Logger = New-EgmLogger -Component 'Install-Lumenveil' }
    Assert-EgmDllApproval -ApproveDllMods:$ApproveDllMods -Force:$Force
    $isDry = Test-EgmDryRun -Apply:$Apply
    $sources = Get-EgmSources

    $conflicts = Find-EgmConflicts -ClientPath $ClientPath
    $versionConflict = $conflicts | Where-Object { $_ -match 'version\.dll is present without CoAVolFog' }
    if ($versionConflict) {
        throw "Conflict detected: $versionConflict"
    }

    # Resolve zip path from catalog — never depend on download-function pipeline objects for ZipPath.
    $zipPath = Join-Path (Get-EgmDownloadDir) ([IO.Path]::GetFileName([string]$sources.lumenveil.zipUrl))
    $expectedSha = [string]$sources.lumenveil.zipSha256

    # Side-effect: download + checksum. Discard any pipeline shape.
    $null = @(Get-EgmLumenveilPackage -Apply:$Apply -Logger $Logger)

    if ($isDry) {
        $Logger.Write("Dry-run: would extract '$zipPath' into client (sha256 $expectedSha).", 'DRY')
        return [pscustomobject]@{ Ok = $true; DryRun = $true; ZipPath = $zipPath; Sha256 = $expectedSha }
    }

    if (-not (Test-Path -LiteralPath $zipPath)) {
        throw "Lumenveil zip not found at '$zipPath' after download."
    }
    $sha = Assert-EgmSha256 -Path $zipPath -ExpectedSha256 $expectedSha

    $stage = Join-Path (Get-EgmRoot) ('Staging\Lumenveil-' + $sources.lumenveil.version)
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    $null = New-Item -ItemType Directory -Force -Path $stage
    Expand-Archive -LiteralPath $zipPath -DestinationPath $stage -Force

    # Zip may contain a root folder or flat files — copy payload next to Wow.exe.
    $payloadRoot = $stage
    $nested = Get-ChildItem -LiteralPath $stage -Directory | Select-Object -First 1
    if ((Test-Path -LiteralPath (Join-Path $stage 'version.dll')) -eq $false -and $nested) {
        $payloadRoot = $nested.FullName
    }

    $preDir = Join-Path (Get-EgmRoot) ("State\prewrite\lumenveil-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $preDir | Out-Null
    foreach ($marker in $sources.lumenveil.markerFiles) {
        $existing = Join-Path $ClientPath $marker
        if (Test-Path -LiteralPath $existing) {
            Copy-Item -LiteralPath $existing -Destination (Join-Path $preDir $marker) -Force
        }
    }

    if (-not (Confirm-EgmAction -Message "Copy Lumenveil $($sources.lumenveil.version) files into '$ClientPath'? Setup.cmd will NOT run unless -RunSetup is also specified." -Force:$Force)) {
        throw 'Lumenveil install cancelled.'
    }

    Copy-Item -Path (Join-Path $payloadRoot '*') -Destination $ClientPath -Recurse -Force
    $Logger.Write("Lumenveil files copied to $ClientPath")

    if ($RunSetup) {
        $setup = Join-Path $ClientPath $sources.lumenveil.setupScript
        if (-not (Test-Path -LiteralPath $setup)) { throw "Missing setup script: $setup" }
        if (-not (Confirm-EgmAction -Message "Run $($sources.lumenveil.setupScript)? It reads local MPQs and writes lampdata.bin / liquiddata.bin. It does not change game archives." -Force:$Force)) {
            $Logger.Write('Setup.cmd skipped by user.', 'WARN')
        }
        else {
            # User-approved local setup only — still not a downloaded arbitrary EXE beyond the verified zip.
            Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$setup`"" -WorkingDirectory $ClientPath -Wait
            $Logger.Write('Lumenveil-Setup.cmd finished.')
        }
    }
    else {
        $Logger.Write('Lumenveil files staged. Run Lumenveil-Setup.cmd manually once (or re-run with -RunSetup).')
    }

    $state = Get-EgmState
    Add-EgmInstalledMod -State $state -Name 'Lumenveil' -Status 'installed' -Details @{
        version  = $sources.lumenveil.version
        sha256   = $sha
        zipPath  = $zipPath
        setupRun = [bool]$RunSetup
    }
    Save-EgmState -State $state

    $verify = Test-EgmInstalledFiles -ClientPath $ClientPath -Logger $Logger
    $lvCheck = @($verify.Checks | Where-Object { $_.name -eq 'Lumenveil markers' } | Select-Object -First 1)
    if ($lvCheck.Count -eq 0 -or -not $lvCheck[0].ok) {
        throw 'Lumenveil verification failed after copy.'
    }
    $Logger.Write("Lumenveil installation verified (sha256=$sha).")
    return [pscustomobject]@{ Ok = $true; DryRun = $false; Version = $sources.lumenveil.version; ZipPath = $zipPath; Sha256 = $sha }
}

function Install-EgmDxvk {
    param(
        [Parameter(Mandatory)][string]$ClientPath,
        [ValidateSet('2.7.1', '3.1.1')][string]$Version = '2.7.1',
        [switch]$Apply,
        [switch]$ApproveDllMods,
        [switch]$Force,
        [object]$Logger
    )
    if (-not $Logger) { $Logger = New-EgmLogger -Component 'Install-DXVK' }
    Assert-EgmDllApproval -ApproveDllMods:$ApproveDllMods -Force:$Force
    $isDry = Test-EgmDryRun -Apply:$Apply
    $sources = Get-EgmSources
    $meta = $sources.dxvk.versions.$Version

    $dxMeta = $sources.dxvk.versions.$Version
    $archivePath = Join-Path (Get-EgmDownloadDir) ([IO.Path]::GetFileName([string]$dxMeta.url))
    $expectedDxSha = [string]$dxMeta.sha256

    $null = @(Get-EgmDxvkPackage -Version $Version -Apply:$Apply -Logger $Logger)
    if ($isDry) {
        return [pscustomobject]@{ Ok = $true; DryRun = $true; Version = $Version; ArchivePath = $archivePath; Sha256 = $expectedDxSha }
    }

    if (-not (Test-Path -LiteralPath $archivePath)) {
        throw "DXVK archive not found at '$archivePath' after download."
    }
    $sha = Assert-EgmSha256 -Path $archivePath -ExpectedSha256 $expectedDxSha

    $extract = Join-Path (Get-EgmRoot) ("Staging\dxvk-$Version")
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
    $null = New-Item -ItemType Directory -Force -Path $extract

    # tar.gz from GitHub — use tar (Windows 10+ / PowerShell 7).
    & tar -xf $archivePath -C $extract
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract DXVK archive (tar exit $LASTEXITCODE)" }

    $dllRelative = $meta.dllRelativePath -replace '/', [IO.Path]::DirectorySeparatorChar
    $dllSource = Join-Path $extract $dllRelative
    if (-not (Test-Path -LiteralPath $dllSource)) {
        # Some extractions nest an extra folder; search for x32\d3d9.dll
        $dllSource = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'd3d9.dll' |
            Where-Object { $_.Directory.Name -eq 'x32' } |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $dllSource -or -not (Test-Path -LiteralPath $dllSource)) {
        throw "Could not locate x32\\d3d9.dll inside DXVK $Version archive."
    }

    $dest = Join-Path $ClientPath 'd3d9.dll'
    if (Test-Path -LiteralPath $dest) {
        $preDir = Join-Path (Get-EgmRoot) ("State\prewrite\dxvk-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Force -Path $preDir | Out-Null
        Copy-Item -LiteralPath $dest -Destination (Join-Path $preDir 'd3d9.dll') -Force
        $Logger.Write("Existing d3d9.dll backed up to $preDir", 'WARN')
    }

    if (-not (Confirm-EgmAction -Message "Install DXVK $Version x32\\d3d9.dll next to Wow.exe?" -Force:$Force)) {
        throw 'DXVK install cancelled.'
    }

    Copy-Item -LiteralPath $dllSource -Destination $dest -Force
    $confPath = Join-Path $ClientPath 'dxvk.conf'
    if (-not (Test-Path -LiteralPath $confPath)) {
        Set-Content -LiteralPath $confPath -Value $sources.dxvk.confFile.contents -Encoding UTF8
    }

    $state = Get-EgmState
    Add-EgmInstalledMod -State $state -Name 'DXVK' -Status 'installed' -Details @{
        version     = $Version
        sha256      = $sha
        archivePath = $archivePath
        dll         = $dest
    }
    Save-EgmState -State $state

    if (-not (Test-Path -LiteralPath $dest)) { throw 'DXVK d3d9.dll missing after copy — install not verified.' }
    $Logger.Write("DXVK $Version installed and file present: $dest (sha256=$sha)")
    return [pscustomobject]@{ Ok = $true; DryRun = $false; Version = $Version; Dll = $dest; Sha256 = $sha }
}

function Install-EgmReshade {
    param(
        [Parameter(Mandatory)][string]$ClientPath,
        [ValidateSet('RTX4090', 'GTX1080')][string]$ProfileId = 'RTX4090',
        [switch]$Apply,
        [switch]$ApproveDllMods,
        [switch]$Force,
        [object]$Logger
    )
    if (-not $Logger) { $Logger = New-EgmLogger -Component 'Install-ReShade' }
    Assert-EgmDllApproval -ApproveDllMods:$ApproveDllMods -Force:$Force
    $isDry = Test-EgmDryRun -Apply:$Apply
    $sources = Get-EgmSources
    $profile = Get-EgmProfile -ProfileId $ProfileId

    Open-EgmReshadeDownloadPage -Logger $Logger | Out-Null

    $guide = Join-Path $ClientPath 'EpochGraphics-ReShade-INSTALL.txt'
    $hasDxvk = Test-Path -LiteralPath (Join-Path $ClientPath 'd3d9.dll')
    $api = if ($hasDxvk) { 'Vulkan (because DXVK is present as d3d9.dll)' } else { 'Direct3D 9' }

    $text = @"
ReShade guided install (manager never runs the setup EXE)

1. Download ReShade from $($sources.reshade.downloadPage) (noted version $($sources.reshade.versionNoted)).
2. Run the official setup yourself.
3. Select: $ClientPath\Wow.exe
4. Choose rendering API: $api
5. When prompted for effect packages, enable:
   - SweetFX by CeeJay.dk
   - iMMERSE by Marty McFly
6. After setup, select preset: $($profile.reshadePreset) (copied by this manager when you apply a hardware profile).
7. In ReShade Home → Edit global preprocessor definitions, set:
$(($profile.reshadeDepthDefines.PSObject.Properties | ForEach-Object { "   $($_.Name)=$($_.Value)" }) -join "`r`n")

Lumenveil docs: $($sources.lumenveil.installDoc.Replace('INSTALL.md','RESHADE.md'))
Project Epoch rules: $($sources.projectEpoch.rulesUrl)
"@

    if ($isDry) {
        $Logger.Write("Would write ReShade guide and copy preset $($profile.reshadePreset)", 'DRY')
        return [pscustomobject]@{ Ok = $true; DryRun = $true }
    }

    if (-not (Confirm-EgmAction -Message 'Write ReShade install guide and copy the profile preset into the client folder? (Setup EXE still manual.)' -Force:$Force)) {
        throw 'ReShade preparation cancelled.'
    }

    Set-Content -LiteralPath $guide -Value $text -Encoding UTF8
    $src = Join-Path (Get-EgmRoot) "Assets\presets\$($profile.reshadePreset)"
    Copy-Item -LiteralPath $src -Destination (Join-Path $ClientPath $profile.reshadePreset) -Force

    $state = Get-EgmState
    Add-EgmInstalledMod -State $state -Name 'ReShade' -Status 'guide-and-preset-prepared' -Details @{
        apiHint = $api
        preset  = $profile.reshadePreset
        guide   = $guide
    }
    Save-EgmState -State $state
    $Logger.Write("ReShade guide written to $guide — complete setup manually, then use Verify.")
    return [pscustomobject]@{ Ok = $true; DryRun = $false; Guide = $guide; Preset = $profile.reshadePreset }
}

Export-ModuleMember -Function @(
    'Install-EgmHdGraphics',
    'Install-EgmLumenveil',
    'Install-EgmDxvk',
    'Install-EgmReshade'
)
