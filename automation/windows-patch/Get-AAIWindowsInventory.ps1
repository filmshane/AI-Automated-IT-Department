param([string]$CustomerCode='lab',[string]$OutDir='C:\ProgramData\AutomationAI\reports')
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object { "{0}:{1:N1}GB free" -f $_.DeviceID, ($_.FreeSpace/1GB) }
[pscustomobject]@{
  Customer=$CustomerCode; Hostname=$env:COMPUTERNAME; OS=$os.Caption
  TotalMemoryGB=[math]::Round($cs.TotalPhysicalMemory/1GB,2); CPU=$cpu.Name
  Cores=$cpu.NumberOfLogicalProcessors; Disks=($disks -join '; '); LastBoot=$os.LastBootUpTime
} | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $OutDir "$CustomerCode-$env:COMPUTERNAME-inventory.csv")
Write-Output (Join-Path $OutDir "$CustomerCode-$env:COMPUTERNAME-inventory.csv")
