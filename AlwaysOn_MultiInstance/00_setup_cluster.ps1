[CmdletBinding()]
param (
    [string]$DomainName = 'COMPANY',
    [string]$DomainController = 'DOM1',
    [string[]]$ClusterNodes = @('SRV1', 'SRV2'),
    [string]$ClusterName = 'SQLCluster',
    [string]$ClusterIP = '192.168.3.70'
)

function Write-LocalWarning {
    param (
        [string]$Message
    )
    Write-Warning -Message ('{0}: {1}' -f (Get-Date), $Message)
}

function Write-LocalHost {
    param (
        [string]$Message,
        [string]$ForegroundColor = 'Yellow'
    )
    Microsoft.PowerShell.Utility\Write-Host -Object ('{0}: {1}' -f (Get-Date), $Message) -ForegroundColor $ForegroundColor
}

function Write-LocalVerbose {
    param (
        [string]$Message
    )
    Write-Verbose -Message ('{0}: {1}' -f (Get-Date), $Message)
}

$ErrorActionPreference = 'Stop'

Write-LocalHost -Message 'Install cluster freature on each node'
Invoke-Command -ComputerName $ClusterNodes -ScriptBlock { Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools } | Format-Table

Write-LocalHost -Message 'Run cluster test and display result in web browser'
$clusterTest = Test-Cluster -Node $ClusterNodes
&$clusterTest.FullName

Write-LocalHost -Message 'Create the cluster'
$cluster = New-Cluster -Name $ClusterName -Node $ClusterNodes -StaticAddress $ClusterIP

Write-LocalHost -Message 'Create a share as cluster quorum and configure the cluster'
Invoke-Command -ComputerName $DomainController -ScriptBlock { 
    $null = New-Item -Path "C:\WindowsClusterQuorum_$using:ClusterName" -ItemType Directory
    $null = New-SmbShare -Path "C:\WindowsClusterQuorum_$using:ClusterName" -Name "WindowsClusterQuorum_$using:ClusterName"
    $null = Grant-SmbShareAccess -Name "WindowsClusterQuorum_$using:ClusterName" -AccountName "$using:DomainName\$using:ClusterName$" -AccessRight Full -Force
}
$cluster | Set-ClusterQuorum -NodeAndFileShareMajority "\\$DomainController\WindowsClusterQuorum_$ClusterName" | Format-List

Write-LocalHost -Message 'finished'
