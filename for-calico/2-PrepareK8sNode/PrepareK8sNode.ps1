<#
.SYNOPSIS
Assists with preparing a Windows VM prior to calling kubeadm join

.DESCRIPTION
This script assists with joining a Windows node to a cluster.
- Downloads Kubernetes binaries (kubelet, kubeadm) at the version specified
- Registers kubelet as an nssm service. More info on nssm: https://nssm.cc/


.PARAMETER Registry
Registry that Kubernetes will use.

.PARAMETER ServiceCIDR
ServiceCIDR that Kubernetes used.

.PARAMETER Interface
Which interface used to calico.

.EXAMPLE
PS> .\PrepareNode.ps1 -Registry 192.168.85.155:60080 -ServiceCIDR '10.6.0.0/16'

#>

Param(
    [parameter(Mandatory = $false)] [string] $Registry="{{VAR_REGISTRY}}",
    [ValidateSet("bgp", "vxlan",IgnoreCase = $true)] $NetworkMode="vxlan",
    [parameter(Mandatory = $false)] $ServiceCIDR="{{VAR_SERVICECIDR}}",
    [parameter(Mandatory = $false)] $Interface="{{VAR_INTERFACE}}",
    [parameter(Mandatory = $false)] $LogDir="C:\k\log",
    [parameter(Mandatory = $false)] $Location="{{VAR_LOCATION}}"
)

Set-Location $Location

while (-not(Test-Path "//./pipe/docker_engine")) {
    Start-Sleep 3
    Write-Host 'Watting for docker service...'
}

Write-Host "ServiceCIDR=$ServiceCIDR"
$ip = $ServiceCIDR.split("/")[0].split("\.")
$KubeDNS = $ip[0] + "." + $ip[1] + "." + $ip[2] + ".10"
Write-Host "KubeDNS=$KubeDNS"
Write-Host "Registry=$Registry"

$ContainerRuntime='Docker'

$ErrorActionPreference = 'Stop'


if ($ContainerRuntime -eq "Docker") {
    if (-not(Test-Path "//./pipe/docker_engine")) {
        Write-Error "Docker service was not detected - please install start Docker before calling PrepareNode.ps1 with -ContainerRuntime Docker"
        exit 1
    }
} elseif ($ContainerRuntime -eq "containerD") {
    if (-not(Test-Path "//./pipe/containerd-containerd")) {
        Write-Error "ContainerD service was not detected - please install and start containerD before calling PrepareNode.ps1 with -ContainerRuntime containerD"
        exit 1
    }
}


$global:Powershell = (Get-Command powershell).Source
$global:PowershellArgs = "-ExecutionPolicy Bypass -NoProfile"
$global:KubernetesPath = "$env:SystemDrive\k"
$global:StartKubeletScript = "$global:KubernetesPath\StartKubelet.ps1"
$global:NssmInstallDirectory = "$env:ProgramFiles\nssm"


<#
if (Test-Path $global:KubernetesPath) {
    Write-Host 'Directory check is ok.'
}
else {
    New-Item -Type Directory -Force "$global:KubernetesPath"|Out-Null
}
New-Item -Type Directory -p $LogDir -Force|Out-Null
#>
Write-Host 'Copy kubelet and kubeadm to /k.'
$K8sArchive = "kubernetes-node-windows-amd64-"+"{{VAR_K8SVERSION}}"+".zip"
Expand-Archive -Force -Path $K8sArchive -DestinationPath $global:KubernetesPath
<#
Copy-Item -Path ./kubelet.exe -Destination $kubeletBinPath -Force
Copy-Item -Path ./kubeadm.exe -Destination $global:KubernetesPath -Force
Copy-Item -Path ./kubectl.exe -Destination $global:KubernetesPath -Force 
Copy-Item -Path ./kube-proxy.exe -Destination $global:KubernetesPath -Force 
#>

$env:Path += ";$global:KubernetesPath"

[Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)

New-Item -Type Directory -Force C:\var\log\kubelet|Out-Null
New-Item -Type Directory -Force C:\var\lib\kubelet\etc\kubernetes|Out-Null
New-Item -Type Directory -Force C:\etc\kubernetes\pki|Out-Null
New-Item -Type File C:\etc\resolv.conf -Force|Out-Null
New-Item -path C:\var\lib\kubelet\etc\kubernetes\pki -type SymbolicLink -value C:\etc\kubernetes\pki -Force|Out-Null
New-Item -path C:\var\lib\kubelet\etc\resolv.conf -type SymbolicLink -value C:\etc\resolv.conf -Force|Out-Null

Write-Host 'Generate kubelet startup script.' -ForegroundColor Blue
$StartKubeletFileContent = '$FileContent = Get-Content -Path "/var/lib/kubelet/kubeadm-flags.env"
$global:KubeletArgs = $FileContent.TrimStart(''KUBELET_KUBEADM_ARGS='').Trim(''"'')

$global:containerRuntime = {{CONTAINER_RUNTIME}}

if ($global:containerRuntime -eq "Docker") {
    $netId = docker.exe network ls -f name=host --format "{{ .ID }}"

    if ($netId.Length -lt 1) {
    docker.exe network create -d nat host
    }
}

$cmd = "C:\k\kubelet.exe $global:KubeletArgs --cert-dir=$env:SYSTEMDRIVE/etc/kubernetes/pki --config=/var/lib/kubelet/config.yaml --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --hostname-override=$(hostname) --pod-infra-container-image=`"{{REGISTRY}}/oss/kubernetes/pause:3.6-windows-ltsc2022-amd64`" --enable-debugging-handlers --cgroups-per-qos=false --enforce-node-allocatable=`"`" --rotate-server-certificates --network-plugin=cni --cni-conf-dir=c:\k\cni\conf --cni-bin-dir=c:\k\cni --cluster-dns={{CLUSTER_DNS}} --resolv-conf=`"`" --log-dir=/var/log/kubelet --logtostderr=true"

Invoke-Expression $cmd'
$StartKubeletFileContent = $StartKubeletFileContent -replace "{{CONTAINER_RUNTIME}}", "`"$ContainerRuntime`""
$StartKubeletFileContent = $StartKubeletFileContent -replace "{{REGISTRY}}", "$Registry"
$StartKubeletFileContent = $StartKubeletFileContent -replace "{{CLUSTER_DNS}}", "$KubeDNS"

Set-Content -Path $global:StartKubeletScript -Value $StartKubeletFileContent

Write-Host "Installing nssm" -ForegroundColor Blue
$arch = "win32"
if ([Environment]::Is64BitOperatingSystem) {
    $arch = "win64"
}

New-Item -Type Directory -Force $global:NssmInstallDirectory|Out-Null

tar -C $global:NssmInstallDirectory -xf .\nssm-2.24.zip --strip-components 2 */$arch/*.exe|Out-Null


$env:path += ";$global:NssmInstallDirectory"

[Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)

Write-Host "Registering kubelet service"
nssm install kubelet $global:Powershell $global:PowershellArgs $global:StartKubeletScript
nssm set kubelet AppStdout $LogDir\kubelet.out.log
nssm set kubelet AppStderr $LogDir\kubelet.err.log
nssm set kubelet Start SERVICE_AUTO_START
nssm set kubelet ObjectName LocalSystem
nssm set kubelet Type SERVICE_WIN32_OWN_PROCESS

if ($ContainerRuntime -eq "Docker") {
    nssm set kubelet DependOnService docker
} 

#Disable firewall
#New-NetFirewallRule -Name kubelet -DisplayName 'kubelet' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 10250
Write-Host 'Dsiable system firewall for kubernetes.' -ForegroundColor Yellow
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

##########

$calico_baseDir = "c:\CalicoWindows"



# TODO: generate component kubeconfig instead of using admin config.
New-Item -Type Directory -p c:\k\cni -Force|Out-Null
New-Item -Type Directory -p c:\k\cni\conf -Force|Out-Null

$Hostname=$(hostname).ToLower()
$NetworkMode = $NetworkMode.ToLower()

Expand-Archive -Path .\calico-windows-v3.20.2.zip -DestinationPath "C:\" -Force

Set-Location c:\k

# generate Calico install config
$Conf = @" 
`$calico_baseDir = "`$PSScriptRoot"
ipmo `$calico_baseDir\libs\calico\calico.psm1

`$env:KUBE_NETWORK = "Calico.*"
`$env:CALICO_NETWORKING_BACKEND="vxlan"

`$env:K8S_SERVICE_CIDR = "$ServiceCIDR"
`$env:DNS_NAME_SERVERS = "$KubeDNS"
`$env:DNS_SEARCH = "svc.cluster.local"

`$env:CALICO_DATASTORE_TYPE = "kubernetes"

`$env:KUBECONFIG = "c:\k\config"

`$env:CNI_BIN_DIR = "c:\k\cni"
`$env:CNI_CONF_DIR = "c:\k\cni\conf"

`$env:CNI_CONF_FILENAME = "10-calico.conf"
`$env:CNI_IPAM_TYPE = "calico-ipam"

`$env:VXLAN_VNI = "4096"
`$env:VXLAN_MAC_PREFIX = "0E-2A"
`$env:VXLAN_ADAPTER = "$Interface"

`$env:NODENAME = "$Hostname"
`$env:CALICO_K8S_NODE_REF = `$env:NODENAME

`$env:STARTUP_VALID_IP_TIMEOUT = 90
`$env:IP = "autodetect"
`$env:IP_AUTODETECTION_METHOD = "interface=$Interface"

`$env:CALICO_LOG_DIR = "$LogDir"

# `$env:FELIX_LOGSEVERITYSCREEN = "info"
`$env:FELIX_LOGSEVERITYFILE = "none"
`$env:FELIX_LOGSEVERITYSYS = "none"
"@
Set-Content "C:\CalicoWindows\config.ps1" -Encoding Ascii -Force $Conf


# Install Calico Service
try {
    Test-Path C:\k\config -PathType Leaf
    C:\CalicoWindows\install-calico.ps1
}
catch {
    Write-Host 'Not found c:\k\config!!!' -ForegroundColor Red
    exit 1
}


# register kube-proxy
try {
    Write-Host 'Try to register kube-proxy service.'
    Unblock-File $calico_baseDir\kubernetes\kube-proxy-service.ps1
    nssm install kube-proxy $global:Powershell
    nssm set kube-proxy AppParameters $calico_baseDir\kubernetes\kube-proxy-service.ps1
    nssm set kube-proxy AppDirectory $calico_baseDir
    nssm set kube-proxy AppStdout $LogDir\kube-proxy.out.log
    nssm set kube-proxy AppStderr $LogDir\kube-proxy.err.log
    nssm set kube-proxy Start SERVICE_AUTO_START
    nssm set kube-proxy ObjectName LocalSystem
    nssm set kube-proxy Type SERVICE_WIN32_OWN_PROCESS
    nssm start kube-proxy
}
catch {
    Write-Host 'Failed to register kube-proxy.' -ForegroundColor Red
}

Write-Host "K8s node is ready to join cluster." -ForegroundColor Green

Write-Host "`n#####3-JoinCluster#####`n" -ForegroundColor Yellow
Set-Location c:\k
$Join = ".\"+"{{VAR_JOINCOMMAND}}"
Invoke-Expression $Join -WarningAction SilentlyContinue

Start-Sleep 2

Write-Host "`n#####4-AutoApproveCSR#####`n" -ForegroundColor Yellow
$SshPassword = ConvertTo-SecureString "{{VAR_MASTERPASSWD}}" -AsPlainText -Force
$SshCred = New-Object System.Management.Automation.PSCredential ("{{VAR_MASTERUSER}}", $SshPassword)
$SSHSession = New-SSHSession -ComputerName "{{VAR_LINUXMASTERIP}}" -Credential $SshCred -Port "{{VAR_MASTERSSHPORT}}" -AcceptKey -ErrorAction SilentlyContinue
$NodeName = HOSTNAME.EXE
$ApproveCmd = "kubectl get csr --no-headers|grep Pending|grep $NodeName|cut -d' ' -f1|xargs -n1 kubectl certificate approve"
$ApproveCSR = Invoke-SSHCommand -SSHSession $SSHSession -Command $ApproveCmd
$ApproveCSR = ($ApproveCSR.Output)[0]
if ($ApproveCSR -and $ApproveCSR -match 'approved') {
    Write-Host "Approve CSR success." -ForegroundColor Green
}
else {
    Write-Host "Approve CSR failed, please check." -ForegroundColor Red
    exit 1
}


[Environment]::SetEnvironmentVariable("Path", $env:Path, [System.EnvironmentVariableTarget]::Machine)
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")

Write-Host "`n#####Remove startup scripts, end the installation.#####"  -BackgroundColor Green -ForegroundColor Black

Out-File -FilePath ("{{VAR_RESULT}}"+"K8s-OK.txt") -InputObject "Details in C:\k\log\K8sInstall.log and C:\k\log\K8sInstall.err"

Unregister-ScheduledJob -Name InstallK8s