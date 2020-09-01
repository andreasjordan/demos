<#
Script to add a database to an empty availability group on every instance of SRV1 and SRV2 with automatic seeding
But step by step with only a little help from dbatools
And with the choice to run some parts as plain SQL

Run this script after: 02_setup_availability_group_demo_02_empty_availability_group.ps1

To update dbatools: Update-Module -Name dbatools 
To get the sql server error message: $Error[0].GetBaseException()

TODO: Only wait for SynchronizationState = 'Synchronized', if $replicaAvailabilityMode = 'SynchronousCommit' (otherwise wait for 'Synchronizing')

TODO: Try to enable compression: https://www.mssqltips.com/sqlservertip/4537/sql-server-2016-availability-group-automatic-seeding/#:~:text=Automatic%20Seeding%20is%20a%20replica,compression%20of%20the%20data%20stream.
#>

# You can comment this out to use SQL instead when possible
$useDBAtools = $true



$ErrorActionPreference = 'Stop'

Import-Module -Name dbatools -MinimumVersion 1.0.116

#$sqlInstance2014 = Connect-DbaInstance -SqlInstance 'SRV1\SQL2014', 'SRV2\SQL2014'
$sqlInstance2016 = Connect-DbaInstance -SqlInstance 'SRV1\SQL2016', 'SRV2\SQL2016'
$sqlInstance2017 = Connect-DbaInstance -SqlInstance 'SRV1\SQL2017', 'SRV2\SQL2017'
$sqlInstance2019 = Connect-DbaInstance -SqlInstance 'SRV1\SQL2019', 'SRV2\SQL2019'

$sqlInstanceAll = $sqlInstance2014 + $sqlInstance2016 + $sqlInstance2017 + $sqlInstance2019



function Write-LocalWarning {
    param (
        [string]$Message
    )
    Write-Warning -Message ('{0}: {1}' -f (Get-Date -Format HH:mm:ss.fff), $Message)
}

function Write-LocalHost {
    param (
        [string]$Message,
        [string]$ForegroundColor = 'Yellow'
    )
    Microsoft.PowerShell.Utility\Write-Host -Object ('{0}: {1}' -f (Get-Date -Format HH:mm:ss.fff), $Message) -ForegroundColor $ForegroundColor
}



#######
# Task: Configure secondary replica for automatic seeding
#######

#$replicaSeedingMode = 'Manual'                                    # Default in CREATE AVAILABILITY GROUP and New-DbaAvailabilityGroup
$replicaSeedingMode = 'Automatic'


# Hint to development of Add-DbaAgDatabase:
# If seeding mode in parameter -SeedingMode is different from actual seeding mode of replicas, 
# then it has to be changed at start and changed back on end of Add-DbaAgDatabase
# If changed from manual to automatic, grants are needed.
# If changed from automatic to manual, revokes are needed.

# Hint to development of New-DbaAvailabilityGroup:
# Set seeding mode of replicas before starting Add-DbaAgDatabase.

# Maybe add grant or revoke to Set-DbaAgReplica and use this one.


$createMonitoringTableSql = "CREATE TABLE master.dbo.ag_db_health(
	[date] [varchar](30) NULL,
	[server] [nvarchar](128) NULL,
	[ag_name] [sysname] NULL,
	[ag_primary_recovery_health_desc] [nvarchar](60) NULL,
	[ag_secondary_recovery_health_desc] [nvarchar](60) NULL,
	[ag_synchronization_health_desc] [nvarchar](60) NULL,
	[primary_operational_state_desc] [nvarchar](60) NULL,
	[secondary_operational_state_desc] [nvarchar](60) NULL,
	[primary_connected_state_desc] [nvarchar](60) NULL,
	[secondary_connected_state_desc] [nvarchar](60) NULL,
	[primary_recovery_health_desc] [nvarchar](60) NULL,
	[secondary_recovery_health_desc] [nvarchar](60) NULL,
	[primary_synchronization_health_desc] [nvarchar](60) NULL,
	[secondary_synchronization_health_desc] [nvarchar](60) NULL,
	[primary_last_connect_error_description] [nvarchar](1024) NULL,
	[secondary_last_connect_error_description] [nvarchar](1024) NULL,
	[database_name] [nvarchar](128) NULL,
	[primary_database_state_desc] [nvarchar](60) NULL,
	[primary_database_synchronization_state_desc] [nvarchar](60) NULL,
	[primary_database_synchronization_health_desc] [nvarchar](60) NULL,
	[secondary_database_state_desc] [nvarchar](60) NULL,
	[secondary_database_synchronization_state_desc] [nvarchar](60) NULL,
	[secondary_database_synchronization_health_desc] [nvarchar](60) NULL

)"

$insertMonitoringTableSql = "DECLARE @starttime AS datetime
WHILE 1=1
BEGIN
    INSERT INTO master.dbo.ag_db_health
    SELECT CONVERT(VARCHAR, GETDATE(), 126) AS date
         , @@SERVERNAME AS server
         , ag.name AS ag_name
         , ags.primary_recovery_health_desc AS ag_primary_recovery_health_desc
         , ags.secondary_recovery_health_desc AS ag_secondary_recovery_health_desc
         , ags.synchronization_health_desc AS ag_synchronization_health_desc
         , arsp.operational_state_desc AS primary_operational_state_desc
         , arss.operational_state_desc AS secondary_operational_state_desc
         , arsp.connected_state_desc AS primary_connected_state_desc
         , arss.connected_state_desc AS secondary_connected_state_desc
         , arsp.recovery_health_desc AS primary_recovery_health_desc
         , arss.recovery_health_desc AS secondary_recovery_health_desc
         , arsp.synchronization_health_desc AS primary_synchronization_health_desc
         , arss.synchronization_health_desc AS secondary_synchronization_health_desc
         , arsp.last_connect_error_description AS primary_last_connect_error_description
         , arss.last_connect_error_description AS secondary_last_connect_error_description
		 , DB_NAME(drsp.database_id) AS database_name
		 , drsp.database_state_desc AS primary_database_state_desc
		 , drsp.synchronization_state_desc AS primary_database_synchronization_state_desc
		 , drsp.synchronization_health_desc AS primary_database_synchronization_health_desc
		 , drss.database_state_desc AS secondary_database_state_desc
		 , drss.synchronization_state_desc AS secondary_database_synchronization_state_desc
		 , drss.synchronization_health_desc AS secondary_database_synchronization_health_desc
      FROM sys.availability_groups ag
           JOIN sys.dm_hadr_availability_group_states ags ON ag.group_id = ags.group_id
           LEFT JOIN (select * from sys.dm_hadr_availability_replica_states WHERE role_desc = 'PRIMARY') arsp ON ag.group_id = arsp.group_id
           LEFT JOIN (select * from sys.dm_hadr_availability_replica_states WHERE role_desc = 'SECONDARY') arss ON ag.group_id = arss.group_id
           LEFT JOIN (select * from sys.dm_hadr_database_replica_states WHERE is_primary_replica = 1) drsp ON ag.group_id = drsp.group_id
           LEFT JOIN (select * from sys.dm_hadr_database_replica_states WHERE is_primary_replica = 0) drss ON ag.group_id = drss.group_id
     WHERE drsp.synchronization_health_desc IS NOT NULL
	    OR drss.synchronization_health_desc IS NOT NULL
    IF @@ROWCOUNT > 0 AND @starttime IS NULL 
        SET @starttime = getdate()
    IF DATEADD(SECOND, 40, @starttime) < GETDATE()
        BREAK
END"

$jobName = 'MonitorAddingAvailabilityDatabase'

$getHealthSql = "SELECT * FROM master.dbo.ag_db_health"


<# To speed up the transfer, you can use backup and restore before adding the database to the availability group:
Backup-DbaDatabase -SqlInstance $sqlInstance2016[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Database | Restore-DbaDatabase -SqlInstance $sqlInstance2016[1] -NoRecovery | Out-Null
Backup-DbaDatabase -SqlInstance $sqlInstance2016[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Log | Restore-DbaDatabase -SqlInstance $sqlInstance2016[1] -NoRecovery -Continue | Out-Null
Backup-DbaDatabase -SqlInstance $sqlInstance2017[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Database | Restore-DbaDatabase -SqlInstance $sqlInstance2017[1] -NoRecovery | Out-Null
Backup-DbaDatabase -SqlInstance $sqlInstance2017[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Log | Restore-DbaDatabase -SqlInstance $sqlInstance2017[1] -NoRecovery -Continue | Out-Null
Backup-DbaDatabase -SqlInstance $sqlInstance2019[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Database | Restore-DbaDatabase -SqlInstance $sqlInstance2019[1] -NoRecovery | Out-Null
Backup-DbaDatabase -SqlInstance $sqlInstance2019[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Log | Restore-DbaDatabase -SqlInstance $sqlInstance2019[1] -NoRecovery -Continue | Out-Null
#>


$agName = 'MyTestAg2016'
$sqlInstancePrimary = $sqlInstance2016[0]
$sqlInstanceSecondary = $sqlInstance2016[1]

Write-LocalHost -Message "Starting building $agName"

Write-LocalHost -Message "Setting up monitoring"
$sqlInstancePrimary.Query($createMonitoringTableSql)
$null = New-DbaAgentJob -SqlInstance $sqlInstancePrimary -Job $jobName -DeleteLevel OnSuccess
$null = New-DbaAgentJobStep -SqlInstance $sqlInstancePrimary -Job $jobName -StepName $jobName -Subsystem TransactSql -Command $insertMonitoringTableSql
$null = Start-DbaAgentJob -SqlInstance $sqlInstancePrimary -Job $jobName
$sqlInstanceSecondary.Query($createMonitoringTableSql)
$null = New-DbaAgentJob -SqlInstance $sqlInstanceSecondary -Job $jobName -DeleteLevel OnSuccess
$null = New-DbaAgentJobStep -SqlInstance $sqlInstanceSecondary -Job $jobName -StepName $jobName -Subsystem TransactSql -Command $insertMonitoringTableSql
$null = Start-DbaAgentJob -SqlInstance $sqlInstanceSecondary -Job $jobName
# Wait just in case the job needs to spin up, first queries to DMVs are sometimes slow
Start-Sleep -Seconds 5

Write-LocalHost -Message "Setting up availability group"
$smoAvailabilityGroup = Get-DbaAvailabilityGroup -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName
if ( $smoAvailabilityGroup.LocalReplicaRole -eq 'Secondary' ) {
    $smoAvailabilityGroup = Invoke-DbaAgFailover -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName -Confirm:$false
}

Write-LocalHost -Message "Granting GRANT CREATE ANY DATABASE on the primary replica"
$sqlInstancePrimary.Query("ALTER AVAILABILITY GROUP [$agName] GRANT CREATE ANY DATABASE")

Write-LocalHost -Message "Granting GRANT CREATE ANY DATABASE on the secondary replica"
$sqlInstanceSecondary.Query("ALTER AVAILABILITY GROUP [$agName] GRANT CREATE ANY DATABASE")

Write-LocalHost -Message "Starting main tasks"
if ( $useDBAtools ) {
    Write-LocalHost -Message "Changing the seeding mode of all replicas on the primary replica"
    $smoAvailabilityReplicas = Get-DbaAgReplica -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName
    $smoAvailabilityReplicas | ForEach-Object -Process { $_.SeedingMode = $replicaSeedingMode ; $_.Alter() }
    Write-LocalHost -Message "smoAvailabilityReplicas are configured"

    $smoAvailabilityDatabasePrimary = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($smoAvailabilityGroup, 'AdventureWorks')
    Write-LocalHost -Message "smoAvailabilityDatabasePrimary is ready"

    $smoAvailabilityDatabasePrimary.Create()
    Write-LocalHost -Message "AvailabilityDatabase is created"

	# https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
    while ( $smoAvailabilityDatabasePrimary.State -ne 'Existing' ) {
        Write-LocalWarning -Message "State of AvailabilityDatabase is still $($smoAvailabilityDatabasePrimary.State)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabasePrimary.Refresh()
    }
    $smoAvailabilityDatabasePrimary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    $smoAvailabilityDatabaseSecondary = Get-DbaAgDatabase -SqlInstance $sqlInstanceSecondary -AvailabilityGroup $agName -Database AdventureWorks
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is ready"

	# https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
    while ( $smoAvailabilityDatabaseSecondary.State -ne 'Existing' ) {
        Write-LocalWarning -Message "State of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.State)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is existing"
    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    # With automatic seeding, .JoinAvailablityGroup() is not needed, just wait for the magic to happen
    while ( -not $smoAvailabilityDatabaseSecondary.IsJoined ) {
        $seedingStats = $sqlInstancePrimary.Query("SELECT * FROM sys.dm_hadr_physical_seeding_stats")
        if ( $seedingStats -eq $null ) {
            Write-LocalWarning -Message "No seeding stats available"
        } else {
            Write-LocalWarning -Message "Seeding stats: internal_state_desc: $($seedingStats.internal_state_desc)  transferred_size_bytes: $($seedingStats.transferred_size_bytes)  database_size_bytes: $($seedingStats.database_size_bytes)  percent complete: $($seedingStats.transferred_size_bytes * 100.0 / $seedingStats.database_size_bytes)  estimate_time_complete_utc: $($seedingStats.estimate_time_complete_utc)"
            if ( $seedingStats.failure_message.ToString() -ne '' ) {
                Write-LocalWarning -Message "Seeding stats: failure_message: $($seedingStats.failure_message)"
            }
        }
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is joined"
    $seedingStats = $sqlInstancePrimary.Query("SELECT * FROM sys.dm_hadr_physical_seeding_stats")
    if ( $seedingStats -eq $null ) {
        Write-LocalWarning -Message "No seeding stats available"
    } else {
        Write-LocalWarning -Message "Seeding stats: internal_state_desc: $($seedingStats.internal_state_desc)  transferred_size_bytes: $($seedingStats.transferred_size_bytes)  database_size_bytes: $($seedingStats.database_size_bytes)  percent complete: $($seedingStats.transferred_size_bytes * 100.0 / $seedingStats.database_size_bytes)  estimate_time_complete_utc: $($seedingStats.estimate_time_complete_utc)"
        if ( $seedingStats.failure_message.ToString() -ne '' ) {
            Write-LocalWarning -Message "Seeding stats: failure_message: $($seedingStats.failure_message)"
        }
    }
    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    while ( $smoAvailabilityDatabaseSecondary.SynchronizationState -ne 'Synchronized' ) {
        Write-LocalWarning -Message "SynchronizationState of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.SynchronizationState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is synchronized"
    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    # Show the backup, that was used to transfer the data to the secondary:
    Get-DbaDbBackupHistory -SqlInstance $sqlInstancePrimary -Database AdventureWorks -AgCheck -IncludeCopyOnly -Since (Get-Date).AddHours(-1) | Format-Table

    # This one command would do all things in this block, but some more I don't like (at the moment):
    # Add-DbaAgDatabase -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName -Database AdventureWorks -SeedingMode Automatic

<# Output:

11:42:33.175: Starting building MyTestAg2016
11:42:33.206: Setting up monitoring
11:42:46.143: Setting up availability group
11:42:51.424: Granting GRANT CREATE ANY DATABASE on the primary replica
11:42:51.440: Granting GRANT CREATE ANY DATABASE on the secondary replica
11:42:51.768: Starting main tasks
11:42:51.784: Changing the seeding mode of all replicas on the primary replica
11:42:52.346: smoAvailabilityReplicas are configured
11:42:52.346: smoAvailabilityDatabasePrimary is ready
11:42:52.409: AvailabilityDatabase is created

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized


11:42:56.956: smoAvailabilityDatabaseSecondary is ready
11:42:56.956: smoAvailabilityDatabaseSecondary is existing

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
          False    False                     False       False Existing     NotSynchronizing


WARNING: 11:42:58.393: Seeding stats: internal_state_desc: ReadingAndSendingData  transferred_size_bytes: 0  database_size_bytes: 219799552  percent complete: 0  estimate_time_complete_utc: 09/01/2020 09:42:57
WARNING: 11:43:04.065: Seeding stats: internal_state_desc: ReadingAndSendingData  transferred_size_bytes: 190849536  database_size_bytes: 219799552  percent complete: 86.828901270918  estimate_time_complete_utc: 09/01/2020 09:43:03
WARNING: 11:43:06.003: Seeding stats: internal_state_desc: WaitingForRestoreToFinish  transferred_size_bytes: 216423936  database_size_bytes: 219799552  percent complete: 98.4642298088033  estimate_time_complete_utc: 09/01/2020 09:43:05
WARNING: 11:43:08.565: Seeding stats: internal_state_desc: WaitingForRestoreToFinish  transferred_size_bytes: 216423936  database_size_bytes: 219799552  percent complete: 98.4642298088033  estimate_time_complete_utc: 09/01/2020 09:43:07
11:43:17.769: smoAvailabilityDatabaseSecondary is joined
WARNING: 11:43:17.769: Seeding stats: internal_state_desc: Success  transferred_size_bytes: 216423936  database_size_bytes: 219799552  percent complete: 98.4642298088033  estimate_time_complete_utc: 09/01/2020 09:43:08

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
          False     True                     False       False Existing     NotSynchronizing


WARNING: 11:43:17.800: SynchronizationState of AvailabilityDatabase is still NotSynchronizing
11:43:20.253: smoAvailabilityDatabaseSecondary is synchronized

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized



SqlInstance  Database       Type TotalSize DeviceType     Start                   Duration End                    
-----------  --------       ---- --------- ----------     -----                   -------- ---                    
SRV1\SQL2016 AdventureWorks Full 206.39 MB Virtual Device 2020-09-01 11:42:58.000 00:00:06 2020-09-01 11:43:04.000

#>

} else {
    # How to do it per SQL?

    Write-LocalHost -Message "Changing the seeding mode of all replicas on the primary replica"
    $sql = "ALTER AVAILABILITY GROUP [$agName] MODIFY REPLICA ON '$($sqlInstancePrimary.DomainInstanceName)' WITH (SEEDING_MODE = $replicaSeedingMode)"
    $sqlInstancePrimary.Query($sql)
    $sql = "ALTER AVAILABILITY GROUP [$agName] MODIFY REPLICA ON '$($sqlInstanceSecondary.DomainInstanceName)' WITH (SEEDING_MODE = $replicaSeedingMode)"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP MODIFY REPLICA is executed"

    $sql = "ALTER AVAILABILITY GROUP [$agName] ADD DATABASE [AdventureWorks]"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP ADD DATABASE is executed"
}

# Wait for the monitoring to finish and then get it
Start-Sleep -Seconds 20
$agDbHealth2016 = $sqlInstancePrimary.Query($getHealthSql) 
$agDbHealth2016 += $sqlInstanceSecondary.Query($getHealthSql) 
$agDbHealth2016 = $agDbHealth2016 | Sort-Object -Property date

# $agDbHealth2016 | Out-GridView

$agDbHealth2016 | Where-Object -Property server -Match 'SRV1' | Select-Object -First 20 | Format-Table -Property date, primary_database_state_desc, primary_database_synchronization_state_desc, primary_database_synchronization_health_desc, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
$agDbHealth2016 | Where-Object -Property server -Match 'SRV1' | Where-Object -Property secondary_database_synchronization_state_desc -NE 'NOT SYNCHRONIZING' | Select-Object -First 20 | Format-Table -Property date, primary_database_state_desc, primary_database_synchronization_state_desc, primary_database_synchronization_health_desc, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    primary_database_state_desc primary_database_synchronization_state_desc primary_database_synchronization_health_desc secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_healt
                                                                                                                                                                                                                         h_desc                                  
----                    --------------------------- ------------------------------------------- -------------------------------------------- ----------------------------- --------------------------------------------- ----------------------------------------
2020-09-01T11:42:52.353 ONLINE                      NOT SYNCHRONIZING                           NOT_HEALTHY                                                                NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.400 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.450 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.510 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.543 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.557 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.590 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.603 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.620 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.637 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.650 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.683 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.700 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.713 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.747 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.777 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.793 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.807 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.823 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:42:52.853 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
[...]
2020-09-01T11:43:11.603 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:11.637 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:11.650 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:11.667 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:11.700 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:11.713 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:11.730 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:11.747 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:16.247 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:16.260 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:16.277 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:16.293 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:16.307 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:16.323 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:16.340 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:16.353 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-09-01T11:43:16.370 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:43:16.400 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:43:16.400 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:43:16.417 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
#>

$agDbHealth2016 | Where-Object -Property server -Match 'SRV2' | Select-Object -First 20 | Format-Table -Property date, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_health_desc
----                    ----------------------------- --------------------------------------------- ----------------------------------------------
2020-09-01T11:43:08.790 RECOVERING                    INITIALIZING                                  NOT_HEALTHY                                   
2020-09-01T11:43:11.917 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:19.370 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:19.963 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:20.447 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:20.853 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:21.463 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:22.150 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:22.807 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:25.120 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:28.150 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:28.730 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:29.370 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:29.680 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:30.587 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:31.337 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:32.027 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:32.510 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:32.853 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:43:33.743 ONLINE                        SYNCHRONIZED                                  HEALTHY   
#>



$agName = 'MyTestAg2017'
$sqlInstancePrimary = $sqlInstance2017[0]
$sqlInstanceSecondary = $sqlInstance2017[1]

Write-LocalHost -Message "Starting building $agName"

Write-LocalHost -Message "Setting up monitoring"
$sqlInstancePrimary.Query($createMonitoringTableSql)
$null = New-DbaAgentJob -SqlInstance $sqlInstancePrimary -Job $jobName -DeleteLevel OnSuccess
$null = New-DbaAgentJobStep -SqlInstance $sqlInstancePrimary -Job $jobName -StepName $jobName -Subsystem TransactSql -Command $insertMonitoringTableSql
$null = Start-DbaAgentJob -SqlInstance $sqlInstancePrimary -Job $jobName
$sqlInstanceSecondary.Query($createMonitoringTableSql)
$null = New-DbaAgentJob -SqlInstance $sqlInstanceSecondary -Job $jobName -DeleteLevel OnSuccess
$null = New-DbaAgentJobStep -SqlInstance $sqlInstanceSecondary -Job $jobName -StepName $jobName -Subsystem TransactSql -Command $insertMonitoringTableSql
$null = Start-DbaAgentJob -SqlInstance $sqlInstanceSecondary -Job $jobName
# Wait just in case the job needs to spin up, first queries to DMVs are sometimes slow
Start-Sleep -Seconds 5

Write-LocalHost -Message "Setting up availability group"
$smoAvailabilityGroup = Get-DbaAvailabilityGroup -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName
if ( $smoAvailabilityGroup.LocalReplicaRole -eq 'Secondary' ) {
    $smoAvailabilityGroup = Invoke-DbaAgFailover -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName -Confirm:$false
}

Write-LocalHost -Message "Granting GRANT CREATE ANY DATABASE on the primary replica"
$sqlInstancePrimary.Query("ALTER AVAILABILITY GROUP [$agName] GRANT CREATE ANY DATABASE")

Write-LocalHost -Message "Granting GRANT CREATE ANY DATABASE on the secondary replica"
$sqlInstanceSecondary.Query("ALTER AVAILABILITY GROUP [$agName] GRANT CREATE ANY DATABASE")

Write-LocalHost -Message "Starting main tasks"
if ( $useDBAtools ) {
    Write-LocalHost -Message "Changing the seeding mode of all replicas on the primary replica"
    $smoAvailabilityReplicas = Get-DbaAgReplica -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName
    $smoAvailabilityReplicas | ForEach-Object -Process { $_.SeedingMode = $replicaSeedingMode ; $_.Alter() }
    Write-LocalHost -Message "smoAvailabilityReplicas are configured"

    $smoAvailabilityDatabasePrimary = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($smoAvailabilityGroup, 'AdventureWorks')
    Write-LocalHost -Message "smoAvailabilityDatabasePrimary is ready"

    $smoAvailabilityDatabasePrimary.Create()
    Write-LocalHost -Message "AvailabilityDatabase is created"

	# https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
    while ( $smoAvailabilityDatabasePrimary.State -ne 'Existing' ) {
        Write-LocalWarning -Message "State of AvailabilityDatabase is still $($smoAvailabilityDatabasePrimary.State)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabasePrimary.Refresh()
    }
    $smoAvailabilityDatabasePrimary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    $smoAvailabilityDatabaseSecondary = Get-DbaAgDatabase -SqlInstance $sqlInstanceSecondary -AvailabilityGroup $agName -Database AdventureWorks
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is ready"

	# https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
    while ( $smoAvailabilityDatabaseSecondary.State -ne 'Existing' ) {
        Write-LocalWarning -Message "State of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.State)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is existing"
    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    # With automatic seeding, .JoinAvailablityGroup() is not needed, just wait for the magic to happen
    while ( -not $smoAvailabilityDatabaseSecondary.IsJoined ) {
        $seedingStats = $sqlInstancePrimary.Query("SELECT * FROM sys.dm_hadr_physical_seeding_stats")
        if ( $seedingStats -eq $null ) {
            Write-LocalWarning -Message "No seeding stats available"
        } else {
            Write-LocalWarning -Message "Seeding stats: internal_state_desc: $($seedingStats.internal_state_desc)  transferred_size_bytes: $($seedingStats.transferred_size_bytes)  database_size_bytes: $($seedingStats.database_size_bytes)  percent complete: $($seedingStats.transferred_size_bytes * 100.0 / $seedingStats.database_size_bytes)  estimate_time_complete_utc: $($seedingStats.estimate_time_complete_utc)"
            if ( $seedingStats.failure_message.ToString() -ne '' ) {
                Write-LocalWarning -Message "Seeding stats: failure_message: $($seedingStats.failure_message)"
            }
        }
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is joined"
    $seedingStats = $sqlInstancePrimary.Query("SELECT * FROM sys.dm_hadr_physical_seeding_stats")
    if ( $seedingStats -eq $null ) {
        Write-LocalWarning -Message "No seeding stats available"
    } else {
        Write-LocalWarning -Message "Seeding stats: internal_state_desc: $($seedingStats.internal_state_desc)  transferred_size_bytes: $($seedingStats.transferred_size_bytes)  database_size_bytes: $($seedingStats.database_size_bytes)  percent complete: $($seedingStats.transferred_size_bytes * 100.0 / $seedingStats.database_size_bytes)  estimate_time_complete_utc: $($seedingStats.estimate_time_complete_utc)"
        if ( $seedingStats.failure_message.ToString() -ne '' ) {
            Write-LocalWarning -Message "Seeding stats: failure_message: $($seedingStats.failure_message)"
        }
    }
    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    while ( $smoAvailabilityDatabaseSecondary.SynchronizationState -ne 'Synchronized' ) {
        Write-LocalWarning -Message "SynchronizationState of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.SynchronizationState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is synchronized"
    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    # Show the backup, that was used to transfer the data to the secondary:
    Get-DbaDbBackupHistory -SqlInstance $sqlInstancePrimary -Database AdventureWorks -AgCheck -IncludeCopyOnly -Since (Get-Date).AddHours(-1) | Format-Table

    # This one command would do all things in this block, but some more I don't like (at the moment):
    # Add-DbaAgDatabase -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName -Database AdventureWorks -SeedingMode Automatic

<# Output:

11:43:41.003: Starting building MyTestAg2017
11:43:41.018: Setting up monitoring
11:44:06.784: Setting up availability group
11:44:12.253: Granting GRANT CREATE ANY DATABASE on the primary replica
11:44:12.300: Granting GRANT CREATE ANY DATABASE on the secondary replica
11:44:12.409: Starting main tasks
11:44:12.409: Changing the seeding mode of all replicas on the primary replica
11:44:12.988: smoAvailabilityReplicas are configured
11:44:12.988: smoAvailabilityDatabasePrimary is ready
11:44:13.065: AvailabilityDatabase is created

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized


11:44:18.565: smoAvailabilityDatabaseSecondary is ready
11:44:18.565: smoAvailabilityDatabaseSecondary is existing

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
          False    False                     False       False Existing     NotSynchronizing


WARNING: 11:44:21.222: Seeding stats: internal_state_desc: WaitingForRestoreToFinish  transferred_size_bytes: 216427008  database_size_bytes: 352313344  percent complete: 61.430261352803  estimate_time_complete_utc: 09/01/2020 09:44:22
WARNING: 11:44:25.050: Seeding stats: internal_state_desc: Success  transferred_size_bytes: 216427008  database_size_bytes: 352313344  percent complete: 61.430261352803  estimate_time_complete_utc: 09/01/2020 09:44:29
11:44:27.847: smoAvailabilityDatabaseSecondary is joined
WARNING: 11:44:27.940: Seeding stats: internal_state_desc: Success  transferred_size_bytes: 216427008  database_size_bytes: 352313344  percent complete: 61.430261352803  estimate_time_complete_utc: 09/01/2020 09:44:29

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized


11:44:27.940: smoAvailabilityDatabaseSecondary is synchronized

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized



SqlInstance  Database       Type TotalSize DeviceType     Start                   Duration End                    
-----------  --------       ---- --------- ----------     -----                   -------- ---                    
SRV1\SQL2017 AdventureWorks Full 206.39 MB Virtual Device 2020-09-01 11:44:13.000 00:00:06 2020-09-01 11:44:19.000

#>

} else {
    # How to do it per SQL?

    Write-LocalHost -Message "Changing the seeding mode of all replicas on the primary replica"
    $sql = "ALTER AVAILABILITY GROUP [$agName] MODIFY REPLICA ON '$($sqlInstancePrimary.DomainInstanceName)' WITH (SEEDING_MODE = $replicaSeedingMode)"
    $sqlInstancePrimary.Query($sql)
    $sql = "ALTER AVAILABILITY GROUP [$agName] MODIFY REPLICA ON '$($sqlInstanceSecondary.DomainInstanceName)' WITH (SEEDING_MODE = $replicaSeedingMode)"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP MODIFY REPLICA is executed"

    $sql = "ALTER AVAILABILITY GROUP [$agName] ADD DATABASE [AdventureWorks]"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP ADD DATABASE is executed"
}

# Wait for the monitoring to finish and then get it
Start-Sleep -Seconds 20
$agDbHealth2017 = $sqlInstancePrimary.Query($getHealthSql) 
$agDbHealth2017 += $sqlInstanceSecondary.Query($getHealthSql) 
$agDbHealth2017 = $agDbHealth2017 | Sort-Object -Property date

# $agDbHealth2017 | Out-GridView

$agDbHealth2017 | Where-Object -Property server -Match 'SRV1' | Select-Object -First 20 | Format-Table -Property date, primary_database_state_desc, primary_database_synchronization_state_desc, primary_database_synchronization_health_desc, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
$agDbHealth2017 | Where-Object -Property server -Match 'SRV1' | Where-Object -Property secondary_database_synchronization_state_desc -NE 'NOT SYNCHRONIZING' | Select-Object -First 20 | Format-Table -Property date, primary_database_state_desc, primary_database_synchronization_state_desc, primary_database_synchronization_health_desc, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    primary_database_state_desc primary_database_synchronization_state_desc primary_database_synchronization_health_desc secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_healt
                                                                                                                                                                                                                         h_desc                                  
----                    --------------------------- ------------------------------------------- -------------------------------------------- ----------------------------- --------------------------------------------- ----------------------------------------
2020-09-01T11:44:12.980 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:13.137 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:13.247 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:13.277 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:13.353 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:13.433 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:13.463 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:13.497 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:13.543 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:13.573 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:13.603 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:13.980 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:14.010 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:14.043 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:14.260 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:14.293 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:14.323 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:14.370 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:14.590 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:44:14.637 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
[...]
2020-09-01T11:44:25.900 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.260 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.307 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.353 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.400 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.433 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.480 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.510 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.557 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.603 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.637 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.667 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.730 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.760 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.793 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.823 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.870 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.900 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.933 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:44:26.950 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
#>

$agDbHealth2017 | Where-Object -Property server -Match 'SRV2' | Select-Object -First 20 | Format-Table -Property date, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_health_desc
----                    ----------------------------- --------------------------------------------- ----------------------------------------------
2020-09-01T11:44:22.290 RESTORING                     INITIALIZING                                  NOT_HEALTHY                                   
2020-09-01T11:44:24.133 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:26.760 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:27.713 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:28.133 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:28.383 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:28.837 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:29.243 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:29.573 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:29.883 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:30.120 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:30.463 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:30.823 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:31.230 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:31.493 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:31.917 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:32.133 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:32.510 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:33.040 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:44:33.400 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
#>



$agName = 'MyTestAg2019'
$sqlInstancePrimary = $sqlInstance2019[0]
$sqlInstanceSecondary = $sqlInstance2019[1]

Write-LocalHost -Message "Starting building $agName"

Write-LocalHost -Message "Setting up monitoring"
$sqlInstancePrimary.Query($createMonitoringTableSql)
$null = New-DbaAgentJob -SqlInstance $sqlInstancePrimary -Job $jobName -DeleteLevel OnSuccess
$null = New-DbaAgentJobStep -SqlInstance $sqlInstancePrimary -Job $jobName -StepName $jobName -Subsystem TransactSql -Command $insertMonitoringTableSql
$null = Start-DbaAgentJob -SqlInstance $sqlInstancePrimary -Job $jobName
$sqlInstanceSecondary.Query($createMonitoringTableSql)
$null = New-DbaAgentJob -SqlInstance $sqlInstanceSecondary -Job $jobName -DeleteLevel OnSuccess
$null = New-DbaAgentJobStep -SqlInstance $sqlInstanceSecondary -Job $jobName -StepName $jobName -Subsystem TransactSql -Command $insertMonitoringTableSql
$null = Start-DbaAgentJob -SqlInstance $sqlInstanceSecondary -Job $jobName
# Wait just in case the job needs to spin up, first queries to DMVs are sometimes slow
Start-Sleep -Seconds 5

Write-LocalHost -Message "Setting up availability group"
$smoAvailabilityGroup = Get-DbaAvailabilityGroup -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName
if ( $smoAvailabilityGroup.LocalReplicaRole -eq 'Secondary' ) {
    $smoAvailabilityGroup = Invoke-DbaAgFailover -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName -Confirm:$false
}

Write-LocalHost -Message "Granting GRANT CREATE ANY DATABASE on the primary replica"
$sqlInstancePrimary.Query("ALTER AVAILABILITY GROUP [$agName] GRANT CREATE ANY DATABASE")

Write-LocalHost -Message "Granting GRANT CREATE ANY DATABASE on the secondary replica"
$sqlInstanceSecondary.Query("ALTER AVAILABILITY GROUP [$agName] GRANT CREATE ANY DATABASE")

Write-LocalHost -Message "Starting main tasks"
if ( $useDBAtools ) {
    Write-LocalHost -Message "Changing the seeding mode of all replicas on the primary replica"
    $smoAvailabilityReplicas = Get-DbaAgReplica -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName
    $smoAvailabilityReplicas | ForEach-Object -Process { $_.SeedingMode = $replicaSeedingMode ; $_.Alter() }
    Write-LocalHost -Message "smoAvailabilityReplicas are configured"

    $smoAvailabilityDatabasePrimary = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($smoAvailabilityGroup, 'AdventureWorks')
    Write-LocalHost -Message "smoAvailabilityDatabasePrimary is ready"

    $smoAvailabilityDatabasePrimary.Create()
    Write-LocalHost -Message "AvailabilityDatabase is created"

	# https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
    while ( $smoAvailabilityDatabasePrimary.State -ne 'Existing' ) {
        Write-LocalWarning -Message "State of AvailabilityDatabase is still $($smoAvailabilityDatabasePrimary.State)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabasePrimary.Refresh()
    }
    $smoAvailabilityDatabasePrimary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    $smoAvailabilityDatabaseSecondary = Get-DbaAgDatabase -SqlInstance $sqlInstanceSecondary -AvailabilityGroup $agName -Database AdventureWorks
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is ready"

	# https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
    while ( $smoAvailabilityDatabaseSecondary.State -ne 'Existing' ) {
        Write-LocalWarning -Message "State of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.State)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is existing"
    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    # With automatic seeding, .JoinAvailablityGroup() is not needed, just wait for the magic to happen
    while ( -not $smoAvailabilityDatabaseSecondary.IsJoined ) {
        $seedingStats = $sqlInstancePrimary.Query("SELECT * FROM sys.dm_hadr_physical_seeding_stats")
        if ( $seedingStats -eq $null ) {
            Write-LocalWarning -Message "No seeding stats available"
        } else {
            Write-LocalWarning -Message "Seeding stats: internal_state_desc: $($seedingStats.internal_state_desc)  transferred_size_bytes: $($seedingStats.transferred_size_bytes)  database_size_bytes: $($seedingStats.database_size_bytes)  percent complete: $($seedingStats.transferred_size_bytes * 100.0 / $seedingStats.database_size_bytes)  estimate_time_complete_utc: $($seedingStats.estimate_time_complete_utc)"
            if ( $seedingStats.failure_message.ToString() -ne '' ) {
                Write-LocalWarning -Message "Seeding stats: failure_message: $($seedingStats.failure_message)"
            }
        }
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is joined"
    $seedingStats = $sqlInstancePrimary.Query("SELECT * FROM sys.dm_hadr_physical_seeding_stats")
    if ( $seedingStats -eq $null ) {
        Write-LocalWarning -Message "No seeding stats available"
    } else {
        Write-LocalWarning -Message "Seeding stats: internal_state_desc: $($seedingStats.internal_state_desc)  transferred_size_bytes: $($seedingStats.transferred_size_bytes)  database_size_bytes: $($seedingStats.database_size_bytes)  percent complete: $($seedingStats.transferred_size_bytes * 100.0 / $seedingStats.database_size_bytes)  estimate_time_complete_utc: $($seedingStats.estimate_time_complete_utc)"
        if ( $seedingStats.failure_message.ToString() -ne '' ) {
            Write-LocalWarning -Message "Seeding stats: failure_message: $($seedingStats.failure_message)"
        }
    }
    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    while ( $smoAvailabilityDatabaseSecondary.SynchronizationState -ne 'Synchronized' ) {
        Write-LocalWarning -Message "SynchronizationState of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.SynchronizationState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is synchronized"
    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    # Show the backup, that was used to transfer the data to the secondary:
    Get-DbaDbBackupHistory -SqlInstance $sqlInstancePrimary -Database AdventureWorks -AgCheck -IncludeCopyOnly -Since (Get-Date).AddHours(-1) | Format-Table

    # This one command would do all things in this block, but some more I don't like (at the moment):
    # Add-DbaAgDatabase -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName -Database AdventureWorks -SeedingMode Automatic

<# Output:

11:44:48.940: Starting building MyTestAg2019
11:44:48.940: Setting up monitoring
11:45:01.316: Setting up availability group
11:45:06.472: Granting GRANT CREATE ANY DATABASE on the primary replica
11:45:06.472: Granting GRANT CREATE ANY DATABASE on the secondary replica
11:45:06.628: Starting main tasks
11:45:06.644: Changing the seeding mode of all replicas on the primary replica
11:45:07.144: smoAvailabilityReplicas are configured
11:45:07.144: smoAvailabilityDatabasePrimary is ready
11:45:07.206: AvailabilityDatabase is created

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized


11:45:09.191: smoAvailabilityDatabaseSecondary is ready
11:45:09.191: smoAvailabilityDatabaseSecondary is existing

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
          False    False                     False       False Existing     NotSynchronizing


WARNING: 11:45:10.081: No seeding stats available
WARNING: 11:45:11.253: No seeding stats available
WARNING: 11:45:13.457: Seeding stats: internal_state_desc: ReadingAndSendingData  transferred_size_bytes: 52437504  database_size_bytes: 352313344  percent complete: 14.8837689213384  estimate_time_complete_utc: 09/01/2020 09:45:18
WARNING: 11:45:34.691: Seeding stats: internal_state_desc: WaitingForRestoreToFinish  transferred_size_bytes: 216361472  database_size_bytes: 352313344  percent complete: 61.4116597298114  estimate_time_complete_utc: 09/01/2020 09:45:47
11:45:37.550: smoAvailabilityDatabaseSecondary is joined
WARNING: 11:45:37.566: Seeding stats: internal_state_desc: Success  transferred_size_bytes: 216361472  database_size_bytes: 352313344  percent complete: 61.4116597298114  estimate_time_complete_utc: 09/01/2020 09:45:47

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized


11:45:37.566: smoAvailabilityDatabaseSecondary is synchronized

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized



SqlInstance  Database       Type TotalSize DeviceType     Start                   Duration End                    
-----------  --------       ---- --------- ----------     -----                   -------- ---                    
SRV1\SQL2019 AdventureWorks Full 206.33 MB Virtual Device 2020-09-01 11:45:12.000 00:00:20 2020-09-01 11:45:32.000

#>

} else {
    # How to do it per SQL?

    Write-LocalHost -Message "Changing the seeding mode of all replicas on the primary replica"
    $sql = "ALTER AVAILABILITY GROUP [$agName] MODIFY REPLICA ON '$($sqlInstancePrimary.DomainInstanceName)' WITH (SEEDING_MODE = $replicaSeedingMode)"
    $sqlInstancePrimary.Query($sql)
    $sql = "ALTER AVAILABILITY GROUP [$agName] MODIFY REPLICA ON '$($sqlInstanceSecondary.DomainInstanceName)' WITH (SEEDING_MODE = $replicaSeedingMode)"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP MODIFY REPLICA is executed"

    $sql = "ALTER AVAILABILITY GROUP [$agName] ADD DATABASE [AdventureWorks]"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP ADD DATABASE is executed"
}

# Wait for the monitoring to finish and then get it
Start-Sleep -Seconds 20
$agDbHealth2019 = $sqlInstancePrimary.Query($getHealthSql) 
$agDbHealth2019 += $sqlInstanceSecondary.Query($getHealthSql) 
$agDbHealth2019 = $agDbHealth2019 | Sort-Object -Property date

# $agDbHealth2019 | Out-GridView

$agDbHealth2019 | Where-Object -Property server -Match 'SRV1' | Select-Object -First 20 | Format-Table -Property date, primary_database_state_desc, primary_database_synchronization_state_desc, primary_database_synchronization_health_desc, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
$agDbHealth2019 | Where-Object -Property server -Match 'SRV1' | Where-Object -Property secondary_database_synchronization_state_desc -NE 'NOT SYNCHRONIZING' | Select-Object -First 20 | Format-Table -Property date, primary_database_state_desc, primary_database_synchronization_state_desc, primary_database_synchronization_health_desc, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    primary_database_state_desc primary_database_synchronization_state_desc primary_database_synchronization_health_desc secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_healt
                                                                                                                                                                                                                         h_desc                                  
----                    --------------------------- ------------------------------------------- -------------------------------------------- ----------------------------- --------------------------------------------- ----------------------------------------
2020-09-01T11:45:07.090 ONLINE                      NOT SYNCHRONIZING                           NOT_HEALTHY                                                                NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.170 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.273 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.353 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.387 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.417 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.477 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.507 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.537 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.573 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.607 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.637 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.667 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.697 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.740 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.770 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.803 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.840 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.870 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
2020-09-01T11:45:07.900 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    NOT SYNCHRONIZING                             NOT_HEALTHY                             
[...]
2020-09-01T11:45:37.047 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.107 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.137 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.167 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.197 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.230 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.263 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.293 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.323 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.360 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.397 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.433 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.470 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.500 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.540 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.597 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.640 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.690 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.720 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-09-01T11:45:37.750 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
#>

$agDbHealth2019 | Where-Object -Property server -Match 'SRV2' | Select-Object -First 20 | Format-Table -Property date, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_health_desc
----                    ----------------------------- --------------------------------------------- ----------------------------------------------
2020-09-01T11:45:34.543 RESTORING                     INITIALIZING                                  NOT_HEALTHY                                   
2020-09-01T11:45:35.260 RECOVERING                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                             
2020-09-01T11:45:37.110 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:37.600 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:39.120 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:40.357 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:40.927 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:41.580 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:41.830 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:42.133 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:42.610 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:43.143 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:43.213 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:43.530 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:43.937 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:44.440 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:44.750 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:45.397 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:45.733 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-09-01T11:45:45.900 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
#>
