#Requires -Version 7.0
<#
.SYNOPSIS
  Dark-themed Windows GUI for Project Epoch Graphics Manager.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\Scripts\_bootstrap.ps1"

function Import-EgmModulesFresh {
    . "$PSScriptRoot\..\Scripts\_bootstrap.ps1"
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ui = @{
    Bg       = [Drawing.Color]::FromArgb(18, 20, 24)
    Panel    = [Drawing.Color]::FromArgb(28, 32, 38)
    Accent   = [Drawing.Color]::FromArgb(201, 148, 58)
    Accent2  = [Drawing.Color]::FromArgb(72, 140, 120)
    Text     = [Drawing.Color]::FromArgb(230, 230, 225)
    Muted    = [Drawing.Color]::FromArgb(150, 155, 160)
    Danger   = [Drawing.Color]::FromArgb(190, 80, 70)
    Button   = [Drawing.Color]::FromArgb(40, 46, 54)
    ButtonH  = [Drawing.Color]::FromArgb(55, 62, 72)
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Project Epoch Graphics Manager'
$form.Size = New-Object Drawing.Size(1080, 760)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $ui.Bg
$form.ForeColor = $ui.Text
$form.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$form.MinimumSize = New-Object Drawing.Size(960, 680)

function New-EgmLabel($text, $x, $y, $w = 400, $h = 22, $muted = $false) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object Drawing.Point($x, $y)
    $l.Size = New-Object Drawing.Size($w, $h)
    $l.ForeColor = if ($muted) { $ui.Muted } else { $ui.Text }
    $l.BackColor = [Drawing.Color]::Transparent
    return $l
}

function New-EgmButton($text, $x, $y, $w = 200, $h = 36) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object Drawing.Point($x, $y)
    $b.Size = New-Object Drawing.Size($w, $h)
    $b.FlatStyle = 'Flat'
    $b.BackColor = $ui.Button
    $b.ForeColor = $ui.Text
    $b.FlatAppearance.BorderColor = $ui.Accent
    $b.FlatAppearance.BorderSize = 1
    $b.Cursor = [Windows.Forms.Cursors]::Hand
    $b.add_MouseEnter({ $this.BackColor = $ui.ButtonH })
    $b.add_MouseLeave({ $this.BackColor = $ui.Button })
    return $b
}

$title = New-EgmLabel 'Project Epoch Graphics Manager' 24 18 700 32
$title.Font = New-Object Drawing.Font('Segoe UI Semibold', 16)
$form.Controls.Add($title)

$subtitle = New-EgmLabel '3.3.5a build 12340 · dry-run unless Apply is checked · DLL stages need approval' 24 52 900 22 $true
$form.Controls.Add($subtitle)

# Left action panel
$left = New-Object Windows.Forms.Panel
$left.Location = New-Object Drawing.Point(20, 90)
$left.Size = New-Object Drawing.Size(240, 600)
$left.BackColor = $ui.Panel
$form.Controls.Add($left)

$btnDetect = New-EgmButton 'Detect Game' 20 20 200 34
$btnBackup = New-EgmButton 'Backup Client' 20 64 200 34
$btnHd = New-EgmButton 'Install HD Graphics' 20 108 200 34
$btnLumen = New-EgmButton 'Install Lumenveil' 20 152 200 34
$btnDxvk = New-EgmButton 'Install DXVK' 20 196 200 34
$btnReshade = New-EgmButton 'Install ReShade' 20 240 200 34
$btnRtx = New-EgmButton 'Configure RTX 4090' 20 284 200 34
$btn1080 = New-EgmButton 'Configure GTX 1080' 20 328 200 34
$btnVerify = New-EgmButton 'Verify Installation' 20 372 200 34
$btnRestore = New-EgmButton 'Restore Original Client' 20 416 200 34
$btnBrowse = New-EgmButton 'Browse Client…' 20 470 200 34

foreach ($b in @($btnDetect, $btnBackup, $btnHd, $btnLumen, $btnDxvk, $btnReshade, $btnRtx, $btn1080, $btnVerify, $btnRestore, $btnBrowse)) {
    $left.Controls.Add($b)
}

# Options
$chkApply = New-Object Windows.Forms.CheckBox
$chkApply.Text = 'Apply changes (disable dry-run)'
$chkApply.Location = New-Object Drawing.Point(20, 520)
$chkApply.Size = New-Object Drawing.Size(200, 24)
$chkApply.ForeColor = $ui.Accent
$chkApply.BackColor = $ui.Panel
$left.Controls.Add($chkApply)

$chkDll = New-Object Windows.Forms.CheckBox
$chkDll.Text = 'Approve DLL mods (read rules)'
$chkDll.Location = New-Object Drawing.Point(20, 548)
$chkDll.Size = New-Object Drawing.Size(200, 24)
$chkDll.ForeColor = $ui.Danger
$chkDll.BackColor = $ui.Panel
$left.Controls.Add($chkDll)

# Status panel
$right = New-Object Windows.Forms.Panel
$right.Location = New-Object Drawing.Point(280, 90)
$right.Size = New-Object Drawing.Size(760, 280)
$right.BackColor = $ui.Panel
$form.Controls.Add($right)

$lblVersion = New-EgmLabel 'Detected client version: (not detected)' 16 16 720 22
$lblPath = New-EgmLabel 'Installation directory: (not detected)' 16 44 720 22
$lblBackup = New-EgmLabel 'Backup location: (none)' 16 72 720 22
$lblMods = New-EgmLabel 'Installed modifications: (none)' 16 100 720 40
$lblConflicts = New-EgmLabel 'Conflicts: (none)' 16 146 720 40
$lblVerify = New-EgmLabel 'Download verification: (none)' 16 192 720 40
$lblProgress = New-EgmLabel 'Progress: idle' 16 238 720 22
$lblProgress.ForeColor = $ui.Accent2

foreach ($l in @($lblVersion, $lblPath, $lblBackup, $lblMods, $lblConflicts, $lblVerify, $lblProgress)) {
    $right.Controls.Add($l)
}

# Log box
$logBox = New-Object Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$logBox.Location = New-Object Drawing.Point(280, 386)
$logBox.Size = New-Object Drawing.Size(760, 300)
$logBox.BackColor = [Drawing.Color]::FromArgb(12, 14, 16)
$logBox.ForeColor = $ui.Text
$logBox.Font = New-Object Drawing.Font('Consolas', 9)
$logBox.BorderStyle = 'FixedSingle'
$form.Controls.Add($logBox)

$script:ClientPath = $null
$script:Busy = $false

function Write-UiLog([string]$Message, [string]$Level = 'INFO') {
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    if ($logBox.InvokeRequired) {
        $logBox.Invoke([Action] { $logBox.AppendText($line + [Environment]::NewLine) })
    }
    else {
        $logBox.AppendText($line + [Environment]::NewLine)
    }
}

function Update-UiStatus {
    $state = Get-EgmState
    $lblVersion.Text = "Detected client version: $(if ($state.detectedVersion) { $state.detectedVersion } else { '(not detected)' })"
    $lblPath.Text = "Installation directory: $(if ($state.clientPath) { $state.clientPath } else { '(not detected)' })"
    $lblBackup.Text = "Backup location: $(if ($state.backupPath) { $state.backupPath } else { '(none)' })"
    $modsList = @($state.installedMods)
    $mods = if ($modsList.Count -gt 0) {
        ($modsList | ForEach-Object { "$($_.name)=$($_.status)" }) -join ', '
    } else { '(none)' }
    $lblMods.Text = "Installed modifications: $mods"
    $conflictList = @($state.conflicts)
    $conflicts = if ($conflictList.Count -gt 0) { ($conflictList -join ' | ') } else { '(none)' }
    $lblConflicts.Text = "Conflicts: $conflicts"
    $verifyList = @($state.downloadVerification)
    $verify = if ($verifyList.Count -gt 0) {
        ($verifyList | ForEach-Object { "$($_.name):$($_.status)" }) -join ', '
    } else { '(none)' }
    $lblVerify.Text = "Download verification: $verify"
    if ($state.clientPath) { $script:ClientPath = $state.clientPath }
}

function Ensure-Client {
    if (-not $script:ClientPath) {
        [Windows.Forms.MessageBox]::Show('Detect or browse to a Project Epoch client first.', 'Client required', 'OK', 'Warning') | Out-Null
        return $false
    }
    return $true
}

function Invoke-UiAction {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Work
    )
    if ($script:Busy) { return }
    $script:Busy = $true
    $lblProgress.Text = "Progress: $Name…"
    $form.Cursor = [Windows.Forms.Cursors]::WaitCursor
    try {
        Write-UiLog "Starting: $Name"
        & $Work
        Update-UiStatus
        Write-UiLog "Finished: $Name" 'OK'
        $lblProgress.Text = "Progress: $Name complete"
    }
    catch {
        Write-UiLog $_.Exception.Message 'ERROR'
        $lblProgress.Text = "Progress: $Name failed"
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Error', 'OK', 'Error') | Out-Null
    }
    finally {
        $form.Cursor = [Windows.Forms.Cursors]::Default
        $script:Busy = $false
    }
}

$btnBrowse.Add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select the Project Epoch folder that contains Wow.exe'
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:ClientPath = $dlg.SelectedPath
        Invoke-UiAction -Name 'Validate browsed client' -Work {
            $det = Test-EgmClientPath -Path $script:ClientPath
            if (-not $det.Ok) { throw "Invalid client: $($det.Reasons -join '; ') / $($det.Build.Reason)" }
            $state = Get-EgmState
            $state.clientPath = $det.Path
            $state.detectedVersion = $det.Build.Version
            $state.conflicts = $det.Conflicts
            Save-EgmState -State $state
            Write-UiLog "Client OK: $($det.Path) ($($det.Build.Version))"
            Write-UiLog $det.DllPolicyNote 'WARN'
        }
    }
})

$btnDetect.Add_Click({
    Invoke-UiAction -Name 'Detect Game' -Work {
        Import-EgmModulesFresh
        $det = $null
        # Prefer in-memory path, then saved state, then filesystem scan
        if ($script:ClientPath -and (Test-Path -LiteralPath (Join-Path $script:ClientPath 'Wow.exe'))) {
            $det = Find-EgmClient -Path $script:ClientPath
        }
        if (-not $det -or -not $det.Ok) {
            $det = Find-EgmClient
        }
        if (-not $det.Ok) {
            $msg = (@($det.Reasons) -join ' ')
            [Windows.Forms.MessageBox]::Show(
                "$msg`n`nClick Browse Client and select the folder containing Wow.exe.",
                'Detect Game failed', 'OK', 'Warning') | Out-Null
            throw "Detection failed: $msg"
        }
        $script:ClientPath = $det.Path
        $state = Get-EgmState
        $state.clientPath = $det.Path
        $state.detectedVersion = $det.Build.Version
        $state.conflicts = @($det.Conflicts)
        Save-EgmState -State $state
        $via = if ($det.PSObject.Properties['DetectedVia']) { [string]$det.DetectedVia } else { 'scan' }
        Write-UiLog "Found $($det.Path) (via $via)"
        Write-UiLog "Version $($det.Build.Version) — $($det.Build.Reason)"
        Write-UiLog ("Original MPQs: " + ((@(@($det.OriginalMpqs).Name) -join ', ')))
        Write-UiLog ("Custom MPQs: " + ((@(@($det.CustomGraphics).Name) -join ', ')))
        if (@($det.ProtectedNotes).Count -gt 0) { Write-UiLog ((@($det.ProtectedNotes) -join ' | ')) }
        if (@($det.Conflicts).Count -gt 0) { Write-UiLog ((@($det.Conflicts) -join ' | ')) 'WARN' }
        Write-UiLog $det.DllPolicyNote 'WARN'
    }
})

$btnBackup.Add_Click({
    if (-not (Ensure-Client)) { return }
    Invoke-UiAction -Name 'Backup Client' -Work {
        $r = New-EgmClientBackup -ClientPath $script:ClientPath -Apply:$chkApply.Checked -Force -Logger (New-EgmLogger -Component 'Gui-Backup')
        Write-UiLog "Backup path: $($r.BackupPath) dryRun=$($r.DryRun)"
    }
})

$btnHd.Add_Click({
    if (-not (Ensure-Client)) { return }
    Invoke-UiAction -Name 'Install HD Graphics' -Work {
        try {
            Install-EgmHdGraphics -ClientPath $script:ClientPath -Apply:$chkApply.Checked -Force -Logger (New-EgmLogger -Component 'Gui-HD') | Out-Null
        }
        catch {
            if ($_.Exception.Message -match 'Stage EpochAuthenticHD') {
                Write-UiLog $_.Exception.Message 'WARN'
                [Windows.Forms.MessageBox]::Show(
                    "EpochAuthenticHD must be downloaded manually from the official Google Drive link documented in the project README.`n`nExtract MPQs into:`n$(Join-Path (Get-EgmRoot) 'Staging\EpochAuthenticHD')`n`nThen click Install HD Graphics again.",
                    'Manual staging required', 'OK', 'Information') | Out-Null
            }
            throw
        }
    }
})

$btnLumen.Add_Click({
    if (-not (Ensure-Client)) { return }
    if (-not $chkDll.Checked) {
        [Windows.Forms.MessageBox]::Show('Check "Approve DLL mods" after reading Project Epoch rules.', 'DLL approval required', 'OK', 'Warning') | Out-Null
        return
    }
    Invoke-UiAction -Name 'Install Lumenveil' -Work {
        Import-EgmModulesFresh
        $result = Install-EgmLumenveil -ClientPath $script:ClientPath -Apply:$chkApply.Checked -ApproveDllMods -Force -Logger (New-EgmLogger -Component 'Gui-Lumenveil')
        Write-UiLog ("Lumenveil dryRun=$($result.DryRun) zip=$($result.ZipPath)")
        if (-not $result.DryRun) {
            Write-UiLog 'Lumenveil files installed. Run Lumenveil-Setup.cmd once in the game folder (not auto-run by GUI).' 'WARN'
        }
        else {
            Write-UiLog 'Dry-run only. Check Apply changes to install.' 'WARN'
        }
    }
})

$btnDxvk.Add_Click({
    if (-not (Ensure-Client)) { return }
    if (-not $chkDll.Checked) {
        [Windows.Forms.MessageBox]::Show('Check "Approve DLL mods" after reading Project Epoch rules.', 'DLL approval required', 'OK', 'Warning') | Out-Null
        return
    }
    Invoke-UiAction -Name 'Install DXVK' -Work {
        Install-EgmDxvk -ClientPath $script:ClientPath -Version '2.7.1' -Apply:$chkApply.Checked -ApproveDllMods -Force -Logger (New-EgmLogger -Component 'Gui-DXVK') | Out-Null
    }
})

$btnReshade.Add_Click({
    if (-not (Ensure-Client)) { return }
    if (-not $chkDll.Checked) {
        [Windows.Forms.MessageBox]::Show('Check "Approve DLL mods" after reading Project Epoch rules.', 'DLL approval required', 'OK', 'Warning') | Out-Null
        return
    }
    Invoke-UiAction -Name 'Install ReShade' -Work {
        $profile = if ((Get-EgmState).lastProfile) { (Get-EgmState).lastProfile } else { 'RTX4090' }
        Install-EgmReshade -ClientPath $script:ClientPath -ProfileId $profile -Apply:$chkApply.Checked -ApproveDllMods -Force -Logger (New-EgmLogger -Component 'Gui-ReShade') | Out-Null
        Write-UiLog 'ReShade setup EXE is never auto-run. Follow EpochGraphics-ReShade-INSTALL.txt in the client folder.' 'WARN'
    }
})

$btnRtx.Add_Click({
    if (-not (Ensure-Client)) { return }
    Invoke-UiAction -Name 'Configure RTX 4090' -Work {
        Set-EgmHardwareProfile -ClientPath $script:ClientPath -ProfileId 'RTX4090' -Apply:$chkApply.Checked -Force -Logger (New-EgmLogger -Component 'Gui-RTX4090') | Out-Null
    }
})

$btn1080.Add_Click({
    if (-not (Ensure-Client)) { return }
    Invoke-UiAction -Name 'Configure GTX 1080' -Work {
        Set-EgmHardwareProfile -ClientPath $script:ClientPath -ProfileId 'GTX1080' -Apply:$chkApply.Checked -Force -Logger (New-EgmLogger -Component 'Gui-GTX1080') | Out-Null
    }
})

$btnVerify.Add_Click({
    if (-not (Ensure-Client)) { return }
    Invoke-UiAction -Name 'Verify Installation' -Work {
        $v = Test-EgmInstalledFiles -ClientPath $script:ClientPath -Logger (New-EgmLogger -Component 'Gui-Verify')
        foreach ($c in $v.Checks) {
            Write-UiLog ("{0}: {1}" -f $c.name, $c.detail) $(if ($c.ok) { 'OK' } else { 'WARN' })
        }
    }
})

$btnRestore.Add_Click({
    if (-not (Ensure-Client)) { return }
    $state = Get-EgmState
    if (-not $state.backupPath) {
        [Windows.Forms.MessageBox]::Show('No backup recorded. Create a backup first.', 'Restore', 'OK', 'Warning') | Out-Null
        return
    }
    Invoke-UiAction -Name 'Restore Original Client' -Work {
        Restore-EgmClient -ClientPath $script:ClientPath -BackupPath $state.backupPath -Apply:$chkApply.Checked -Force -Logger (New-EgmLogger -Component 'Gui-Restore') | Out-Null
    }
})

Update-UiStatus
Write-UiLog 'Ready. Dry-run is ON until you check Apply changes.'
Write-UiLog 'Read Project Epoch rules before enabling DLL-based stages (Lumenveil / DXVK / ReShade).' 'WARN'
[Windows.Forms.Application]::Run($form)
