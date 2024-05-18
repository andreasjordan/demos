[CmdletBinding()]
param (
    [string]$DomainName = 'ORDIX',
    [string]$DomainController = 'DC',
    [string[]]$ClusterNodes = @('SQL01', 'SQL02'),
    [string[]]$SqlInstances = @('SQL01', 'SQL02'),
    [string]$SQLServerServiceAccount = 'gMSA-SQLServer',
    [SecureString]$AdminPassword = (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force),
    [string]$SQLServerSourcesPath = '\\fs\Software\SQLServer\ISO',
    [string]$SQLServerPatchesPath = '\\fs\Software\SQLServer\CU',
    [string]$SampleDatabasesPath = '\\fs\SampleDatabases',
    [string]$DatabaseName = 'AdventureWorks'
)

$ErrorActionPreference = 'Stop'

Import-Module -Name PSFramework
Import-Module -Name dbatools

$PSDefaultParameterValues['*-Dba*:EnableException'] = $true
$PSDefaultParameterValues['*-Dba*:Confirm'] = $false

try {

$administratorCredential = [PSCredential]::new("$DomainName\Admin", $AdminPassword)
$sqlServerCredential = [PSCredential]::new("$DomainName\$SQLServerServiceAccount$", [SecureString]::new())

if ($null -eq (Get-ADServiceAccount -Filter "Name -eq '$SQLServerServiceAccount'") ) {
    throw "Service Account '$SQLServerServiceAccount' for SQL Server not found. Creation of this account is not part of this script but done in https://github.com/andreasjordan/demos/blob/master/AutomatedLab/CustomScripts/SQLServer_AlwaysOn.ps1"
}

Write-PSFMessage -Level Host -Message 'Change powerplan of cluster nodes to high performance'
Set-DbaPowerPlan -ComputerName $ClusterNodes | Format-Table

Write-PSFMessage -Level Host -Message 'Install SQL Server instances on cluster nodes'
$installParams = @{
    SqlInstance        = $SqlInstances
    Version            = 2022
    Feature            = 'Engine'
    Path               = $SQLServerSourcesPath
    UpdateSourcePath   = $SQLServerPatchesPath
    EngineCredential   = $sqlServerCredential
    AgentCredential    = $sqlServerCredential
    AuthenticationMode = 'Mixed'
    Credential         = $administratorCredential
    Restart            = $true
    EnableException    = $false
}
$installResult = @( )
$installResult += Install-DbaInstance @installParams
$installResult | Format-Table
if ($installResult.Count -lt $SqlInstances.Count -or $false -in $installResult.Successful) {
    throw "Install-DbaInstance not successful"
}

Write-PSFMessage -Level Host -Message 'Grant instant file initialization rights to SQL Server service account on cluster nodes'
Set-DbaPrivilege -ComputerName $ClusterNodes -Type IFI

Write-PSFMessage -Level Host -Message 'Add rule to firewall on cluster nodes'
New-DbaFirewallRule -SqlInstance $SqlInstances | Format-Table

Write-PSFMessage -Level Host -Message 'Configure SQL Server instances: MaxMemory / MaxDop / CostThresholdForParallelism'
Set-DbaMaxMemory -SqlInstance $SqlInstances -Max 2048 | Format-Table
Set-DbaMaxDop -SqlInstance $SqlInstances | Format-Table
Set-DbaSpConfigure -SqlInstance $SqlInstances -Name CostThresholdForParallelism -Value 50 | Format-Table

Write-PSFMessage -Level Host -Message 'Restore and configure demo database'
$null = Restore-DbaDatabase -SqlInstance $SqlInstances[0] -Path "$SampleDatabasesPath\AdventureWorks2017.bak" -DatabaseName $DatabaseName
$null = Set-DbaDbOwner -SqlInstance $SqlInstances[0] -Database $DatabaseName -TargetLogin sa
$null = Set-DbaDbRecoveryModel -SqlInstance $SqlInstances[0] -Database $DatabaseName -RecoveryModel Full
$null = Backup-DbaDatabase -SqlInstance $SqlInstances[0] -Database $DatabaseName

Write-PSFMessage -Level Host -Message 'finished'

} catch { Write-PSFMessage -Level Warning -Message 'failed' -ErrorRecord $_ }
