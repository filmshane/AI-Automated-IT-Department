#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Unattended Windows Update for AutomationAI vITD (based on millersh\bin\winupdate-main.ps1).

.DESCRIPTION
  Same COM Microsoft.Update.Session engine as winupdate-main.ps1 (no PSWindowsUpdate module).
  Designed for Scheduled Task / RMM / remote run:
  - No interactive prompts
  - No Wait-ForKey
  - Writes customer evidence pack under ProgramData
  - Optional winget (--SkipSoftware default for servers)

.PARAMETER CustomerCode
  Short client code for evidence naming

.PARAMETER SkipSoftware
  Skip winget (default $true for unattended servers)

.PARAMETER InstallSoftware
  If set, runs winget upgrade --all non-interactively

.PARAMETER Reboot
  Never | Prefer | Force

.PARAMETER WhatIf
  List updates only

.NOTES
  Interactive desktop use: prefer winupdate.cmd / winupdate-main.ps1 from this folder or %USERPROFILE%\bin
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CustomerCode,

    [bool]$SkipSoftware = $true,

    [switch]$InstallSoftware,

    [ValidateSet('Never', 'Prefer', 'Force')]
    [string]$Reboot = 'Never',

    [string]$EvidenceRoot = 'C:\ProgramData\AutomationAI\reports',

    [string]$LogRoot = 'C:\ProgramData\AutomationAI\logs',

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$day = Get-Date -Format 'yyyy-MM-dd'
$hostName = $env:COMPUTERNAME
$runId = "$CustomerCode-$hostName-$day"

New-Item -ItemType Directory -Force -Path $EvidenceRoot, $LogRoot | Out-Null
$logPath = Join-Path $LogRoot "winupdate-$runId-$ts.log"
$csvPath = Join-Path $EvidenceRoot "$runId-wu-updates.csv"
$sumPath = Join-Path $EvidenceRoot "$runId-wu-summary.txt"

function Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue
    Write-Host $line
}

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

Write-Log "START customer=$CustomerCode host=$hostName reboot=$Reboot whatif=$WhatIf"

$installedSummary = New-Object System.Collections.Generic.List[object]
$failedSummary = New-Object System.Collections.Generic.List[object]
$listed = New-Object System.Collections.Generic.List[object]
$rebootFromWU = $false

try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'automationai-winupdate'
    $searcher = $session.CreateUpdateSearcher()
    $criteria = 'IsInstalled=0 and IsHidden=0'
    Write-Log "Search criteria: $criteria"
    $result = $searcher.Search($criteria)
    $updates = $result.Updates
    Write-Log ("Found {0} Windows Update(s)." -f $updates.Count)

    for ($i = 0; $i -lt $updates.Count; $i++) {
        $u = $updates.Item($i)
        $size = 0
        try { $size = [double]$u.MaxDownloadSize } catch {}
        $kb = ''
        try {
            if ($u.KBArticleIDs -and $u.KBArticleIDs.Count -gt 0) {
                $kb = 'KB' + ($u.KBArticleIDs -join ',KB')
            }
        } catch {}
        $listed.Add([pscustomobject]@{
                Index = $i + 1
                Title = $u.Title
                KB    = $kb
                Size  = $size
            }) | Out-Null
    }

    $listed | Export-Csv -NoTypeInformation -Path $csvPath -Encoding UTF8
    Write-Log "CSV evidence: $csvPath"

    if ($updates.Count -eq 0) {
        Write-Log 'No Windows Updates available.' 'Success'
    }
    elseif ($WhatIf) {
        Write-Log 'WhatIf: skipping download/install.' 'Warn'
    }
    else {
        Write-Log 'Accepting EULAs and downloading...'
        $toDownload = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $updates) {
            try {
                if ($u.EulaAccepted -eq $false) { $u.AcceptEula() | Out-Null }
            } catch {
                Write-Log ("EULA warn: {0}" -f $u.Title) 'Warn'
            }
            if (-not $u.IsDownloaded) { [void]$toDownload.Add($u) }
        }
        if ($toDownload.Count -gt 0) {
            $downloader = $session.CreateUpdateDownloader()
            $downloader.Updates = $toDownload
            $dlResult = $downloader.Download()
            Write-Log ("Download result code: {0}" -f $dlResult.ResultCode)
        }

        Write-Log 'Installing...'
        $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $updates) {
            if ($u.IsDownloaded) {
                [void]$toInstall.Add($u)
            }
            else {
                $failedSummary.Add([pscustomobject]@{ Title = $u.Title; Reason = 'Not downloaded' })
            }
        }
        if ($toInstall.Count -gt 0) {
            $installer = $session.CreateUpdateInstaller()
            $installer.Updates = $toInstall
            try { $installer.AllowSourcePrompts = $false } catch {}
            try { $installer.ForceQuiet = $true } catch {}
            $installResult = $installer.Install()
            $rebootFromWU = [bool]$installResult.RebootRequired
            Write-Log ("Install result code: {0}; RebootRequired={1}" -f $installResult.ResultCode, $rebootFromWU)

            for ($j = 0; $j -lt $toInstall.Count; $j++) {
                $u = $toInstall.Item($j)
                $ur = $installResult.GetUpdateResult($j)
                $code = $ur.ResultCode
                $codeName = switch ($code) {
                    2 { 'Succeeded' }
                    3 { 'SucceededWithErrors' }
                    4 { 'Failed' }
                    5 { 'Aborted' }
                    default { "Code$code" }
                }
                if ($code -eq 2 -or $code -eq 3) {
                    $installedSummary.Add([pscustomobject]@{ Title = $u.Title; Result = $codeName })
                    Write-Log ("INSTALLED: {0}" -f $u.Title) 'Success'
                }
                else {
                    $hresult = ''
                    try { $hresult = ('0x{0:X8}' -f ($ur.HResult -band 0xFFFFFFFF)) } catch {}
                    $failedSummary.Add([pscustomobject]@{ Title = $u.Title; Reason = "$codeName $hresult" })
                    Write-Log ("FAILED: {0} [{1}]" -f $u.Title, $hresult) 'Error'
                }
            }
        }
    }
}
catch {
    Write-Log ("Windows Update COM error: {0}" -f $_.Exception.Message) 'Error'
}

# Optional winget
$wingetNote = 'skipped'
if ($InstallSoftware -or (-not $SkipSoftware)) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        $wingetNote = 'winget not found'
        Write-Log $wingetNote 'Warn'
    }
    elseif ($WhatIf) {
        $wingetNote = 'whatif-only'
    }
    else {
        Write-Log 'Running winget upgrade --all (non-interactive)...'
        try {
            & winget.exe upgrade --all --include-unknown --accept-package-agreements --accept-source-agreements --disable-interactivity --force 2>&1 |
                ForEach-Object { Write-Log "winget: $_" }
            $wingetNote = "exit=$LASTEXITCODE"
        }
        catch {
            $wingetNote = $_.Exception.Message
            Write-Log $wingetNote 'Error'
        }
    }
}

$rebootPending = $rebootFromWU -or (Test-RebootPending)
$willReboot = $false
if ($rebootPending -and -not $WhatIf) {
    if ($Reboot -eq 'Force' -or $Reboot -eq 'Prefer') {
        $willReboot = $true
        Write-Log 'Scheduling reboot in 60s' 'Warn'
    }
}

$summary = @"
=== AUTOMATIONAI WINDOWS UPDATE SUMMARY ===
Customer: $CustomerCode
Hostname: $hostName
Date: $day
Timestamp: $ts
Updates listed: $($listed.Count)
Installed: $($installedSummary.Count)
Failed/skipped: $($failedSummary.Count)
Reboot pending: $rebootPending
Reboot policy: $Reboot
Will reboot: $willReboot
Winget: $wingetNote
CSV: $csvPath
Log: $logPath
RESULT: $(if ($failedSummary.Count -gt 0) { 'REVIEW' } elseif ($WhatIf) { 'WHATIF' } elseif ($listed.Count -eq 0) { 'NO_UPDATES' } else { 'OK_OR_REVIEW' })
Engine: Microsoft.Update.Session COM (same as bin\winupdate-main.ps1)
"@
$summary | Set-Content -Path $sumPath -Encoding UTF8
Write-Log "Summary: $sumPath"
Write-Output $summary

if ($willReboot) {
    shutdown.exe /r /t 60 /c "AutomationAI winupdate: finish updates ($CustomerCode)"
}

exit $(if ($failedSummary.Count -gt 0) { 2 } else { 0 })
