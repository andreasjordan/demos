[CmdletBinding()]
param (
    [string]$DomainName = 'COMPANY',
    [string]$DomainController = 'DOM1',
    [string]$NewClusterNode = 'SRV3',
    [string]$ClusterName = 'SQLCluster'
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

Write-LocalHost -Message 'Install cluster freature on new node'
$installResult = Invoke-Command -ComputerName $NewClusterNode -ScriptBlock { Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools }
$installResult | Format-Table
if ( $installResult.RestartNeeded -eq 'Yes' ) {
    # Restart is needed on Windows Server 2019
    Restart-Computer -ComputerName $NewClusterNode
    Start-Sleep -Seconds 60
}

Write-LocalHost -Message 'Install cluster freature on new node'
Get-Cluster -Name $ClusterName | Add-ClusterNode -Name $NewClusterNode
# This should output something, but it does not

Write-LocalHost -Message 'Lets see if we have a new node'
Get-Cluster -Name $ClusterName | Get-ClusterNode
# Yes, we have


# put code in here from: SRV3_MultiInstance\setup_instances.ps1


# plan:

# Add replica (delete database AdventureWorks befor that - or not?)
# Add databases (maybe they are added automatically with automatic seeding?


Write-LocalHost -Message 'finished'
