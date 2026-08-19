#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
  Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber
}
Import-Module PSWindowsUpdate -Force
Write-Host "OK: PSWindowsUpdate ready"
