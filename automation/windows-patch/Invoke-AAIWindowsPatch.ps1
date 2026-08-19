#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true)][string]$CustomerCode,
  [ValidateSet('Never','Prefer','Force')][string]$Reboot = 'Prefer',
  [string]$ReportRoot = 'C:\ProgramData\AutomationAI\reports',
  [string]$LogRoot = 'C:\ProgramData\AutomationAI\logs',
  [switch]$MicrosoftUpdate,
  [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$ts = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$day = Get-Date -Format 'yyyy-MM-dd'
$hostName = $env:COMPUTERNAME
$runId = "$CustomerCode-$hostName-$day"
New-Item -ItemType Directory -Force -Path $ReportRoot, $LogRoot | Out-Null
$logFile = Join-Path $LogRoot "$runId-$ts.log"
$csvFile = Join-Path $ReportRoot "$runId-updates.csv"
$sumFile = Join-Path $ReportRoot "$runId-summary.txt"
function Write-Log([string]$msg) {
  $line = "{0} {1}" -f (Get-Date -Format o), $msg
  Add-Content -Path $logFile -Value $line
  Write-Host $line
}
try { Import-Module PSWindowsUpdate -ErrorAction Stop }
catch { Write-Log "ERROR: run Install-AAIPatchPrereqs.ps1 first"; throw }
Write-Log "START customer=$CustomerCode host=$hostName reboot=$Reboot whatif=$WhatIf"
if ($MicrosoftUpdate) { try { Add-WUServiceManager -MicrosoftUpdate -Confirm:$false | Out-Null } catch { Write-Log "WARN $_" } }
Write-Log "Scanning..."
$updates = @(Get-WindowsUpdate -MicrosoftUpdate:$MicrosoftUpdate -ErrorAction Stop)
$updates | Select-Object KB, Title, Size, Status | Export-Csv -NoTypeInformation -Path $csvFile -Encoding UTF8
Write-Log ("Found {0} update(s)" -f $updates.Count)
$pendingReboot = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
$failed = @()
if (-not $WhatIf -and $updates.Count -gt 0) {
  if ($PSCmdlet.ShouldProcess($hostName, 'Install Windows Updates')) {
    try {
      $null = Get-WindowsUpdate -MicrosoftUpdate:$MicrosoftUpdate -AcceptAll -Install -IgnoreReboot -ErrorAction Stop
      Write-Log "Install completed"
    } catch { Write-Log "ERROR $_"; $failed += $_.Exception.Message }
  }
} else { Write-Log "No install (WhatIf or empty)" }
$pendingReboot = $pendingReboot -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
$didReboot = $false
if ($pendingReboot -and ($Reboot -eq 'Force' -or $Reboot -eq 'Prefer')) { $didReboot = $true; Write-Log "Reboot scheduled in 60s" }
@"
=== AUTOMATIONAI WINDOWS PATCH SUMMARY ===
Customer: $CustomerCode
Hostname: $hostName
Date: $day
Updates listed: $($updates.Count)
Pending reboot: $pendingReboot
Reboot policy: $Reboot
Will reboot: $didReboot
CSV: $csvFile
Log: $logFile
RESULT: $(if ($failed.Count) {'REVIEW'} elseif ($WhatIf) {'WHATIF'} else {'OK_OR_REVIEW_CSV'})
"@ | Set-Content -Path $sumFile -Encoding UTF8
Get-Content $sumFile
if ($didReboot) { shutdown.exe /r /t 60 /c "AutomationAI approved patch reboot" }
