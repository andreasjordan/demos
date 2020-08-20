[CmdletBinding()]
param (
    [string[]]$ClusterNodes = @('SRV1', 'SRV2'),
    [string[]]$InstanceNames = @('SQL2014', 'SQL2016', 'SQL2017', 'SQL2019'),
    [string[]]$SqlVersions = @('2014', '2016', '2017', '2019'),
    [int[]]$HadrEndpointPorts = @(5022, 5023, 5024, 5025),
    [string[]]$AvailabilityGroupNames = @('Adventure2014', 'Adventure2016', 'Adventure2017', 'Adventure2019'),
    [System.Net.IPAddress[]]$AvailabilityGroupIPs = @('192.168.3.71', '192.168.3.72', '192.168.3.73', '192.168.3.74'),
    [PSCredential]$AdministratorCredential = (New-Object -TypeName PSCredential -ArgumentList "COMPANY\Administrator", (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force)),
    [PSCredential]$SqlServerCredential = (New-Object -TypeName PSCredential -ArgumentList "COMPANY\SQLServer", (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force)),
    [string]$BackupPath = '\\WIN10\SQLServerBackups',
    [string]$DatabaseName = 'AdventureWorks'
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

$instances = @() 
foreach ( $nr in 0 .. ($InstanceNames.Count - 1) ) { 
    $instances += [PSCustomObject]@{
        InstanceName = $InstanceNames[$nr]
        SqlVersion = $SqlVersions[$nr]
        HadrEndpointPort = $HadrEndpointPorts[$nr]
        AvailabilityGroupName = $AvailabilityGroupNames[$nr]
        AvailabilityGroupIP = $AvailabilityGroupIPs[$nr]
    }
}

Write-LocalHost -Message 'Import module dbatools'
Import-Module -Name dbatools -MinimumVersion 1.0.115

foreach ( $instance in $instances ) {
    $sqlInstances = @();
    foreach ( $node in $ClusterNodes ) {
        $sqlInstances += "$node\$($instance.InstanceName)"
    }

    Write-LocalHost -Message "Configure SQL Server $($instance.SqlVersion) instance service to enable Always On"
    Enable-DbaAgHadr -SqlInstance $sqlInstances -Force | Format-Table

    Write-LocalHost -Message 'Configure and start extended event session AlwaysOn_health'
    Get-DbaXESession -SqlInstance $sqlInstances -Session AlwaysOn_health | ForEach-Object -Process { $_.AutoStart = $true ; $_.Alter() ; $_ | Start-DbaXESession } | Format-Table

    Write-LocalHost -Message 'Create endpoints'
    $endpoint = New-DbaEndpoint -SqlInstance $sqlInstances -Name hadr_endpoint -Type DatabaseMirroring -EndpointEncryption Supported -EncryptionAlgorithm Aes -Port $instance.HadrEndpointPort
    $endpoint | Start-DbaEndpoint | Format-Table

    $availabilityGroupParameters = @{
        Primary     = $SqlInstances[0]
        Secondary   = $SqlInstances[1]
        Name        = $instance.AvailabilityGroupName
        IPAddress   = $instance.AvailabilityGroupIP
        Database    = $DatabaseName
        ClusterType = 'Wsfc'
        Confirm     = $false
    }
    Write-LocalHost -Message 'Create Always On Availability Group with manual seeding'
    if ( $instance.SqlVersion -eq '2014' ) {
        Write-LocalHost -Message 'Sorry, there is a bug that prevents this command from working on SQL Server 2014'
        continue
    }
    New-DbaAvailabilityGroup @availabilityGroupParameters -SeedingMode Manual -SharedPath $BackupPath | Format-Table
    #New-DbaAvailabilityGroup @availabilityGroupParameters -SeedingMode Automatic | Format-Table
    Get-DbaAgReplica -SqlInstance $SqlInstances[0] -AvailabilityGroup $instance.AvailabilityGroupName | Format-Table
    Get-DbaAgDatabase -SqlInstance $SqlInstances -AvailabilityGroup $instance.AvailabilityGroupName -Database $DatabaseName | Format-Table

}

Write-LocalHost -Message 'finished'
