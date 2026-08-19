#Requires -RunAsAdministrator
param(
  [Parameter(Mandatory=$true)][string]$CustomerCode,
  [string]$ScriptPath = (Join-Path $PSScriptRoot 'Invoke-AAIWindowsPatch.ps1'),
  [string]$Time = '22:00',
  [ValidateSet('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday')][string]$DayOfWeek = 'Tuesday'
)
$taskName = "AAI-WindowsPatch-$CustomerCode"
$arg = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -CustomerCode $CustomerCode -Reboot Prefer"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$trig = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time
$prin = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trig -Principal $prin -Force | Out-Null
Write-Host "Registered $taskName"
