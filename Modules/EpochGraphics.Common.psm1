#Requires -Version 7.0
Set-StrictMode -Version Latest

$script:ModuleRoot = Split-Path -Parent $PSScriptRoot
$script:ConfigPath = Join-Path $script:ModuleRoot 'Config\sources.json'
$script:StateDir = Join-Path $script:ModuleRoot 'State'
$script:LogDir = Join-Path $script:ModuleRoot 'Logs'
$script:DownloadDir = Join-Path $script:ModuleRoot 'Downloads'
$script:StagingDir = Join-Path $script:ModuleRoot 'Staging'
$script:BackupRootDefault = Join-Path $env:USERPROFILE 'EpochGraphicsBackups'

function Get-EgmRoot {
    return $script:ModuleRoot
}

function Get-EgmSources {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        throw "Missing sources catalog: $script:ConfigPath"
    }
    return Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-EgmProfile {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('RTX4090', 'GTX1080')]
        [string]$ProfileId
    )
    $path = Join-Path $script:ModuleRoot "Config\profiles\$ProfileId.json"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing profile: $path"
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Initialize-EgmEnvironment {
    foreach ($dir in @($script:StateDir, $script:LogDir, $script:DownloadDir, $script:StagingDir, $script:BackupRootDefault)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    }
}

function Get-EgmStatePath {
    return Join-Path $script:StateDir 'install-state.json'
}

function Get-EgmState {
    Initialize-EgmEnvironment
    $path = Get-EgmStatePath
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{
            schemaVersion        = 1
            clientPath           = $null
            backupPath           = $null
            detectedVersion      = $null
            installedMods        = @()
            conflicts            = @()
            downloadVerification = @()
            lastProfile          = $null
            dllApproval          = $false
            updatedAtUtc         = $null
        }
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Save-EgmState {
    param(
        [Parameter(Mandatory)]
        [object]$State
    )
    Initialize-EgmEnvironment
    $State.updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $json = $State | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath (Get-EgmStatePath) -Value $json -Encoding UTF8
}

function New-EgmLogger {
    param([string]$Component = 'Manager')
    Initialize-EgmEnvironment
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = Join-Path $script:LogDir "$Component-$stamp.log"

    $logger = [pscustomobject]@{
        Path      = $logPath
        Component = $Component
    }

    $null = Add-Member -InputObject $logger -MemberType ScriptMethod -Name Write -Value {
        param([string]$Message, [string]$Level = 'INFO')
        $line = '{0:u} [{1}] {2}' -f (Get-Date).ToUniversalTime(), $Level.ToUpperInvariant(), $Message
        Add-Content -LiteralPath $this.Path -Value $line -Encoding UTF8 | Out-Null
        switch ($Level.ToUpperInvariant()) {
            'ERROR' { Write-Error $Message }
            'WARN'  { Write-Warning $Message }
            'DRY'   { Write-Host "[DRY-RUN] $Message" -ForegroundColor Cyan }
            default { Write-Host $Message }
        }
    }

    ,$logger
}

function Test-EgmDryRun {
    param([switch]$Apply)
    return -not [bool]$Apply
}

function Confirm-EgmAction {
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$Force
    )
    if ($Force) { return $true }
    $answer = Read-Host "$Message [y/N]"
    return ($answer -match '^(y|yes)$')
}

function Get-EgmFileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found for checksum: $Path"
    }
    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'virus|potentially unwanted|0x800700e1|225') {
            throw @"
Windows Defender is blocking checksum access to '$Path' (often a false positive for Lumenveil DLLs).
Documented upstream: https://github.com/lumenveil/Lumenveil/blob/main/docs/TROUBLESHOOTING.md
Expected SHA-256 (from sources.json / release): verify after allowing the file, or run:
  gh attestation verify <file> --repo lumenveil/Lumenveil
To proceed: allow/restore the file in Windows Security, optionally add an exclusion for:
  $(Split-Path -Parent $Path)
Then re-run the install. Original error: $msg
"@
        }
        throw
    }
}

function Assert-EgmSha256 {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )
    $actual = Get-EgmFileSha256 -Path $Path
    $expected = $ExpectedSha256.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "Checksum mismatch for '$Path'. Expected $expected, got $actual"
    }
    return $actual
}

function Copy-EgmSafeItem {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$Apply,
        [object]$Logger
    )
    $isDry = Test-EgmDryRun -Apply:$Apply
    if ($isDry) {
        if ($Logger) { $Logger.Write("Would copy '$Source' -> '$Destination'", 'DRY') }
        return
    }
    $destDir = Split-Path -Parent $Destination
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    if ($Logger) { $Logger.Write("Copied '$Source' -> '$Destination'") }
}

function Backup-EgmFileBeforeWrite {
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$BackupFolder,
        [switch]$Apply,
        [object]$Logger
    )
    if (-not (Test-Path -LiteralPath $TargetPath)) { return $null }
    $relName = Split-Path -Leaf $TargetPath
    $backupPath = Join-Path $BackupFolder ("prewrite-" + $relName)
    Copy-EgmSafeItem -Source $TargetPath -Destination $backupPath -Apply:$Apply -Logger $Logger
    return $backupPath
}

function Add-EgmInstalledMod {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [hashtable]$Details = @{}
    )
    $existing = @(@($State.installedMods) | Where-Object { $_.name -eq $Name })
    $entry = [pscustomobject]@{
        name      = $Name
        status    = $Status
        details   = $Details
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $current = @($State.installedMods)
    if ($existing.Count -gt 0) {
        $State.installedMods = @($current | Where-Object { $_.name -ne $Name }) + $entry
    }
    else {
        $State.installedMods = $current + $entry
    }
}

function Format-EgmStatusReport {
    param([Parameter(Mandatory)][object]$State)
    $modsList = @($State.installedMods)
    $mods = if ($modsList.Count -gt 0) { ($modsList | ForEach-Object { "$($_.name)=$($_.status)" }) -join ', ' } else { '(none)' }
    $conflictList = @($State.conflicts)
    $conflicts = if ($conflictList.Count -gt 0) { ($conflictList -join '; ') } else { '(none)' }
    $verifyList = @($State.downloadVerification)
    $verify = if ($verifyList.Count -gt 0) {
        ($verifyList | ForEach-Object { "$($_.name):$($_.status)" }) -join ', '
    } else { '(none)' }

    @"
Client Path      : $($State.clientPath)
Detected Version : $($State.detectedVersion)
Backup Location  : $($State.backupPath)
Last Profile     : $($State.lastProfile)
DLL Approval     : $($State.dllApproval)
Installed Mods   : $mods
Conflicts        : $conflicts
Download Verify  : $verify
Updated (UTC)    : $($State.updatedAtUtc)
"@
}

Export-ModuleMember -Function @(
    'Get-EgmRoot',
    'Get-EgmSources',
    'Get-EgmProfile',
    'Initialize-EgmEnvironment',
    'Get-EgmStatePath',
    'Get-EgmState',
    'Save-EgmState',
    'New-EgmLogger',
    'Test-EgmDryRun',
    'Confirm-EgmAction',
    'Get-EgmFileSha256',
    'Assert-EgmSha256',
    'Copy-EgmSafeItem',
    'Backup-EgmFileBeforeWrite',
    'Add-EgmInstalledMod',
    'Format-EgmStatusReport'
)
