#Requires -Version 5.1
<#
.SYNOPSIS
  Windows Update + optional software (winget) upgrades from the command line.

.DESCRIPTION
  - Scans and installs all available Windows Updates automatically (accepts all).
  - Reports what was installed / failed.
  - Shows winget software upgrades and prompts Yes/No before installing.
  - Detects reboot requirement and prompts if a restart is needed.

.NOTES
  Run as Administrator (script will self-elevate if needed).
  Place: %USERPROFILE%\bin (on PATH). Launch via: winupdate
#>

[CmdletBinding()]
param(
    [switch]$SkipSoftware,
    [switch]$NoRebootPrompt,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Setup / logging
# ---------------------------------------------------------------------------
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath   = Join-Path $scriptDir "winupdate-$timestamp.log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info','Success','Warn','Error','Step','Cyan')]
        [string]$Level = 'Info'
    )
    $ts = Get-Date -Format 'HH:mm:ss'
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warn'    { 'Yellow' }
        'Error'   { 'Red' }
        'Step'    { 'Yellow' }
        'Cyan'    { 'Cyan' }
        default   { 'White' }
    }
    $line = "[$ts] $Message"
    Write-Host $line -ForegroundColor $color
    try { Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
Write-Host '=== winupdate ===' -ForegroundColor Cyan
Write-Log "Logging to: $logPath" 'Cyan'

# ---------------------------------------------------------------------------
# Elevation
# ---------------------------------------------------------------------------
Write-Log 'Step 1: Checking elevation...' 'Step'
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Wait-ForKeyToClose {
    # AFK-safe: window stays open until YOU press a key (no timeout).
    Write-Host ''
    Write-Host '================================================' -ForegroundColor Cyan
    Write-Host '  Done. Window will stay open (AFK-safe).' -ForegroundColor Yellow
    Write-Host '  Press any key to close this window...' -ForegroundColor Yellow
    Write-Host '================================================' -ForegroundColor Cyan
    try {
        if ($Host.Name -eq 'ConsoleHost') {
            try {
                while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
            } catch {}
            [void][Console]::ReadKey($true)
        } else {
            [void](Read-Host 'Press Enter to close')
        }
    } catch {
        try { [void](Read-Host 'Press Enter to close') } catch {
            Write-Host 'Could not read keyboard; sleeping 1 hour so output is not lost...' -ForegroundColor DarkYellow
            Start-Sleep -Seconds 3600
        }
    }
}

if (-not $isAdmin) {
    Write-Log 'Not elevated. Relaunching as Administrator...' 'Warn'
    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', "`"$PSCommandPath`""
    )
    if ($SkipSoftware)    { $argList += '-SkipSoftware' }
    if ($NoRebootPrompt)  { $argList += '-NoRebootPrompt' }
    if ($WhatIf)          { $argList += '-WhatIf' }

    try {
        $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -PassThru -Wait
        # Elevated window already waited for a key; do not double-prompt here.
        exit $(if ($null -ne $p) { $p.ExitCode } else { 1 })
    } catch {
        Write-Log "Elevation failed or was cancelled: $($_.Exception.Message)" 'Error'
        Write-Host 'Right-click PowerShell -> Run as administrator, then run: winupdate' -ForegroundColor Yellow
        Wait-ForKeyToClose
        exit 1
    }
}
Write-Log 'Running elevated.' 'Success'

# Any uncaught failure still leaves the window open for review
trap {
    Write-Host ''
    Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
    try { Write-Log ("FATAL: {0}" -f $_.Exception.Message) 'Error' } catch {}
    Wait-ForKeyToClose
    exit 1
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Test-RebootPending {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }
    try {
        $sess = [Activator]::CreateInstance([Type]::GetTypeFromCLSID([guid]'{9DA26DB0-9C38-4A6E-A32B-DC68F5398D87}'))
        if ($sess.IsBusy -or $sess.RebootRequired) { return $true }
    } catch {}
    return $false
}

function Get-YesNo {
    param([string]$Prompt, [string]$Default = 'N')
    while ($true) {
        $suffix = if ($Default -eq 'Y') { '[Y/n]' } else { '[y/N]' }
        Write-Host -NoNewline "$Prompt $suffix "
        $r = (Read-Host).Trim()
        if ([string]::IsNullOrWhiteSpace($r)) { $r = $Default }
        switch -Regex ($r) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default     { Write-Host 'Please answer Y or N.' -ForegroundColor Yellow }
        }
    }
}

function Format-SizeMB {
    param([double]$Bytes)
    if ($Bytes -le 0) { return 'n/a' }
    return ('{0:N1} MB' -f ($Bytes / 1MB))
}

# ---------------------------------------------------------------------------
# Windows Update via COM (no extra modules)
# ---------------------------------------------------------------------------
Write-Log 'Step 2: Searching for Windows Updates...' 'Step'

$installedSummary = New-Object System.Collections.Generic.List[object]
$failedSummary    = New-Object System.Collections.Generic.List[object]
$rebootFromWU     = $false

try {
    $session  = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'winupdate-cli'
    $searcher = $session.CreateUpdateSearcher()

    # Software + driver updates that are not installed and not hidden
    $criteria = "IsInstalled=0 and IsHidden=0"
    Write-Log "Search criteria: $criteria" 'Info'
    $result = $searcher.Search($criteria)
    $updates = $result.Updates

    Write-Log ("Found {0} Windows Update(s)." -f $updates.Count) 'Cyan'

    if ($updates.Count -eq 0) {
        Write-Log 'No Windows Updates available.' 'Success'
    } else {
        Write-Host ''
        Write-Host '--- Available Windows Updates ---' -ForegroundColor Cyan
        $i = 0
        foreach ($u in $updates) {
            $i++
            $size = 0
            try { $size = [double]$u.MaxDownloadSize } catch {}
            $title = $u.Title
            $kb = ''
            try {
                if ($u.KBArticleIDs -and $u.KBArticleIDs.Count -gt 0) {
                    $kb = 'KB' + ($u.KBArticleIDs -join ', KB')
                }
            } catch {}
            Write-Host ("  [{0}] {1}" -f $i, $title)
            if ($kb) { Write-Host ("       {0}  |  {1}" -f $kb, (Format-SizeMB $size)) -ForegroundColor DarkGray }
            else     { Write-Host ("       Size: {0}" -f (Format-SizeMB $size)) -ForegroundColor DarkGray }
        }
        Write-Host ''

        if ($WhatIf) {
            Write-Log 'WhatIf: skipping download/install of Windows Updates.' 'Warn'
        } else {
            Write-Log 'Step 3: Accepting EULAs and downloading ALL Windows Updates (auto-yes)...' 'Step'

            $toDownload = New-Object -ComObject Microsoft.Update.UpdateColl
            foreach ($u in $updates) {
                try {
                    if ($u.EulaAccepted -eq $false) {
                        $u.AcceptEula() | Out-Null
                    }
                } catch {
                    Write-Log ("Could not accept EULA for: {0} ({1})" -f $u.Title, $_.Exception.Message) 'Warn'
                }
                if (-not $u.IsDownloaded) {
                    [void]$toDownload.Add($u)
                }
            }

            if ($toDownload.Count -gt 0) {
                $downloader = $session.CreateUpdateDownloader()
                $downloader.Updates = $toDownload
                Write-Log ("Downloading {0} update(s)..." -f $toDownload.Count) 'Info'
                $dlResult = $downloader.Download()
                Write-Log ("Download result code: {0}" -f $dlResult.ResultCode) 'Info'
            } else {
                Write-Log 'All selected updates already downloaded.' 'Info'
            }

            Write-Log 'Step 4: Installing Windows Updates...' 'Step'
            $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
            foreach ($u in $updates) {
                if ($u.IsDownloaded) {
                    [void]$toInstall.Add($u)
                } else {
                    Write-Log ("Skipping (not downloaded): {0}" -f $u.Title) 'Warn'
                    $failedSummary.Add([pscustomobject]@{ Title = $u.Title; Reason = 'Not downloaded' })
                }
            }

            if ($toInstall.Count -eq 0) {
                Write-Log 'Nothing to install after download phase.' 'Warn'
            } else {
                $installer = $session.CreateUpdateInstaller()
                $installer.Updates = $toInstall
                # Allow install while users are logged on
                try { $installer.AllowSourcePrompts = $false } catch {}
                try { $installer.ForceQuiet = $true } catch {}

                $installResult = $installer.Install()
                $rebootFromWU = [bool]$installResult.RebootRequired
                Write-Log ("Install overall result code: {0}" -f $installResult.ResultCode) 'Info'
                Write-Log ("Reboot required (WU API): {0}" -f $rebootFromWU) 'Info'

                for ($j = 0; $j -lt $toInstall.Count; $j++) {
                    $u = $toInstall.Item($j)
                    $ur = $installResult.GetUpdateResult($j)
                    $code = $ur.ResultCode
                    # ResultCode: 0=NotStarted 1=InProgress 2=Succeeded 3=SucceededWithErrors 4=Failed 5=Aborted
                    $codeName = switch ($code) {
                        2 { 'Succeeded' }
                        3 { 'SucceededWithErrors' }
                        4 { 'Failed' }
                        5 { 'Aborted' }
                        default { "Code$code" }
                    }
                    if ($code -eq 2 -or $code -eq 3) {
                        $installedSummary.Add([pscustomobject]@{ Title = $u.Title; Result = $codeName })
                        Write-Log ("INSTALLED: {0} [{1}]" -f $u.Title, $codeName) 'Success'
                    } else {
                        $hresult = ''
                        try { $hresult = ('0x{0:X8}' -f ($ur.HResult -band 0xFFFFFFFF)) } catch {}
                        $failedSummary.Add([pscustomobject]@{ Title = $u.Title; Reason = "$codeName $hresult" })
                        Write-Log ("FAILED: {0} [{1} {2}]" -f $u.Title, $codeName, $hresult) 'Error'
                    }
                }
            }
        }
    }
} catch {
    Write-Log ("Windows Update COM error: {0}" -f $_.Exception.Message) 'Error'
    Write-Log 'Tip: Ensure Windows Update service (wuauserv) is running and you are online.' 'Warn'
}

# ---------------------------------------------------------------------------
# Summary: Windows Updates
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '========== WINDOWS UPDATE SUMMARY ==========' -ForegroundColor Cyan
if ($installedSummary.Count -gt 0) {
    Write-Host 'Installed / applied:' -ForegroundColor Green
    foreach ($item in $installedSummary) {
        Write-Host ("  + {0}  ({1})" -f $item.Title, $item.Result)
    }
} else {
    Write-Host 'No Windows Updates were installed this run.' -ForegroundColor DarkGray
}
if ($failedSummary.Count -gt 0) {
    Write-Host 'Failed / skipped:' -ForegroundColor Red
    foreach ($item in $failedSummary) {
        Write-Host ("  - {0}  ({1})" -f $item.Title, $item.Reason)
    }
}
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------------------
# Software updates via winget
# ---------------------------------------------------------------------------
if ($SkipSoftware) {
    Write-Log 'Skipping software updates (-SkipSoftware).' 'Warn'
} else {
    Write-Log 'Step 5: Checking software updates (winget)...' 'Step'
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Log 'winget.exe not found. Skipping software updates.' 'Warn'
        Write-Log 'Install App Installer from Microsoft Store to enable winget.' 'Info'
    } else {
        Write-Log ("winget: {0}" -f $winget.Source) 'Info'

        # Refresh sources quietly
        try {
            & winget.exe source update --disable-interactivity 2>&1 | Out-Null
        } catch {}

        $upgradeRaw = ''
        try {
            $upgradeRaw = & winget.exe upgrade --include-unknown --disable-interactivity 2>&1 | Out-String
        } catch {
            Write-Log ("winget upgrade list failed: {0}" -f $_.Exception.Message) 'Error'
        }

        if ($upgradeRaw) {
            Write-Host ''
            Write-Host '--- Software updates available (winget) ---' -ForegroundColor Cyan
            Write-Host $upgradeRaw
            try { Add-Content -Path $logPath -Value $upgradeRaw } catch {}
        }

        # Detect if there is anything actionable
        $hasUpgrades = $false
        if ($upgradeRaw -match 'Available' -or $upgradeRaw -match '\d+\s+upgrades?\s+available') {
            $hasUpgrades = $true
        }
        # winget sometimes prints a table with package ids even without that phrase
        if (-not $hasUpgrades -and $upgradeRaw -match '(?m)^[A-Za-z0-9._-]+\s+\S+\s+\S+\s+\S+') {
            # crude: lines that look like package rows
            if ($upgradeRaw -notmatch 'No installed package found' -and $upgradeRaw -notmatch 'No newer package versions') {
                $hasUpgrades = $true
            }
        }
        if ($upgradeRaw -match 'No installed package found matching input criteria' -or
            $upgradeRaw -match 'No newer package versions are available') {
            $hasUpgrades = $false
        }

        if (-not $hasUpgrades) {
            Write-Log 'No software (winget) upgrades detected.' 'Success'
        } else {
            if ($WhatIf) {
                Write-Log 'WhatIf: would prompt to install software upgrades.' 'Warn'
            } else {
                $doSoft = Get-YesNo -Prompt 'Install ALL listed software updates via winget?' -Default 'N'
                if ($doSoft) {
                    Write-Log 'Installing software upgrades with winget (accept agreements)...' 'Step'
                    # Prefer force + disable-interactivity (avoid --silent per skill notes)
                    $wgArgs = @(
                        'upgrade', '--all',
                        '--include-unknown',
                        '--accept-package-agreements',
                        '--accept-source-agreements',
                        '--disable-interactivity',
                        '--force'
                    )
                    Write-Log ("Running: winget {0}" -f ($wgArgs -join ' ')) 'Info'
                    $wgExit = 0
                    try {
                        & winget.exe @wgArgs 2>&1 | ForEach-Object {
                            $line = "$_"
                            Write-Host $line
                            try { Add-Content -Path $logPath -Value $line } catch {}
                        }
                        $wgExit = $LASTEXITCODE
                    } catch {
                        Write-Log ("winget failed: {0}" -f $_.Exception.Message) 'Error'
                        $wgExit = 1
                    }
                    if ($wgExit -eq 0) {
                        Write-Log 'winget upgrade completed successfully.' 'Success'
                    } else {
                        Write-Log ("winget exited with code {0}. Some packages may have failed (common for store-pinned or in-use apps)." -f $wgExit) 'Warn'
                    }
                } else {
                    Write-Log 'Software updates skipped by user.' 'Warn'
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Reboot check
# ---------------------------------------------------------------------------
Write-Log 'Step 6: Checking if reboot is required...' 'Step'
$rebootPending = $rebootFromWU -or (Test-RebootPending)

if ($rebootPending) {
    Write-Host ''
    Write-Host '*** REBOOT REQUIRED ***' -ForegroundColor Red
    Write-Log 'A restart is required to finish applying updates.' 'Warn'

    if ($NoRebootPrompt -or $WhatIf) {
        Write-Log 'Reboot prompt suppressed (-NoRebootPrompt / -WhatIf). Restart manually when ready.' 'Warn'
    } else {
        $doReboot = Get-YesNo -Prompt 'Reboot now?' -Default 'N'
        if ($doReboot) {
            Write-Log 'Rebooting in 15 seconds... (shutdown /r /t 15)' 'Warn'
            shutdown.exe /r /t 15 /c "winupdate: restart to finish Windows Updates"
        } else {
            Write-Log 'Reboot deferred. Restart when convenient.' 'Info'
        }
    }
} else {
    Write-Log 'No reboot required.' 'Success'
}

Write-Host ''
Write-Log 'Done.' 'Cyan'
Write-Host "Full log: $logPath" -ForegroundColor DarkGray
Write-Host ''

# Always wait — no auto-close, no timeout (safe if you walk away / AFK)
Wait-ForKeyToClose
exit 0
