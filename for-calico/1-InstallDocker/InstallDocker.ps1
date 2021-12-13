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
Set-Location .\1-InstallDocker

try {
  Write-Host 'Try to enable container feature.' 
  New-Item -ItemType Directory c:\offline -Force|Out-Null
  Dism /Mount-Image /ImageFile:.\install.wim /Index:1 /MountDir:c:\offline /ReadOnly
  
  Enable-WindowsOptionalFeature -Online -FeatureName "Containers" -All -Source "c:\offline" -LimitAccess -NoRestart
  
  Dism /Unmount-Image /MountDir:C:\offline /Discard
  Write-Host 'Enable container feature successfully!!!' -ForegroundColor Green
}
catch {
  Write-Host 'Failed to enable container feature!!! Please contact the admin to troubleshoot.' -ForegroundColor Red
  exit 1
}

try {
  Write-Host 'Start to install docker'
  Expand-Archive -Path .\docker-20-10-7.zip -DestinationPath "C:\Program Files" -Force
  Write-Host 'Add docker to Environment variable.'
  $env:Path += ";C:\Program Files\docker"
  [Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)
  Write-Host 'Register service for docker.'
  & 'C:\Program Files\docker\dockerd.exe' --register-service
  Write-Host 'Docker install finshed!' -ForegroundColor Green
  $CniConf = @"
{
  "insecure-registries" : ["0.0.0.0/0"],
  "allow-nondistributable-artifacts" : ["0.0.0.0/0"]
}
"@
  New-Item -ItemType Directory "C:\ProgramData\Docker\config" -Force|Out-Null
  $CniConf | Out-File "C:\ProgramData\Docker\config\daemon.json" -Encoding Ascii -Force
  #start-service -name docker
}
catch {
  Write-Host 'Failed to install docker!!! Please contact the admin to troubleshoot.' -ForegroundColor Red
  exit 1
}


#Create startup script to continue install
$trigger = New-JobTrigger -AtStartup -RandomDelay 30
$Step2Script = $(Split-Path $(Get-Location) -Parent)+"\2-PrepareK8sNode\PrepareK8sNode.ps1"
$Step2 = "Start-Process powershell -ArgumentList $Step2Script -RedirectStandardOutput C:\k\log\K8sInstall.log -RedirectStandardError C:\k\log\K8sInstall.err"
$Step2 = [Scriptblock]::Create($Step2)
Register-ScheduledJob -Trigger $trigger -ScriptBlock $Step2 -Name InstallK8s

$KubernetesPath = "$env:SystemDrive\k"
$LogDir="C:\k\log"
New-Item -Type Directory -p $KubernetesPath -Force|Out-Null
New-Item -Type Directory -p $LogDir -Force|Out-Null

Write-Host "#####After reboot#####`n#####Continue to 2-PrepareK8sNode#####`n" -ForegroundColor Yellow
start-sleep 6

Restart-Computer -Force 