[CmdletBinding()]
param (
    [string]$DomainName = 'ORDIX',
    [string]$DomainController = 'DC',
    [string[]]$ClusterNodes = @('SQL01', 'SQL02'),
    [string[]]$SqlInstances = @('SQL01', 'SQL02'),
    [string]$NewClusterNode = 'SQL03',
    [string]$NewSqlInstance = 'SQL03',
    [string]$ClusterName = 'CLUSTER1',
    [string]$SQLServerServiceAccount = 'SQLServer',
    [SecureString]$AdminPassword = (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force),
    [SecureString]$SqlPassword = (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force),
    [string]$SQLServerSourcesPath = '\\fs\Software\SQLServer\ISO',
    [string]$SQLServerPatchesPath = '\\fs\Software\SQLServer\CU',
    [string]$AvailabilityGroupName = 'AdventureSQL',
    [string]$BackupPath = '\\fs\Backup'
)

$ErrorActionPreference = 'Stop'

Import-Module -Name PSFramework
Import-Module -Name dbatools

$PSDefaultParameterValues['*-Dba*:EnableException'] = $true
$PSDefaultParameterValues['*-Dba*:Confirm'] = $false

try {

Write-PSFMessage -Level Host -Message 'Install cluster feature on new node'
$installResult = Invoke-Command -ComputerName $NewClusterNode -ScriptBlock { Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools }
$installResult | Format-Table
if ( $installResult.RestartNeeded -eq 'Yes' ) {
    # Restart is needed on Windows Server 2019
    Restart-Computer -ComputerName $NewClusterNode
    Start-Sleep -Seconds 60
}

Write-PSFMessage -Level Host -Message 'Add new node to cluster'
Get-Cluster -Name $ClusterName | Add-ClusterNode -Name $NewClusterNode
# This should output something, but it does not

Write-PSFMessage -Level Host -Message 'Lets see if we have a new node'
Get-Cluster -Name $ClusterName | Get-ClusterNode
# Yes, we have


# Begin of code from 01_setup_instances.ps1

$administratorCredential = New-Object -TypeName PSCredential -ArgumentList "$DomainName\Admin", $AdminPassword
$sqlServerCredential = New-Object -TypeName PSCredential -ArgumentList "$DomainName\$SQLServerServiceAccount", $SqlPassword

Write-PSFMessage -Level Host -Message 'Change powerplan of new cluster node to high performance'
Set-DbaPowerPlan -ComputerName $NewClusterNode | Format-Table

Write-PSFMessage -Level Host -Message 'Install SQL Server instances on new cluster node'
$installParams = @{
    SqlInstance        = $NewSqlInstance
    Version            = 2019
    Feature            = 'Engine'
    Path               = $SQLServerSourcesPath
    UpdateSourcePath   = $SQLServerPatchesPath
    EngineCredential   = $sqlServerCredential
    AgentCredential    = $sqlServerCredential
    AuthenticationMode = 'Mixed'
    SaCredential       = $sqlServerCredential
    Credential         = $administratorCredential
    Restart            = $true
    EnableException    = $false
}
$installResult = Install-DbaInstance @installParams
$installResult | Format-Table
if ($false -in $installResult.Successful) {
    throw "Install-DbaInstance not successful"
}

Write-PSFMessage -Level Host -Message 'Grant instant file initialization rights to SQL Server service account on new cluster node'
Set-DbaPrivilege -ComputerName $NewClusterNode -Type IFI

Write-PSFMessage -Level Host -Message 'Configure SQL Server instances: MaxMemory / MaxDop / CostThresholdForParallelism'
Set-DbaMaxMemory -SqlInstance $NewSqlInstance -Max 2048 | Format-Table
Set-DbaMaxDop -SqlInstance $NewSqlInstance | Format-Table
Set-DbaSpConfigure -SqlInstance $NewSqlInstance -Name CostThresholdForParallelism -Value 50 | Format-Table

# End of code from 01_setup_instances.ps1


# Begin of code from 02_setup_availability_group.ps1

Write-PSFMessage -Level Host -Message 'Configure SQL Server instance service to enable Always On'
Enable-DbaAgHadr -SqlInstance $NewSqlInstance -Force | Format-Table

# End of code from 02_setup_availability_group.ps1


$ag = Get-DbaAvailabilityGroup -SqlInstance $SqlInstances -AvailabilityGroup $AvailabilityGroupName | Where-Object LocalReplicaRole -eq Primary
$primaryReplica = Get-DbaAgReplica -SqlInstance $ag.Parent -AvailabilityGroup $AvailabilityGroupName | Where-Object Role -eq Primary

$replicaParameters = @{
    SqlInstance                   = $NewSqlInstance
    AvailabilityMode              = $primaryReplica.AvailabilityMode
    FailoverMode                  = $primaryReplica.FailoverMode
    BackupPriority                = $primaryReplica.BackupPriority
    ConnectionModeInPrimaryRole   = $primaryReplica.ConnectionModeInPrimaryRole
    ConnectionModeInSecondaryRole = $primaryReplica.ConnectionModeInSecondaryRole
    SeedingMode                   = 'Manual'
    ConfigureXESession            = $true
}

# Special configuration for one of our clients:
$replicaParameters['EndpointUrl'] = 'TCP://192.168.3.33:5023'

Write-PSFMessage -Level Host -Message 'Adding replica to Always On Availability Group with manual seeding'
$ag | Add-DbaAgReplica @replicaParameters | Format-Table

# Wait for new replica to connect to Availability Group
Write-PSFMessage -Level Host -Message 'waiting...'
Start-Sleep -Seconds 30

Write-PSFMessage -Level Host -Message 'Adding databases to Always On Availability Group with manual seeding'
Add-DbaAgDatabase -SqlInstance $primaryReplica.SqlInstance -AvailabilityGroup $AvailabilityGroupName -Database $ag.AvailabilityDatabases.Name -SharedPath $BackupPath | Format-Table
Get-DbaAgReplica -SqlInstance $primaryReplica.SqlInstance -AvailabilityGroup $AvailabilityGroupName | Format-Table
Get-DbaAgDatabase -SqlInstance $NewSqlInstance -AvailabilityGroup $AvailabilityGroupName | Format-Table


# This is optional just to show some more features:

Write-PSFMessage -Level Host -Message 'waiting...'
Start-Sleep -Seconds 30

$null = Remove-DbaAgReplica -SqlInstance $ag.Parent -AvailabilityGroup $AvailabilityGroupName -Replica $NewSqlInstance
$null = Get-DbaDatabase -SqlInstance $NewSqlInstance -Database $ag.AvailabilityDatabases.Name | Remove-DbaDatabase
$null = Get-DbaEndpoint -SqlInstance $NewSqlInstance -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false

$replicaParameters = @{
    SqlInstance                   = $NewSqlInstance
    AvailabilityMode              = $primaryReplica.AvailabilityMode
    FailoverMode                  = $primaryReplica.FailoverMode
    BackupPriority                = $primaryReplica.BackupPriority
    ConnectionModeInPrimaryRole   = $primaryReplica.ConnectionModeInPrimaryRole
    ConnectionModeInSecondaryRole = $primaryReplica.ConnectionModeInSecondaryRole
    SeedingMode                   = 'Automatic'
    ConfigureXESession            = $true
}

Write-PSFMessage -Level Host -Message 'Adding replica to Always On Availability Group with automatic seeding'
$ag | Add-DbaAgReplica @replicaParameters | Format-Table

# Wait for new replica to connect to Availability Group and for automatic seeding to move databases to new replica
Write-PSFMessage -Level Host -Message 'waiting...'
Start-Sleep -Seconds 30

Get-DbaAgReplica -SqlInstance $primaryReplica.SqlInstance -AvailabilityGroup $AvailabilityGroupName | Format-Table
Get-DbaAgDatabase -SqlInstance $NewSqlInstance -AvailabilityGroup $AvailabilityGroupName | Format-Table


Write-PSFMessage -Level Host -Message 'finished'

} catch { Write-PSFMessage -Level Warning -Message 'failed' -ErrorRecord $_ }
