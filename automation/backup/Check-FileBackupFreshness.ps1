param([Parameter(Mandatory=$true)][string]$Path,[int]$MaxAgeHours=26,[string]$CustomerCode='lab')
$ErrorActionPreference='Stop'
if (-not (Test-Path $Path)) { Write-Error "Path missing: $Path"; exit 2 }
$newest = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $newest) { Write-Error "No files under $Path"; exit 3 }
$age = (Get-Date) - $newest.LastWriteTime
$result = [pscustomobject]@{Customer=$CustomerCode;Path=$Path;NewestFile=$newest.FullName;LastWrite=$newest.LastWriteTime;AgeHours=[math]::Round($age.TotalHours,2);Status= if ($age.TotalHours -le $MaxAgeHours) {'OK'} else {'STALE'}}
$result | Format-List
if ($result.Status -ne 'OK') { exit 1 }
