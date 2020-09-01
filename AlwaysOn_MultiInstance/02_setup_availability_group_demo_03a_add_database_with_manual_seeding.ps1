<#
Script to add a database to an empty availability group on every instance of SRV1 and SRV2 with manual seeding
But step by step with only a little help from dbatools
And with the choice to run some parts as plain SQL

Run this script after: 02_setup_availability_group_demo_02_empty_availability_group.ps1

To update dbatools: Update-Module -Name dbatools 
To get the sql server error message: $Error[0].GetBaseException()

TODO: Only wait for SynchronizationState = 'Synchronized', if $replicaAvailabilityMode = 'SynchronousCommit' (otherwise wait for 'Synchronizing')
#>

# You can comment this out to use SQL instead when possible
$useDBAtools = $true



$ErrorActionPreference = 'Stop'

Import-Module -Name dbatools -MinimumVersion 1.0.116

$sqlInstance2014 = Connect-DbaInstance -SqlInstance 'SRV1\SQL2014', 'SRV2\SQL2014'
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
# Task: Transfer the Database to the secondary
#######

# I use dbatools for that, because it's just super easy and perfect:

Backup-DbaDatabase -SqlInstance $sqlInstance2014[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Database | Restore-DbaDatabase -SqlInstance $sqlInstance2014[1] -NoRecovery | Out-Null
Backup-DbaDatabase -SqlInstance $sqlInstance2014[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Log | Restore-DbaDatabase -SqlInstance $sqlInstance2014[1] -NoRecovery -Continue | Out-Null

Backup-DbaDatabase -SqlInstance $sqlInstance2016[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Database | Restore-DbaDatabase -SqlInstance $sqlInstance2016[1] -NoRecovery | Out-Null
Backup-DbaDatabase -SqlInstance $sqlInstance2016[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Log | Restore-DbaDatabase -SqlInstance $sqlInstance2016[1] -NoRecovery -Continue | Out-Null

Backup-DbaDatabase -SqlInstance $sqlInstance2017[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Database | Restore-DbaDatabase -SqlInstance $sqlInstance2017[1] -NoRecovery | Out-Null
Backup-DbaDatabase -SqlInstance $sqlInstance2017[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Log | Restore-DbaDatabase -SqlInstance $sqlInstance2017[1] -NoRecovery -Continue | Out-Null

Backup-DbaDatabase -SqlInstance $sqlInstance2019[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Database | Restore-DbaDatabase -SqlInstance $sqlInstance2019[1] -NoRecovery | Out-Null
Backup-DbaDatabase -SqlInstance $sqlInstance2019[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Log | Restore-DbaDatabase -SqlInstance $sqlInstance2019[1] -NoRecovery -Continue | Out-Null


<# Output:

Sorry, I suppressed all output because it's just not very interesting.

#>


# To show that I can use the database while adding it to the availability group, I will insert some data:

$sqlInstance2014[0].Query("CREATE TABLE AdventureWorks.dbo.Test(Id int IDENTITY, Data char(5000) DEFAULT 'DATADATADATA')")
1..1000 | ForEach-Object -Process { $sqlInstance2014[0].Query("INSERT INTO AdventureWorks.dbo.Test DEFAULT VALUES") }

$sqlInstance2016[0].Query("CREATE TABLE AdventureWorks.dbo.Test(Id int IDENTITY, Data char(5000) DEFAULT 'DATADATADATA')")
1..1000 | ForEach-Object -Process { $sqlInstance2016[0].Query("INSERT INTO AdventureWorks.dbo.Test DEFAULT VALUES") }

$sqlInstance2017[0].Query("CREATE TABLE AdventureWorks.dbo.Test(Id int IDENTITY, Data char(5000) DEFAULT 'DATADATADATA')")
1..1000 | ForEach-Object -Process { $sqlInstance2017[0].Query("INSERT INTO AdventureWorks.dbo.Test DEFAULT VALUES") }

$sqlInstance2019[0].Query("CREATE TABLE AdventureWorks.dbo.Test(Id int IDENTITY, Data char(5000) DEFAULT 'DATADATADATA')")
1..1000 | ForEach-Object -Process { $sqlInstance2019[0].Query("INSERT INTO AdventureWorks.dbo.Test DEFAULT VALUES") }


# I can also take full backups:

$fullBackup2014 = Backup-DbaDatabase -SqlInstance $sqlInstance2014[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Database
$fullBackup2016 = Backup-DbaDatabase -SqlInstance $sqlInstance2016[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Database
$fullBackup2017 = Backup-DbaDatabase -SqlInstance $sqlInstance2017[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Database
$fullBackup2019 = Backup-DbaDatabase -SqlInstance $sqlInstance2019[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Database


# What I am not allowed to do: Restore these full backups to the secondary.

<# To get things failing, execute these lines:
$fullBackup2014 | Restore-DbaDatabase -SqlInstance $sqlInstance2014[1] -NoRecovery -WithReplace | Out-Null
$fullBackup2016 | Restore-DbaDatabase -SqlInstance $sqlInstance2016[1] -NoRecovery -WithReplace | Out-Null
$fullBackup2017 | Restore-DbaDatabase -SqlInstance $sqlInstance2017[1] -NoRecovery -WithReplace | Out-Null
$fullBackup2019 | Restore-DbaDatabase -SqlInstance $sqlInstance2019[1] -NoRecovery -WithReplace | Out-Null

# Command that fails: 
# $smoAvailabilityDatabaseSecondary.JoinAvailablityGroup()
# Error message:
# The mirror database, "AdventureWorks", has insufficient transaction log data to preserve the log backup chain of the principal database.  This may happen if a log backup from the principal database has not been taken or has not been restored on the mirror database.
#>


# What I am also not allowed to do: Take log backups.

<# To get things failing, execute these lines:
$logBackup2014 = Backup-DbaDatabase -SqlInstance $sqlInstance2014[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Log
$logBackup2016 = Backup-DbaDatabase -SqlInstance $sqlInstance2016[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Log
$logBackup2017 = Backup-DbaDatabase -SqlInstance $sqlInstance2017[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Log
$logBackup2019 = Backup-DbaDatabase -SqlInstance $sqlInstance2019[0] -Database AdventureWorks -Path \\WIN10\SQLServerBackups -Type Log

# Command that fails: 
# $smoAvailabilityDatabaseSecondary.JoinAvailablityGroup()
# Error message:
# The remote copy of database "AdventureWorks" has not been rolled forward to a point in time that is encompassed in the local copy of the database log.
#>


# Summary: 
# The last log backup must be restored on the secondary.
# So there has to be a log backup of the database.
# So there has to be a full backup of the databse.
# But if Add-DbaAgDatabase is doing the full and log backup and restore, there is not need to test for a previous backup. Testing for full recovery model is sufficient.



#######
# Task: Add the Database to the availability group
#######


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
    IF DATEADD(SECOND, 20, @starttime) < GETDATE()
        BREAK
END"

$jobName = 'MonitorAddingAvailabilityDatabase'

$getHealthSql = "SELECT * FROM master.dbo.ag_db_health"



$agName = 'MyTestAg2014'
$sqlInstancePrimary = $sqlInstance2014[0]
$sqlInstanceSecondary = $sqlInstance2014[1]

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

Write-LocalHost -Message "Starting main tasks"
if ( $useDBAtools ) {
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

    $smoAvailabilityDatabaseSecondary.JoinAvailablityGroup()

    while ( $smoAvailabilityDatabaseSecondary.IsJoined -ne $true ) {
        Write-LocalWarning -Message "IsJoined of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.IsJoined)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is joined"

    while ( $smoAvailabilityDatabaseSecondary.SynchronizationState -ne 'Synchronized' ) {
        Write-LocalWarning -Message "SynchronizationState of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.SynchronizationState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is synchronized"

    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    # This one command would do all things in this block, but some more I don't like (at the moment):
    # Add-DbaAgDatabase -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName -Database AdventureWorks -SharedPath \\WIN10\SQLServerBackups

<# Output:

17:40:18.859: Starting building MyTestAg2014
17:40:18.891: Setting up monitoring
17:40:27.282: Setting up availability group
17:40:32.532: Starting main tasks
17:40:32.532: smoAvailabilityDatabasePrimary is ready
17:40:32.578: AvailabilityDatabase is created

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized


17:40:32.875: smoAvailabilityDatabaseSecondary is ready
17:40:32.875: smoAvailabilityDatabaseSecondary is existing

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
          False    False                     False       False Existing     NotSynchronizing


17:40:44.094: smoAvailabilityDatabaseSecondary is joined
WARNING: 17:40:44.109: SynchronizationState of AvailabilityDatabase is still Initializing
17:40:49.219: smoAvailabilityDatabaseSecondary is synchronized

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized

#>

} else {
    # How to do it per SQL?

    $sql = "ALTER AVAILABILITY GROUP [$agName] ADD DATABASE [AdventureWorks]"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP ADD DATABASE is executed"

    $sql = "ALTER DATABASE [AdventureWorks] SET HADR AVAILABILITY GROUP = [$agName]"
    $sqlInstanceSecondary.Query($sql)
    Write-LocalHost -Message "ALTER DATABASE SET HADR is executed"
}

# Wait for the monitoring to finish and then get it
Start-Sleep -Seconds 20
$agDbHealth2014 = $sqlInstancePrimary.Query($getHealthSql) 
$agDbHealth2014 += $sqlInstanceSecondary.Query($getHealthSql) 
$agDbHealth2014 = $agDbHealth2014 | Sort-Object -Property date

# $agDbHealth2014 | Out-GridView

$agDbHealth2014 | Where-Object -Property server -Match 'SRV1' | Where-Object -Property secondary_database_synchronization_state_desc -NE 'NOT SYNCHRONIZING' | Select-Object -First 400 | Format-Table -Property date, primary_database_state_desc, primary_database_synchronization_state_desc, primary_database_synchronization_health_desc, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    primary_database_state_desc primary_database_synchronization_state_desc primary_database_synchronization_health_desc secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_healt
                                                                                                                                                                                                                         h_desc                                  
----                    --------------------------- ------------------------------------------- -------------------------------------------- ----------------------------- --------------------------------------------- ----------------------------------------
2020-08-31T17:40:44.080 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:44.190 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:44.203 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:44.220 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:44.233 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:44.250 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:44.267 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:44.280 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:44.297 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:44.313 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:44.330 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
[...]
2020-08-31T17:40:46.940 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:46.970 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:46.983 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:47.017 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:47.030 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:47.047 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:40:47.080 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:40:47.110 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:40:47.127 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:40:47.157 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:40:47.173 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:40:47.190 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:40:47.203 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:40:47.220 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:40:47.233 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
#>

$agDbHealth2014 | Where-Object -Property server -Match 'SRV2' | Select-Object -First 20 | Format-Table -Property date, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_health_desc
----                    ----------------------------- --------------------------------------------- ----------------------------------------------
2020-08-31T17:40:43.490 ONLINE                        NOT SYNCHRONIZING                             NOT_HEALTHY                                   
2020-08-31T17:40:43.723 ONLINE                        INITIALIZING                                  NOT_HEALTHY                                   
2020-08-31T17:40:44.100 ONLINE                        INITIALIZING                                  NOT_HEALTHY                                   
2020-08-31T17:40:48.113 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:40:49.037 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:40:49.693 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:40:51.147 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:40:51.410 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:40:52.647 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:40:54.100 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:40:54.613 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:40:55.630 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:40:57.083 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:40:58.363 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:40:58.613 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:00.113 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:01.503 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:01.707 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:01.740 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
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

Write-LocalHost -Message "Starting main tasks"
if ( $useDBAtools ) {
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

    $smoAvailabilityDatabaseSecondary.JoinAvailablityGroup()

    while ( $smoAvailabilityDatabaseSecondary.IsJoined -ne $true ) {
        Write-LocalWarning -Message "IsJoined of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.IsJoined)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is joined"

    while ( $smoAvailabilityDatabaseSecondary.SynchronizationState -ne 'Synchronized' ) {
        Write-LocalWarning -Message "SynchronizationState of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.SynchronizationState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is synchronized"

    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    # This one command would do all things in this block, but some more I don't like (at the moment):
    # Add-DbaAgDatabase -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName -Database AdventureWorks -SharedPath \\WIN10\SQLServerBackups

<# Output:

17:41:10.312: Starting building MyTestAg2016
17:41:10.312: Setting up monitoring
17:41:31.360: Setting up availability group
17:41:38.844: Starting main tasks
17:41:38.844: smoAvailabilityDatabasePrimary is ready
17:41:38.922: AvailabilityDatabase is created

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized


17:41:39.860: smoAvailabilityDatabaseSecondary is ready
17:41:39.860: smoAvailabilityDatabaseSecondary is existing

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
          False    False                     False       False Existing     NotSynchronizing


17:41:51.266: smoAvailabilityDatabaseSecondary is joined
WARNING: 17:41:51.266: SynchronizationState of AvailabilityDatabase is still Initializing
17:41:52.407: smoAvailabilityDatabaseSecondary is synchronized

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized

#>

} else {
    # How to do it per SQL?

    $sql = "ALTER AVAILABILITY GROUP [$agName] ADD DATABASE [AdventureWorks]"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP ADD DATABASE is executed"

    $sql = "ALTER DATABASE [AdventureWorks] SET HADR AVAILABILITY GROUP = [$agName]"
    $sqlInstanceSecondary.Query($sql)
    Write-LocalHost -Message "ALTER DATABASE SET HADR is executed"
}

# Wait for the monitoring to finish and then get it
Start-Sleep -Seconds 20
$agDbHealth2016 = $sqlInstancePrimary.Query($getHealthSql) 
$agDbHealth2016 += $sqlInstanceSecondary.Query($getHealthSql) 
$agDbHealth2016 = $agDbHealth2016 | Sort-Object -Property date

# $agDbHealth2016 | Out-GridView

$agDbHealth2016 | Where-Object -Property server -Match 'SRV1' | Where-Object -Property secondary_database_synchronization_state_desc -NE 'NOT SYNCHRONIZING' | Select-Object -First 20 | Format-Table -Property date, primary_database_state_desc, primary_database_synchronization_state_desc, primary_database_synchronization_health_desc, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    primary_database_state_desc primary_database_synchronization_state_desc primary_database_synchronization_health_desc secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_healt
                                                                                                                                                                                                                         h_desc                                  
----                    --------------------------- ------------------------------------------- -------------------------------------------- ----------------------------- --------------------------------------------- ----------------------------------------
2020-08-31T17:41:51.343 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:41:51.627 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:41:51.703 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:41:51.750 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:41:51.860 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:41:51.983 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.080 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.157 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.267 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.360 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.407 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.483 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.547 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.627 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.690 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.750 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.813 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.877 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:52.953 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:41:53.030 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
#>

$agDbHealth2016 | Where-Object -Property server -Match 'SRV2' | Select-Object -First 20 | Format-Table -Property date, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_health_desc
----                    ----------------------------- --------------------------------------------- ----------------------------------------------
2020-08-31T17:41:50.537 RESTORING                     NOT SYNCHRONIZING                             NOT_HEALTHY                                   
2020-08-31T17:41:50.740 RECOVERING                    INITIALIZING                                  NOT_HEALTHY                                   
2020-08-31T17:41:51.050 RECOVERING                    INITIALIZING                                  NOT_HEALTHY                                   
2020-08-31T17:41:51.350 RECOVERING                    INITIALIZING                                  NOT_HEALTHY                                   
2020-08-31T17:41:52.113 RECOVERING                    SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:52.397 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:52.490 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:52.600 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:52.707 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:52.833 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:52.957 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:53.083 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:53.193 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:53.287 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:53.427 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:53.537 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:53.660 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:53.753 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:53.880 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:41:53.990 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
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

Write-LocalHost -Message "Starting main tasks"
if ( $useDBAtools ) {
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

    $smoAvailabilityDatabaseSecondary.JoinAvailablityGroup()

    while ( $smoAvailabilityDatabaseSecondary.IsJoined -ne $true ) {
        Write-LocalWarning -Message "IsJoined of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.IsJoined)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is joined"

    while ( $smoAvailabilityDatabaseSecondary.SynchronizationState -ne 'Synchronized' ) {
        Write-LocalWarning -Message "SynchronizationState of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.SynchronizationState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is synchronized"

    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    # This one command would do all things in this block, but some more I don't like (at the moment):
    # Add-DbaAgDatabase -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName -Database AdventureWorks -SharedPath \\WIN10\SQLServerBackups

<# Output:
17:42:12.609: Starting building MyTestAg2017
17:42:12.625: Setting up monitoring
17:42:22.860: Setting up availability group
17:42:28.188: Starting main tasks
17:42:28.188: smoAvailabilityDatabasePrimary is ready
17:42:28.266: AvailabilityDatabase is created

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized


17:42:29.078: smoAvailabilityDatabaseSecondary is ready
17:42:29.078: smoAvailabilityDatabaseSecondary is existing

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
          False    False                     False       False Existing     NotSynchronizing


17:42:30.609: smoAvailabilityDatabaseSecondary is joined
WARNING: 17:42:30.625: SynchronizationState of AvailabilityDatabase is still Initializing
WARNING: 17:42:31.438: SynchronizationState of AvailabilityDatabase is still Initializing
17:42:32.047: smoAvailabilityDatabaseSecondary is synchronized

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized

#>

} else {
    # How to do it per SQL?

    $sql = "ALTER AVAILABILITY GROUP [$agName] ADD DATABASE [AdventureWorks]"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP ADD DATABASE is executed"

    $sql = "ALTER DATABASE [AdventureWorks] SET HADR AVAILABILITY GROUP = [$agName]"
    $sqlInstanceSecondary.Query($sql)
    Write-LocalHost -Message "ALTER DATABASE SET HADR is executed"
}

# Wait for the monitoring to finish and then get it
Start-Sleep -Seconds 20
$agDbHealth2017 = $sqlInstancePrimary.Query($getHealthSql) 
$agDbHealth2017 += $sqlInstanceSecondary.Query($getHealthSql) 
$agDbHealth2017 = $agDbHealth2017 | Sort-Object -Property date

# $agDbHealth2017 | Out-GridView

$agDbHealth2017 | Where-Object -Property server -Match 'SRV1' | Where-Object -Property secondary_database_synchronization_state_desc -NE 'NOT SYNCHRONIZING' | Select-Object -First 20 | Format-Table -Property date, primary_database_state_desc, primary_database_synchronization_state_desc, primary_database_synchronization_health_desc, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    primary_database_state_desc primary_database_synchronization_state_desc primary_database_synchronization_health_desc secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_healt
                                                                                                                                                                                                                         h_desc                                  
----                    --------------------------- ------------------------------------------- -------------------------------------------- ----------------------------- --------------------------------------------- ----------------------------------------
2020-08-31T17:42:30.580 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZING                                 PARTIALLY_HEALTHY                       
2020-08-31T17:42:30.797 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:30.907 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:31.017 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:31.140 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:31.237 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:31.377 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:31.517 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:31.657 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:31.780 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:31.907 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:32.017 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:32.127 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:32.220 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:32.267 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:32.313 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:32.377 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:32.500 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:32.657 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:42:32.830 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
#>

$agDbHealth2017 | Where-Object -Property server -Match 'SRV2' | Select-Object -First 20 | Format-Table -Property date, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_health_desc
----                    ----------------------------- --------------------------------------------- ----------------------------------------------
2020-08-31T17:42:29.600 RESTORING                     INITIALIZING                                  NOT_HEALTHY                                   
2020-08-31T17:42:29.943 RECOVERING                    INITIALIZING                                  NOT_HEALTHY                                   
2020-08-31T17:42:30.630 RECOVERING                    INITIALIZING                                  NOT_HEALTHY                                   
2020-08-31T17:42:31.223 RECOVERING                    INITIALIZING                                  NOT_HEALTHY                                   
2020-08-31T17:42:31.427 RECOVERING                    INITIALIZING                                  NOT_HEALTHY                                   
2020-08-31T17:42:31.677 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:31.910 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:32.113 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:32.300 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:32.457 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:32.630 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:32.817 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:32.990 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:33.160 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:33.333 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:33.490 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:33.677 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:33.833 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:34.020 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:42:34.207 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
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

Write-LocalHost -Message "Starting main tasks"
if ( $useDBAtools ) {
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

    $smoAvailabilityDatabaseSecondary.JoinAvailablityGroup()

    while ( $smoAvailabilityDatabaseSecondary.IsJoined -ne $true ) {
        Write-LocalWarning -Message "IsJoined of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.IsJoined)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is joined"

    while ( $smoAvailabilityDatabaseSecondary.SynchronizationState -ne 'Synchronized' ) {
        Write-LocalWarning -Message "SynchronizationState of AvailabilityDatabase is still $($smoAvailabilityDatabaseSecondary.SynchronizationState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityDatabaseSecondary.Refresh()
    }
    Write-LocalHost -Message "smoAvailabilityDatabaseSecondary is synchronized"

    $smoAvailabilityDatabaseSecondary | Format-Table -Property IsFailoverReady, IsJoined, IsPendingSecondarySuspend, IsSuspended, State, SynchronizationState

    # This one command would do all things in this block, but some more I don't like (at the moment):
    # Add-DbaAgDatabase -SqlInstance $sqlInstancePrimary -AvailabilityGroup $agName -Database AdventureWorks -SharedPath \\WIN10\SQLServerBackups

<# Output:

17:42:52.141: Starting building MyTestAg2019
17:42:52.156: Setting up monitoring
17:43:02.453: Setting up availability group
17:43:30.703: Starting main tasks
17:43:30.719: smoAvailabilityDatabasePrimary is ready
17:43:30.813: AvailabilityDatabase is created

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized


17:43:31.563: smoAvailabilityDatabaseSecondary is ready
17:43:31.563: smoAvailabilityDatabaseSecondary is existing

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
          False    False                     False       False Existing     NotSynchronizing


17:43:43.438: smoAvailabilityDatabaseSecondary is joined
WARNING: 17:43:43.453: SynchronizationState of AvailabilityDatabase is still Initializing
17:43:44.875: smoAvailabilityDatabaseSecondary is synchronized

IsFailoverReady IsJoined IsPendingSecondarySuspend IsSuspended    State SynchronizationState
--------------- -------- ------------------------- -----------    ----- --------------------
           True     True                     False       False Existing         Synchronized

#>

} else {
    # How to do it per SQL?

    $sql = "ALTER AVAILABILITY GROUP [$agName] ADD DATABASE [AdventureWorks]"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP ADD DATABASE is executed"

    $sql = "ALTER DATABASE [AdventureWorks] SET HADR AVAILABILITY GROUP = [$agName]"
    $sqlInstanceSecondary.Query($sql)
    Write-LocalHost -Message "ALTER DATABASE SET HADR is executed"
}

# Wait for the monitoring to finish and then get it
Start-Sleep -Seconds 20
$agDbHealth2019 = $sqlInstancePrimary.Query($getHealthSql) 
$agDbHealth2019 += $sqlInstanceSecondary.Query($getHealthSql) 
$agDbHealth2019 = $agDbHealth2019 | Sort-Object -Property date

# $agDbHealth2019 | Out-GridView

$agDbHealth2019 | Where-Object -Property server -Match 'SRV1' | Where-Object -Property secondary_database_synchronization_state_desc -NE 'NOT SYNCHRONIZING' | Select-Object -First 20 | Format-Table -Property date, primary_database_state_desc, primary_database_synchronization_state_desc, primary_database_synchronization_health_desc, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    primary_database_state_desc primary_database_synchronization_state_desc primary_database_synchronization_health_desc secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_healt
                                                                                                                                                                                                                         h_desc                                  
----                    --------------------------- ------------------------------------------- -------------------------------------------- ----------------------------- --------------------------------------------- ----------------------------------------
2020-08-31T17:43:43.247 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:44.450 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:44.510 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:44.580 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:44.670 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:44.817 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:45.057 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:45.283 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:45.403 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:45.727 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:45.790 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:45.850 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:45.900 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:45.957 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:46.023 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:46.180 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:46.433 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:46.677 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:46.880 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
2020-08-31T17:43:47.097 ONLINE                      SYNCHRONIZED                                HEALTHY                                                                    SYNCHRONIZED                                  HEALTHY                                 
#>

$agDbHealth2019 | Where-Object -Property server -Match 'SRV2' | Select-Object -First 20 | Format-Table -Property date, secondary_database_state_desc, secondary_database_synchronization_state_desc, secondary_database_synchronization_health_desc
<#
date                    secondary_database_state_desc secondary_database_synchronization_state_desc secondary_database_synchronization_health_desc
----                    ----------------------------- --------------------------------------------- ----------------------------------------------
2020-08-31T17:43:42.270 RESTORING                     NOT SYNCHRONIZING                             NOT_HEALTHY                                   
2020-08-31T17:43:42.510 RECOVERING                    NOT SYNCHRONIZING                             NOT_HEALTHY                                   
2020-08-31T17:43:42.927 RECOVERING                    INITIALIZING                                  NOT_HEALTHY                                   
2020-08-31T17:43:43.517 RECOVERING                    INITIALIZING                                  NOT_HEALTHY                                   
2020-08-31T17:43:44.397 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:44.790 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:45.010 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:45.183 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:45.340 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:45.543 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:45.720 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:45.917 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:46.077 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:46.213 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:46.453 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:46.607 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:46.770 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:46.920 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:47.120 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
2020-08-31T17:43:47.343 ONLINE                        SYNCHRONIZED                                  HEALTHY                                       
#>

