[CmdletBinding()]
param (
    [string[]]$SqlInstances = @('SQL01\SQL2017', 'SQL02\SQL2017'),
    [string]$BackupPath = '\\fs\Backup',
    [string]$DatabaseName = 'AdventureWorks',
    [string]$AvailabilityGroupName = 'AdventureSQL2017',
    [System.Net.IPAddress]$AvailabilityGroupIP = '192.168.3.72',
    [string[]]$EndpointUrls = @('TCP://192.168.3.31:5024', 'TCP://192.168.3.32:5024')
)

$ErrorActionPreference = 'Stop'

Import-Module -Name PSFramework
Import-Module -Name dbatools

$PSDefaultParameterValues['*-Dba*:EnableException'] = $true
$PSDefaultParameterValues['*-Dba*:Confirm'] = $false

try {

Write-PSFMessage -Level Host -Message 'Configure SQL Server instance service to enable Always On'
Enable-DbaAgHadr -SqlInstance $SqlInstances -Force | Format-Table

$availabilityGroupParameters = @{
    Primary            = $SqlInstances[0]
    Secondary          = $SqlInstances[1]
    Name               = $AvailabilityGroupName
    IPAddress          = $AvailabilityGroupIP
    Port               = 14330                 # This is only needed if you have also run the 02_setup_availability_group.ps1 - as the other availability group already uses port 1433
    Database           = $DatabaseName
    ClusterType        = 'Wsfc'
    ConfigureXESession = $true
}

# Special configuration for one of our clients:
$availabilityGroupParameters['DtcSupport'] = $true
$availabilityGroupParameters['ConnectionModeInSecondaryRole'] = 'AllowAllConnections'
if ($EndpointUrls.Count -gt 0) {
    $availabilityGroupParameters['EndpointUrl'] = $EndpointUrls
}

Write-PSFMessage -Level Host -Message 'Create Always On Availability Group with automatic seeding'
$availabilityGroupParameters['SeedingMode'] = 'Automatic'
New-DbaAvailabilityGroup @availabilityGroupParameters | Format-Table
Get-DbaAgReplica -SqlInstance $SqlInstances[0] -AvailabilityGroup $AvailabilityGroupName | Format-Table
Get-DbaAgDatabase -SqlInstance $SqlInstances -AvailabilityGroup $AvailabilityGroupName -Database $DatabaseName | Format-Table


# This is optional just to show some more features:

Write-PSFMessage -Level Host -Message 'waiting...'
Start-Sleep -Seconds 30

Write-PSFMessage -Level Host -Message 'Drop Always On Availability Group'
$null = Remove-DbaAvailabilityGroup -SqlInstance $SqlInstances[0] -AvailabilityGroup $AvailabilityGroupName
$null = Remove-DbaDatabase -SqlInstance $SqlInstances[1] -Database $DatabaseName
$null = Get-DbaEndpoint -SqlInstance $SqlInstances -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false

Write-PSFMessage -Level Host -Message 'waiting...'
Start-Sleep -Seconds 30

Write-PSFMessage -Level Host -Message 'Create Always On Availability Group with manual seeding'
$availabilityGroupParameters['SeedingMode'] = 'Manual'
$availabilityGroupParameters['SharedPath'] = $BackupPath
New-DbaAvailabilityGroup @availabilityGroupParameters | Format-Table
Get-DbaAgReplica -SqlInstance $SqlInstances[0] -AvailabilityGroup $AvailabilityGroupName | Format-Table
Get-DbaAgDatabase -SqlInstance $SqlInstances -AvailabilityGroup $AvailabilityGroupName -Database $DatabaseName | Format-Table


Write-PSFMessage -Level Host -Message 'Add database to Always On Availability Group with backup-restore and automatic seeding'
$null = New-DbaDatabase -SqlInstance $SqlInstances[0] -Name TestDB
$null = Backup-DbaDatabase -SqlInstance $SqlInstances[0] -Database TestDB -Path $BackupPath -Type Full | Restore-DbaDatabase -SqlInstance $SqlInstances[1] -NoRecovery
$null = Backup-DbaDatabase -SqlInstance $SqlInstances[0] -Database TestDB -Path $BackupPath -Type Log | Restore-DbaDatabase -SqlInstance $SqlInstances[1] -Continue -NoRecovery
Add-DbaAgDatabase -SqlInstance $SqlInstances[0] -AvailabilityGroup $AvailabilityGroupName -Database TestDB -Secondary $SqlInstances[1] -SeedingMode Automatic | Format-Table
Get-DbaAgDatabase -SqlInstance $SqlInstances -AvailabilityGroup $AvailabilityGroupName -Database TestDB | Format-Table


Write-PSFMessage -Level Host -Message 'finished'

} catch { Write-PSFMessage -Level Warning -Message 'failed' -ErrorRecord $_ }

