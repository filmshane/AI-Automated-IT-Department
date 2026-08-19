#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Register weekly unattended winupdate task (AutomationAI).
#>
param(
    [Parameter(Mandatory = $true)][string]$CustomerCode,
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'Invoke-AAIWinUpdateUnattended.ps1'),
    [string]$Time = '22:00',
    [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
    [string]$DayOfWeek = 'Tuesday',
    [ValidateSet('Never', 'Prefer', 'Force')]
    [string]$Reboot = 'Never',
    [switch]$InstallSoftware
)

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Script not found: $ScriptPath"
}

$taskName = "AAI-WinUpdate-$CustomerCode"
$soft = if ($InstallSoftware) { '-InstallSoftware' } else { '' }
$arg = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -CustomerCode $CustomerCode -Reboot $Reboot $soft"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg.Trim()
$trig = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time
$prin = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trig -Principal $prin -Settings $settings -Force | Out-Null
Write-Host "Registered scheduled task: $taskName"
Write-Host "  Script: $ScriptPath"
Write-Host "  When:   $DayOfWeek $Time"
Write-Host "  Reboot: $Reboot"
Write-Host "Evidence: C:\ProgramData\AutomationAI\reports\"
