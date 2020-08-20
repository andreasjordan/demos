[CmdletBinding()]
param (
    [string[]]$SqlInstances = @('SRV1', 'SRV2'),
    [string]$BackupPath = '\\WIN10\SQLServerBackups',
    [string]$DatabaseName = 'AdventureWorks',
    [string]$AvailabilityGroupName = 'AdventureSQL',
    [System.Net.IPAddress]$AvailabilityGroupIP = '192.168.3.71'
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

Write-LocalHost -Message 'Configure SQL Server instance service to enable Always On'
Enable-DbaAgHadr -SqlInstance $SqlInstances -Force | Format-Table

Write-LocalHost -Message 'Configure and start extended event session AlwaysOn_health'
Get-DbaXESession -SqlInstance $SqlInstances -Session AlwaysOn_health | ForEach-Object -Process { $_.AutoStart = $true ; $_.Alter() ; $_ | Start-DbaXESession } | Format-Table

$availabilityGroupParameters = @{
    Primary     = $SqlInstances[0]
    Secondary   = $SqlInstances[1]
    Name        = $AvailabilityGroupName
    IPAddress   = $AvailabilityGroupIP
    Database    = $DatabaseName
    ClusterType = 'Wsfc'
    Confirm     = $false
}
Write-LocalHost -Message 'Create Always On Availability Group with manual seeding'
New-DbaAvailabilityGroup @availabilityGroupParameters -SeedingMode Manual -SharedPath $BackupPath | Format-Table
#New-DbaAvailabilityGroup @availabilityGroupParameters -SeedingMode Automatic | Format-Table
Get-DbaAgReplica -SqlInstance $SqlInstances[0] -AvailabilityGroup $AvailabilityGroupName | Format-Table
Get-DbaAgDatabase -SqlInstance $SqlInstances -AvailabilityGroup $AvailabilityGroupName -Database $DatabaseName | Format-Table

Write-LocalHost -Message 'finished'

<#
Write-LocalHost -Message 'Drop Always On Availability Group'
$null = Remove-DbaAvailabilityGroup -SqlInstance $SqlInstances[0] -AvailabilityGroup $AvailabilityGroupName -Confirm:$false
$null = Remove-DbaDatabase -SqlInstance $SqlInstances[1] -Database $DatabaseName -Confirm:$false

Write-LocalHost -Message 'Create Always On Availability Group with automatic seeding'
#New-DbaAvailabilityGroup @availabilityGroupParameters -SeedingMode Manual -SharedPath $BackupPath -Verbose | Format-Table
New-DbaAvailabilityGroup @availabilityGroupParameters -SeedingMode Automatic | Format-Table
Get-DbaAgReplica -SqlInstance $SqlInstances[0] -AvailabilityGroup $AvailabilityGroupName | Format-Table
Get-DbaAgDatabase -SqlInstance $SqlInstances -AvailabilityGroup $AvailabilityGroupName -Database $DatabaseName | Format-Table
#>
