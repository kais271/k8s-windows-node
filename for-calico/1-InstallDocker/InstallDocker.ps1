<#
.SYNOPSIS
Use to install docker.

.DESCRIPTION
This script use to install docker for Windows Server.
- Mount the install.wim to enable container feature.
- Expand the docker zip to install docker.

.EXAMPLE
PS> .\InstallDocker.ps1
#>

function Pause(){
  [System.Console]::Write('Press any key to restart...')
  [void][System.Console]::ReadKey(1)
}

try {
  Write-Host 'Try to enable container feature.' 
  mkdir c:\offline
  Dism /Mount-Image /ImageFile:.\install.wim /Index:1 /MountDir:c:\offline /ReadOnly
  
  Enable-WindowsOptionalFeature -Online -FeatureName "Containers" -All -Source "c:\offline" -LimitAccess -NoRestart
  
  Dism /Unmount-Image /MountDir:C:\offline /Discard
  Write-Host 'Enable container feature successfully!!!' -ForegroundColor Green
}
catch {
  Write-Host 'Failed to enable container feature!!! Please contact the admin to troubleshoot.' -ForegroundColor Red
}

try {
  Write-Host 'Start to install docker'
  Expand-Archive -Path .\docker-20-10-7.zip -DestinationPath "C:\Program Files" -Force
  Write-Host 'Add docker to Environment variable.'
  $env:Path += ";C:\Program Files\docker"
  [Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)
  Write-Host 'Register service for docker.'
  & 'C:\Program Files\docker\dockerd.exe' --register-service
  Write-Host 'Install finshed!' -ForegroundColor Green
  $CniConf = @"
{
  "insecure-registries": [
    "0.0.0.0/0"
  ]
}
"@
  mkdir "C:\ProgramData\Docker\config" -Force
  $CniConf | Out-File "C:\ProgramData\Docker\config\daemon.json" -Encoding Ascii -Force
  #start-service -name docker
}
catch {
  Write-Host 'Failed to install docker!!! Please contact the admin to troubleshoot.' -ForegroundColor Red
}

New-Item -ItemType Directory c:\k -Force|Out-Null
pause

Restart-Computer -Force 
