<#
.SYNOPSIS
Use to install k8s windows node.

.DESCRIPTION
This script use to install docker for Windows Server.
- Mount the install.wim to enable container feature.
- Expand the docker zip to install docker.

.EXAMPLE
PS> .\Install.ps1 -LinuxMasterIp 192.168.85.57 -MasterUser root -MasterPasswd Passwd01! -K8sVersion '1.21.6' [-MasterSSHPort 22] [-Interface="Ethernet0]
#>

Param(
    [parameter(Mandatory = $true)] [string] $LinuxMasterIp,
    [parameter(Mandatory = $true)] [string] $MasterUser="root",
    [parameter(Mandatory = $true)] [string] $MasterPasswd,
    [parameter(Mandatory = $false)] [string] $MasterSSHPort="22",
    [parameter(Mandatory = $false)] $Interface="Ethernet0",
    [parameter(Mandatory = $true)] [ValidateSet("1.21.4", "1.21.6", "1.22.2" ,IgnoreCase = $false)] [string] $K8sVersion
)


#Install ssh module
Copy-Item -Recurse -Path .\0-Prerequisite\PackageManagement\ -Destination 'C:\Program Files\' -Force -ErrorAction SilentlyContinue
$LocalPSRepository=$(Get-Location).Path+"\0-Prerequisite\"
Register-PSRepository -Name tmp -SourceLocation $LocalPSRepository -InstallationPolicy Trusted -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
Install-Module -Name Posh-SSH -Repository tmp


function Pre-Check {
<#
Pre-check
1.Test network connectivity to master
2.Test user and password
#>
    try {
        if ((Test-NetConnection $LinuxMasterIp -Port $MasterSSHPort).TcpTestSucceeded) {
            Write-Host "1.To master ssh port is ok." -ForegroundColor Green
            if (Get-Module -Name Posh-SSH -ListAvailable) {
                $SshPassword = ConvertTo-SecureString $MasterPasswd -AsPlainText -Force
                $SshCred = New-Object System.Management.Automation.PSCredential ($MasterUser, $SshPassword)
                $SSHSession = New-SSHSession -ComputerName $LinuxMasterIp -Credential $SshCred -Port $MasterSSHPort -AcceptKey -ErrorAction SilentlyContinue
                if ($SSHSession.Connected) {
                    Write-Host "2.Can connect to master, the login info is ok." -ForegroundColor Green
                    Remove-SSHSession -SessionId $SSHSession.SessionId
                    return $True
                }
                else {
                    Write-Host "2.The user or password is incorrect." -ForegroundColor Red
                }
            }
            else {
                Write-Host "SSH module install failed. Exit (1)" -ForegroundColor Red
                exit 1
            }
        }
        else {
            Write-Host "Please contact administrator to diagnose." -BackgroundColor Black -ForegroundColor Red
            exit 1
        }
    }
    catch {
        Write-Host $_.Exception.Message`n -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n#####0-Start to Pre-check#####`n" -ForegroundColor Yellow
$res = Pre-Check

New-Item -ItemType Directory "$env:SystemDrive\k" -Force|Out-Null

#Get k8s informations
if ($res) {
    $SshPassword = ConvertTo-SecureString $MasterPasswd -AsPlainText -Force
    $SshCred = New-Object System.Management.Automation.PSCredential ($MasterUser, $SshPassword)
    $SFTPSession = New-SFTPSession -ComputerName $LinuxMasterIp -Credential $SshCred -Port $MasterSSHPort -AcceptKey
    #Get k8s config
    Get-SFTPItem -SessionId $SFTPSession.SessionId -Path /etc/kubernetes/admin.conf -Destination c:\k\ -Force
    Rename-Item -Path c:\k\admin.conf -NewName config -Force
    if (Test-Path c:\k\config) {
        Write-Host "3.Get k8s config success." -ForegroundColor Green
    }
    else {
        Write-Host "3.Get k8s config failed." -ForegroundColor Red
    }
    Remove-SFTPSession -SessionId $SFTPSession.SessionId|Out-Null
    #Get platform registry
    $SSHSession = New-SSHSession -ComputerName $LinuxMasterIp -Credential $SshCred -Port $MasterSSHPort -AcceptKey -ErrorAction SilentlyContinue
    $Registry = Invoke-SSHCommand -SSHSession $SSHSession -Command "kubectl  get ars -n cpaas-system   init -o jsonpath='{.spec.values.global.registry.address}'"
    $Registry = ($Registry.Output)[0]
    if ($Registry) {
        Write-Host "4.Get platform registry: $Registry" -ForegroundColor Green
        (Get-Content -Path .\2-PrepareK8sNode\PrepareK8sNode.ps1) -replace "{{VAR_REGISTRY}}", "$Registry" |Set-Content .\2-PrepareK8sNode\PrepareK8sNode.ps1
    }
    else {
        Write-Host "4.Get platform registry failed." -ForegroundColor Red
    }
    #Get ServiceCIDR
    $ServiceCIDR = Invoke-SSHCommand -SSHSession $SSHSession -Command "kubectl  --namespace kube-system get configmap kubeadm-config -o yaml|grep serviceSubnet|awk '{print $2}'"
    $ServiceCIDR = $ServiceCIDR.Output[0].Split(': ')[-1]
    if ($ServiceCIDR) {
        Write-Host "5.Get serviceCIDR: $ServiceCIDR" -ForegroundColor Green
        (Get-Content -Path .\2-PrepareK8sNode\PrepareK8sNode.ps1) -replace "{{VAR_SERVICECIDR}}", $ServiceCIDR |Set-Content .\2-PrepareK8sNode\PrepareK8sNode.ps1
    }
    else {
        Write-Host "5.Get serviceCIDR failed." -ForegroundColor Red
    }
    $JoinCommand = Invoke-SSHCommand -SSHSession $SSHSession -Command "kubeadm token create --print-join-command"
    $JoinCommand = ($JoinCommand.Output)[0]
    if ($JoinCommand) {
        Write-Host "6.Get JoinCommand success." -ForegroundColor Green
        (Get-Content -Path .\2-PrepareK8sNode\PrepareK8sNode.ps1) -replace "{{VAR_JOINCOMMAND}}", $JoinCommand |Set-Content .\2-PrepareK8sNode\PrepareK8sNode.ps1
    }
    else {
        Write-Host "6.Get JoinCommand failed." -ForegroundColor Red
    } 
    (Get-Content -Path .\2-PrepareK8sNode\PrepareK8sNode.ps1) -replace "{{VAR_INTERFACE}}", "$Interface" |Set-Content .\2-PrepareK8sNode\PrepareK8sNode.ps1
    (Get-Content -Path .\2-PrepareK8sNode\PrepareK8sNode.ps1) -replace "{{VAR_LOCATION}}", $((Get-Location).Path+"\2-PrepareK8sNode") |Set-Content .\2-PrepareK8sNode\PrepareK8sNode.ps1
    (Get-Content -Path .\2-PrepareK8sNode\PrepareK8sNode.ps1) -replace "{{VAR_MASTERPASSWD}}", "$MasterPasswd" |Set-Content .\2-PrepareK8sNode\PrepareK8sNode.ps1
    (Get-Content -Path .\2-PrepareK8sNode\PrepareK8sNode.ps1) -replace "{{VAR_MASTERUSER}}", "$MasterUser" |Set-Content .\2-PrepareK8sNode\PrepareK8sNode.ps1
    (Get-Content -Path .\2-PrepareK8sNode\PrepareK8sNode.ps1) -replace "{{VAR_LINUXMASTERIP}}", "$LinuxMasterIp" |Set-Content .\2-PrepareK8sNode\PrepareK8sNode.ps1
    (Get-Content -Path .\2-PrepareK8sNode\PrepareK8sNode.ps1) -replace "{{VAR_MASTERSSHPORT}}", "$MasterSSHPort" |Set-Content .\2-PrepareK8sNode\PrepareK8sNode.ps1
    (Get-Content -Path .\2-PrepareK8sNode\PrepareK8sNode.ps1) -replace "{{VAR_K8SVERSION}}", "$K8sVersion" |Set-Content .\2-PrepareK8sNode\PrepareK8sNode.ps1
    (Get-Content -Path .\2-PrepareK8sNode\PrepareK8sNode.ps1) -replace "{{VAR_RESULT}}", "$home\desktop\" |Set-Content .\2-PrepareK8sNode\PrepareK8sNode.ps1
}

Write-Host "`n#####1-InstallDocker#####`nStart the docker installation script.`n" -ForegroundColor Yellow
powershell .\1-InstallDocker\InstallDocker.ps1