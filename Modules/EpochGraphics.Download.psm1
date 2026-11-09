#Requires -Version 7.0
Set-StrictMode -Version Latest

# Dependencies are loaded by Scripts\_bootstrap.ps1 — do not Import-Module here.

function Get-EgmDownloadDir {
    Initialize-EgmEnvironment
    return (Join-Path (Get-EgmRoot) 'Downloads')
}

function Register-EgmDownloadVerification {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [string]$Path = $null,
        [string]$Sha256 = $null,
        [string]$Detail = $null
    )
    $state = Get-EgmState
    $entry = [pscustomobject]@{
        name      = $Name
        status    = $Status
        path      = $Path
        sha256    = $Sha256
        detail    = $Detail
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $state.downloadVerification = @(@($state.downloadVerification) | Where-Object { $_.name -ne $Name }) + $entry
    Save-EgmState -State $state
    # No pipeline output — prevents ZipPath/Sha256 package pollution under StrictMode.
}

function Invoke-EgmDownload {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile,
        [object]$Logger
    )
    if (-not $Logger) { $Logger = New-EgmLogger -Component 'Download' }
    $dir = Split-Path -Parent $OutFile
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Logger.Write("Downloading $Url")
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    if (-not (Test-Path -LiteralPath $OutFile)) {
        throw "Download failed: $OutFile was not created"
    }
    $Logger.Write("Saved $OutFile")
    # Intentionally no return value — callers must not receive pipeline pollution.
}

function Get-EgmPackageObject {
    <#
    .SYNOPSIS
      Unwrap pipeline-polluted package results to a single PSCustomObject with required properties.
    #>
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)][string[]]$RequiredProperties
    )
    $candidates = @($Package)
    $obj = $candidates |
        Where-Object { $_ -is [System.Management.Automation.PSObject] -and $_ -isnot [string] } |
        Where-Object {
            $item = $_
            ($RequiredProperties | ForEach-Object { [bool]$item.PSObject.Properties[$_] }) -notcontains $false
        } |
        Select-Object -Last 1

    if ($null -eq $obj) {
        $have = @($candidates | ForEach-Object {
                if ($_ -is [string]) { "[string]$_" }
                elseif ($null -eq $_) { '[null]' }
                else { '[' + $_.GetType().Name + '] props=' + (($_.PSObject.Properties.Name) -join ',') }
            }) -join '; '
        throw "Package object missing required properties ($($RequiredProperties -join ', ')). Got: $have"
    }
    return $obj
}

function Get-EgmLumenveilPackage {
    param(
        [switch]$Apply,
        [object]$Logger
    )
    if (-not $Logger) { $Logger = New-EgmLogger -Component 'Download-Lumenveil' }
    $sources = Get-EgmSources
    $lv = $sources.lumenveil
    $dir = Get-EgmDownloadDir
    $zip = Join-Path $dir $([IO.Path]::GetFileName([string]$lv.zipUrl))
    $sums = Join-Path $dir 'Lumenveil-SHA256SUMS.txt'
    $expected = [string]$lv.zipSha256

    if (Test-EgmDryRun -Apply:$Apply) {
        $Logger.Write("Would download $($lv.zipUrl) and verify sha256 $expected", 'DRY')
        $null = Register-EgmDownloadVerification -Name 'Lumenveil' -Status 'dry-run' -Detail ([string]$lv.zipUrl)
        $package = [pscustomobject]@{
            Ok      = $true
            DryRun  = $true
            ZipPath = $zip
            Sha256  = $expected
        }
        return $package
    }

    if (-not (Test-Path -LiteralPath $zip)) {
        Invoke-EgmDownload -Url ([string]$lv.zipUrl) -OutFile $zip -Logger $Logger
    }
    else {
        $Logger.Write("Using existing download: $zip")
    }

    try {
        Invoke-EgmDownload -Url ([string]$lv.sumsUrl) -OutFile $sums -Logger $Logger
    }
    catch {
        $Logger.Write("Could not download SHA256SUMS.txt ($($_.Exception.Message)); using embedded digest from sources.json", 'WARN')
    }

    $hash = Assert-EgmSha256 -Path $zip -ExpectedSha256 $expected
    $null = Register-EgmDownloadVerification -Name 'Lumenveil' -Status 'verified' -Path $zip -Sha256 $hash -Detail "Matched sources.json / release digest for $($lv.version)"
    $Logger.Write("Lumenveil checksum verified: $hash")

    $package = [pscustomobject]@{
        Ok      = $true
        DryRun  = $false
        ZipPath = $zip
        Sha256  = $hash
    }
    return $package
}

function Get-EgmDxvkPackage {
    param(
        [ValidateSet('2.7.1', '3.1.1')]
        [string]$Version = '2.7.1',
        [switch]$Apply,
        [object]$Logger
    )
    if (-not $Logger) { $Logger = New-EgmLogger -Component 'Download-DXVK' }
    $sources = Get-EgmSources
    $meta = $sources.dxvk.versions.$Version
    if (-not $meta) { throw "DXVK version $Version is not in the verified sources catalog." }

    $dir = Get-EgmDownloadDir
    $archive = Join-Path $dir $([IO.Path]::GetFileName($meta.url))

    if (Test-EgmDryRun -Apply:$Apply) {
        $Logger.Write("Would download $($meta.url) and verify sha256 $($meta.sha256)", 'DRY')
        Register-EgmDownloadVerification -Name "DXVK-$Version" -Status 'dry-run' -Detail $meta.url | Out-Null
        return [pscustomobject]@{
            Ok          = $true
            DryRun      = $true
            ArchivePath = $archive
            Version     = $Version
            Meta        = $meta
            Sha256      = [string]$meta.sha256
        }
    }

    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-EgmDownload -Url ([string]$meta.url) -OutFile $archive -Logger $Logger
    }
    else {
        $Logger.Write("Using existing download: $archive")
    }
    $hash = Assert-EgmSha256 -Path $archive -ExpectedSha256 ([string]$meta.sha256)
    $null = Register-EgmDownloadVerification -Name "DXVK-$Version" -Status 'verified' -Path $archive -Sha256 $hash -Detail ([string]$meta.note)
    $Logger.Write("DXVK $Version checksum verified: $hash")

    $package = [pscustomobject]@{
        Ok          = $true
        DryRun      = $false
        ArchivePath = $archive
        Version     = $Version
        Meta        = $meta
        Sha256      = $hash
    }
    return $package
}

function Open-EgmEpochAuthenticHdDownloadPage {
    param([object]$Logger)
    if (-not $Logger) { $Logger = New-EgmLogger -Component 'Download-HD' }
    $sources = Get-EgmSources
    $url = $sources.epochAuthenticHd.manualDownloadUrl
    $Logger.Write("EpochAuthenticHD has no GitHub release assets. Opening documented Google Drive link for manual download.")
    $Logger.Write($url)
    Start-Process $url
    $staging = Join-Path (Get-EgmRoot) 'Staging\EpochAuthenticHD'
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    Register-EgmDownloadVerification -Name 'EpochAuthenticHD' -Status 'manual-required' -Path $staging -Detail 'Place extracted MPQs (and optional Icons) into Staging\EpochAuthenticHD' | Out-Null
    return [pscustomobject]@{
        Ok           = $true
        Manual       = $true
        Url          = $url
        StagingPath  = $staging
        ChecksumNote = 'No official checksum published for the Google Drive pack.'
    }
}

function Open-EgmReshadeDownloadPage {
    param([object]$Logger)
    if (-not $Logger) { $Logger = New-EgmLogger -Component 'Download-ReShade' }
    $sources = Get-EgmSources
    $url = $sources.reshade.downloadPage
    $Logger.Write("Opening official ReShade download page. Setup EXE will NOT be executed by this manager.")
    Start-Process $url
    Register-EgmDownloadVerification -Name 'ReShade' -Status 'manual-setup-required' -Detail $url | Out-Null
    return [pscustomobject]@{
        Ok     = $true
        Manual = $true
        Url    = $url
        Notes  = $sources.reshade.installNotes
    }
}

Export-ModuleMember -Function @(
    'Get-EgmDownloadDir',
    'Register-EgmDownloadVerification',
    'Get-EgmPackageObject',
    'Get-EgmLumenveilPackage',
    'Get-EgmDxvkPackage',
    'Open-EgmEpochAuthenticHdDownloadPage',
    'Open-EgmReshadeDownloadPage'
)
