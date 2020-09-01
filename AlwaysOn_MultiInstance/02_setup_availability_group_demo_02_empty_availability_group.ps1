<#
Script to build an empty availability group on every instance of SRV1 and SRV2
But step by step with only a little help from dbatools
And with the choice to run some parts as plain SQL

Run this script after: 02_setup_availability_group_demo_01_AgHadr_Endpoint_XESession.ps1

To update dbatools: Update-Module -Name dbatools 
To get the sql server error message: $Error[0].GetBaseException()
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
# Task: Create availability group with two replicas and no database
#######

# Here as well I will try to follow SSMS wizard and defaults from Microsoft documentation

# https://docs.microsoft.com/en-us/sql/t-sql/statements/create-availability-group-transact-sql

$agAutomatedBackupPreference = 'Secondary'                        # Default in CREATE AVAILABILITY GROUP and New-DbaAvailabilityGroup

$agFailureConditionLevelPS = 'OnCriticalServerErrors'
$agFailureConditionLevelSQL = 3
#[Microsoft.SqlServer.Management.Smo.AvailabilityGroupFailureConditionLevel]::OnServerDown                    # 1 in CREATE AVAILABILITY GROUP and default in New-DbaAvailabilityGroup
#[Microsoft.SqlServer.Management.Smo.AvailabilityGroupFailureConditionLevel]::OnServerUnresponsive            # 2 in CREATE AVAILABILITY GROUP
#[Microsoft.SqlServer.Management.Smo.AvailabilityGroupFailureConditionLevel]::OnCriticalServerErrors          # 3 and default in CREATE AVAILABILITY GROUP
#[Microsoft.SqlServer.Management.Smo.AvailabilityGroupFailureConditionLevel]::OnModerateServerErrors          # 4 in CREATE AVAILABILITY GROUP
#[Microsoft.SqlServer.Management.Smo.AvailabilityGroupFailureConditionLevel]::OnAnyQualifiedFailureCondition  # 5 in CREATE AVAILABILITY GROUP
$agHealthCheckTimeout = 30000                                     # Default in CREATE AVAILABILITY GROUP and New-DbaAvailabilityGroup
$agClusterType = 'Wsfc'                                           # Default in CREATE AVAILABILITY GROUP (as far as I see it)
#$agClusterType = 'External'                                      # Default in New-DbaAvailabilityGroup

$replicaAvailabilityModePS = 'SynchronousCommit'                  # Default in New-DbaAvailabilityGroup
$replicaAvailabilityModeSQL = 'SYNCHRONOUS_COMMIT' 
$replicaFailoverMode = 'Automatic'                                # Default in New-DbaAvailabilityGroup
$replicaSeedingMode = 'Manual'                                    # Default in CREATE AVAILABILITY GROUP and New-DbaAvailabilityGroup
$replicaBackupPriority = 50                                       # Default in New-DbaAvailabilityGroup and default in SSMS wizard
#$replicaConnectionModeInSecondaryRolePS = 'AllowAllConnections'  # Default in New-DbaAvailabilityGroup
$replicaConnectionModeInSecondaryRolePS = 'AllowNoConnections'    # Default in CREATE AVAILABILITY GROUP
$replicaConnectionModeInSecondaryRoleSQL = 'NO'                   # Default in CREATE AVAILABILITY GROUP
$replicaConnectionModeInPrimaryRolePS = 'AllowAllConnections'     # Default in CREATE AVAILABILITY GROUP and New-DbaAvailabilityGroup



$createMonitoringTableSql = "CREATE TABLE master.dbo.ag_health(
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
	[secondary_last_connect_error_description] [nvarchar](1024) NULL
)"

$insertMonitoringTableSql = "DECLARE @starttime AS datetime
WHILE 1=1
BEGIN
    INSERT INTO master.dbo.ag_health
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
      FROM sys.availability_groups ag
           JOIN sys.dm_hadr_availability_group_states ags ON ag.group_id = ags.group_id
           LEFT JOIN (select * from sys.dm_hadr_availability_replica_states WHERE role_desc = 'PRIMARY') arsp ON ag.group_id = arsp.group_id
           LEFT JOIN (select * from sys.dm_hadr_availability_replica_states WHERE role_desc = 'SECONDARY') arss ON ag.group_id = arss.group_id
    IF @@ROWCOUNT > 0 AND @starttime IS NULL 
        SET @starttime = getdate()
    IF DATEADD(SECOND, 10, @starttime) < GETDATE()
        BREAK
END"

$jobName = 'MonitorBuildingAvailabilityGroup'

$getHealthSql = "SELECT * FROM master.dbo.ag_health"



# I will use -Passthru with New-DbaAvailabilityGroup and Add-DbaAgReplica to only get well formed smo objects and not let them do to much "magic" in the background
# This is also a demo to prove that some of this "magic" is not necessary and can be deleted

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

Write-LocalHost -Message "Starting main tasks"
if ( $useDBAtools ) {
    if ( ($sqlInstancePrimary.VersionMajor -ge 14) -and ($agClusterType -eq 'Wsfc') ) {
        $sql = "GRANT ALTER ANY AVAILABILITY GROUP TO [NT AUTHORITY\SYSTEM]
                GRANT CONNECT SQL TO [NT AUTHORITY\SYSTEM]
                GRANT VIEW SERVER STATE TO [NT AUTHORITY\SYSTEM]"
        $sqlInstancePrimary.Query($sql)
        $sqlInstanceSecondary.Query($sql)
        Write-LocalHost -Message "GRANTS are set up"
    }

    $smoAvailabilityGroup = New-DbaAvailabilityGroup -Primary $sqlInstancePrimary -Secondary $sqlInstanceSecondary -Name $agName -ClusterType $agClusterType -AutomatedBackupPreference $agAutomatedBackupPreference -FailureConditionLevel $agFailureConditionLevelPS -HealthCheckTimeout $agHealthCheckTimeout -Passthru -Confirm:$false
    Write-LocalHost -Message "smoAvailabilityGroup is ready"

    $smoAvailabilityReplicaPrimary = $smoAvailabilityGroup | Add-DbaAgReplica -SqlInstance $sqlInstancePrimary -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
    $smoAvailabilityGroup.AvailabilityReplicas.Add($smoAvailabilityReplicaPrimary)
    Write-LocalHost -Message "smoAvailabilityReplicaPrimary is ready"

    $smoAvailabilityReplicaSecondary = $smoAvailabilityGroup | Add-DbaAgReplica -SqlInstance $sqlInstanceSecondary -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
    $smoAvailabilityGroup.AvailabilityReplicas.Add($smoAvailabilityReplicaSecondary)
    Write-LocalHost -Message "smoAvailabilityReplicaSecondary is ready"

    $smoAvailabilityGroup.Create()
    Write-LocalHost -Message "AvailabilityGroup is created"

	# https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
    while ( $smoAvailabilityGroup.State -ne 'Existing' ) {
        Write-LocalWarning -Message "State of AvailabilityGroup is still $($smoAvailabilityGroup.State)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityGroup.Refresh()
    }
	# https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.availabilityreplicaoperationalstate
    while ( $smoAvailabilityReplicaPrimary.OperationalState -ne 'Online' ) {
        Write-LocalWarning -Message "OperationalState of AvailabilityReplicaPrimary is still $($smoAvailabilityReplicaPrimary.OperationalState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityReplicaPrimary.Refresh()
    }
    $smoAvailabilityReplicaPrimary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State
    $smoAvailabilityReplicaSecondary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State

    $sqlInstanceSecondary.JoinAvailabilityGroup($agName)
    Write-LocalHost -Message "SecondaryReplica is joined"

	# https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.availabilityreplicaconnectionstate
    while ( $smoAvailabilityReplicaSecondary.ConnectionState -ne 'Connected' ) {
        Write-LocalWarning -Message "ConnectionState of AvailabilityReplicaSecondary is still $($smoAvailabilityReplicaSecondary.ConnectionState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityReplicaSecondary.Refresh()
    }
    $smoAvailabilityReplicaPrimary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State
    $smoAvailabilityReplicaSecondary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State

    # This one command would do all things in this block, but some more I don't like (at the moment):
    # New-DbaAvailabilityGroup -Primary $sqlInstancePrimary -Secondary $sqlInstanceSecondary -Name $agName -ClusterType $agClusterType -AutomatedBackupPreference $agAutomatedBackupPreference -FailureConditionLevel $agFailureConditionLevelPS -HealthCheckTimeout $agHealthCheckTimeout -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Confirm:$false

<# Output:

09:21:08.036: Starting building MyTestAg2014
09:21:08.068: Setting up monitoring
09:21:18.193: Starting main tasks
09:21:18.443: smoAvailabilityGroup is ready
09:21:19.615: smoAvailabilityReplicaPrimary is ready
09:21:20.380: smoAvailabilityReplicaSecondary is ready
09:21:21.442: AvailabilityGroup is created

ConnectionState                JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
---------------                --------- ----------- ---------------- ------------------- --------------------------    -----
      Connected JoinedStandaloneInstance      Online           Online             Unknown           NotSynchronizing Existing



ConnectionState JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
--------------- --------- ----------- ---------------- ------------------- --------------------------    -----
   Disconnected NotJoined      Online          Unknown             Unknown           NotSynchronizing Existing


09:21:22.146: SecondaryReplica is joined
WARNING: 09:21:22.161: ConnectionState of AvailabilityReplicaSecondary is still Disconnected
WARNING: 09:21:22.427: ConnectionState of AvailabilityReplicaSecondary is still Disconnected

ConnectionState                JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
---------------                --------- ----------- ---------------- ------------------- --------------------------    -----
      Connected JoinedStandaloneInstance      Online           Online             Unknown           NotSynchronizing Existing



ConnectionState                JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
---------------                --------- ----------- ---------------- ------------------- --------------------------    -----
      Connected JoinedStandaloneInstance      Online          Unknown             Unknown           NotSynchronizing Existing

#>

} else {
    # How to do it per SQL?

    $replicaNamePrimary = $sqlInstancePrimary.DomainInstanceName      # SRV1\SQL2014
    $replicaNameSecondary = $sqlInstanceSecondary.DomainInstanceName  # SRV2\SQL2014

    $endpointUrlPrimary = (Get-DbaEndpoint -SqlInstance $sqlInstancePrimary -Type DatabaseMirroring).Fqdn      # TCP://srv1.Company.Pri:5022
    $endpointUrlSecondary = (Get-DbaEndpoint -SqlInstance $sqlInstanceSecondary -Type DatabaseMirroring).Fqdn  # TCP://srv2.Company.Pri:5022

    if ( ($sqlInstancePrimary.VersionMajor -ge 14) -and ($agClusterType -eq 'Wsfc') ) {
        $sql = "GRANT ALTER ANY AVAILABILITY GROUP TO [NT AUTHORITY\SYSTEM]
                GRANT CONNECT SQL TO [NT AUTHORITY\SYSTEM]
                GRANT VIEW SERVER STATE TO [NT AUTHORITY\SYSTEM]"
        $sqlInstancePrimary.Query($sql)
        $sqlInstanceSecondary.Query($sql)
        Write-LocalHost -Message "GRANTS are set up"
    }

    $sql = "CREATE AVAILABILITY GROUP [$agName]
            WITH (AUTOMATED_BACKUP_PREFERENCE = $agAutomatedBackupPreference)
            FOR REPLICA ON 
            N'$replicaNamePrimary' WITH (ENDPOINT_URL = N'$endpointUrlPrimary', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityModeSQL, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL)),
	        N'$replicaNameSecondary' WITH (ENDPOINT_URL = N'$endpointUrlSecondary', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityModeSQL, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL))"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "CREATE AVAILABILITY GROUP is executed"

    $sql = "ALTER AVAILABILITY GROUP [$agName] JOIN"
    $sqlInstanceSecondary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP JOIN is executed"
}


<# What does the SSMS wizard do after that?

-- Wait for the replica to start communicating
begin try
declare @conn bit
declare @count int
declare @replica_id uniqueidentifier 
declare @group_id uniqueidentifier
set @conn = 0
set @count = 30 -- wait for 5 minutes 

if (serverproperty('IsHadrEnabled') = 1)
	and (isnull((select member_state from master.sys.dm_hadr_cluster_members where upper(member_name COLLATE Latin1_General_CI_AS) = upper(cast(serverproperty('ComputerNamePhysicalNetBIOS') as nvarchar(256)) COLLATE Latin1_General_CI_AS)), 0) <> 0)
	and (isnull((select state from master.sys.database_mirroring_endpoints), 1) = 0)
begin
    select @group_id = ags.group_id from master.sys.availability_groups as ags where name = N'MyTestAg'
	select @replica_id = replicas.replica_id from master.sys.availability_replicas as replicas where upper(replicas.replica_server_name COLLATE Latin1_General_CI_AS) = upper(@@SERVERNAME COLLATE Latin1_General_CI_AS) and group_id = @group_id
	while @conn <> 1 and @count > 0
	begin
		set @conn = isnull((select connected_state from master.sys.dm_hadr_availability_replica_states as states where states.replica_id = @replica_id), 1)
		if @conn = 1
		begin
			-- exit loop when the replica is connected, or if the query cannot find the replica status
			break
		end
		waitfor delay '00:00:10'
		set @count = @count - 1
	end
end
end try
begin catch
	-- If the wait loop fails, do not stop execution of the alter database statement
end catch

#>

# Wait for the monitoring to finish and then get it
Start-Sleep -Seconds 10
$agHealth2014 = $sqlInstancePrimary.Query($getHealthSql) 
$agHealth2014 += $sqlInstanceSecondary.Query($getHealthSql) 
$agHealth2014 = $agHealth2014 | Sort-Object -Property date

# $agHealth2014 | Out-GridView

$agHealth2014 | Where-Object -Property server -Match 'SRV1' | Select-Object -First 20 | Format-Table -Property date, ag_synchronization_health_desc, primary_operational_state_desc, primary_connected_state_desc, secondary_connected_state_desc, primary_synchronization_health_desc, secondary_synchronization_health_desc
<#
date                    ag_synchronization_health_desc primary_operational_state_desc primary_connected_state_desc secondary_connected_state_desc primary_synchronization_health_desc secondary_synchronization_health_desc
----                    ------------------------------ ------------------------------ ---------------------------- ------------------------------ ----------------------------------- -------------------------------------
2020-08-31T09:21:20.897 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:21:21.240 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:21:21.273 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:21:21.320 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:21:21.350 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:21:21.367 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:21:21.397 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:21:21.413 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:21.490 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:21.553 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:21.617 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:21.647 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:21.693 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:21.740 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:21.787 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:21.833 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:21.880 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:21.897 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:21.913 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:21.930 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
#>

$agHealth2014 | Where-Object -Property server -Match 'SRV2' | Select-Object -First 20 | Format-Table -Property date, ag_synchronization_health_desc, secondary_operational_state_desc, secondary_connected_state_desc, secondary_synchronization_health_desc
<#
date                    ag_synchronization_health_desc secondary_operational_state_desc secondary_connected_state_desc secondary_synchronization_health_desc
----                    ------------------------------ -------------------------------- ------------------------------ -------------------------------------
2020-08-31T09:21:22.130 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:21:22.210 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:21:22.333 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:22.397 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:22.430 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:22.460 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:22.490 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:22.520 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:22.537 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:22.570 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:23.147 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:23.820 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:24.210 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:24.930 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:25.303 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:25.350 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:25.397 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:25.430 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:25.443 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:25.473 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
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

Write-LocalHost -Message "Starting main tasks"
if ( $useDBAtools ) {
    if ( ($sqlInstancePrimary.VersionMajor -ge 14) -and ($agClusterType -eq 'Wsfc') ) {
        $sql = "GRANT ALTER ANY AVAILABILITY GROUP TO [NT AUTHORITY\SYSTEM]
                GRANT CONNECT SQL TO [NT AUTHORITY\SYSTEM]
                GRANT VIEW SERVER STATE TO [NT AUTHORITY\SYSTEM]"
        $sqlInstancePrimary.Query($sql)
        $sqlInstanceSecondary.Query($sql)
        Write-LocalHost -Message "GRANTS are set up"
    }

    $smoAvailabilityGroup = New-DbaAvailabilityGroup -Primary $sqlInstancePrimary -Secondary $sqlInstanceSecondary -Name $agName -ClusterType $agClusterType -AutomatedBackupPreference $agAutomatedBackupPreference -FailureConditionLevel $agFailureConditionLevelPS -HealthCheckTimeout $agHealthCheckTimeout -Passthru -Confirm:$false
    Write-LocalHost -Message "smoAvailabilityGroup is ready"

    $smoAvailabilityReplicaPrimary = $smoAvailabilityGroup | Add-DbaAgReplica -SqlInstance $sqlInstancePrimary -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
    $smoAvailabilityGroup.AvailabilityReplicas.Add($smoAvailabilityReplicaPrimary)
    Write-LocalHost -Message "smoAvailabilityReplicaPrimary is ready"

    $smoAvailabilityReplicaSecondary = $smoAvailabilityGroup | Add-DbaAgReplica -SqlInstance $sqlInstanceSecondary -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
    $smoAvailabilityGroup.AvailabilityReplicas.Add($smoAvailabilityReplicaSecondary)
    Write-LocalHost -Message "smoAvailabilityReplicaSecondary is ready"

    $smoAvailabilityGroup.Create()
    Write-LocalHost -Message "AvailabilityGroup is created"

<#
This happend only once, so I added the while loop:
$Error[0].GetBaseException():
Failed to join the availability replica to availability group 'MyTestAg2016' because the group is not online.  Either bring the availability group online, or drop and recreate it. Then retry the join operation.
Failed to join local availability replica to availability group 'MyTestAg2016'.  The operation encountered SQL Server error 41136 and has been rolled back.  Check the SQL Server error log for more details.  When the cause of the error has been resolved, 
retry the ALTER AVAILABILITY GROUP JOIN command.
#>
    while ( $smoAvailabilityGroup.State -ne 'Existing' ) {
        Write-LocalWarning -Message "State of AvailabilityGroup is still $($smoAvailabilityGroup.State)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityGroup.Refresh()
    }
    while ( $smoAvailabilityReplicaPrimary.OperationalState -ne 'Online' ) {
        Write-LocalWarning -Message "OperationalState of AvailabilityReplicaPrimary is still $($smoAvailabilityReplicaPrimary.OperationalState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityReplicaPrimary.Refresh()
    }
    $smoAvailabilityReplicaPrimary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State
    $smoAvailabilityReplicaSecondary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State

    $sqlInstanceSecondary.JoinAvailabilityGroup($agName)
    Write-LocalHost -Message "SecondaryReplica is joined"

    while ( $smoAvailabilityReplicaSecondary.ConnectionState -ne 'Connected' ) {
        Write-LocalWarning -Message "ConnectionState of AvailabilityReplicaSecondary is still $($smoAvailabilityReplicaSecondary.ConnectionState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityReplicaSecondary.Refresh()
    }
    $smoAvailabilityReplicaPrimary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State
    $smoAvailabilityReplicaSecondary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State

    # This one command would do all things in this block, but some more I don't like (at the moment):
    # New-DbaAvailabilityGroup -Primary $sqlInstancePrimary -Secondary $sqlInstanceSecondary -Name $agName -ClusterType $agClusterType -AutomatedBackupPreference $agAutomatedBackupPreference -FailureConditionLevel $agFailureConditionLevelPS -HealthCheckTimeout $agHealthCheckTimeout -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Confirm:$false

<# Output:

09:21:32.896: Starting building MyTestAg2016
09:21:32.896: Setting up monitoring
09:21:43.818: Starting main tasks
09:21:43.896: smoAvailabilityGroup is ready
09:21:46.411: smoAvailabilityReplicaPrimary is ready
09:21:48.708: smoAvailabilityReplicaSecondary is ready
09:21:49.880: AvailabilityGroup is created

ConnectionState                JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
---------------                --------- ----------- ---------------- ------------------- --------------------------    -----
      Connected JoinedStandaloneInstance      Online           Online             Unknown           NotSynchronizing Existing



ConnectionState JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
--------------- --------- ----------- ---------------- ------------------- --------------------------    -----
   Disconnected NotJoined      Online          Unknown             Unknown           NotSynchronizing Existing


09:21:51.350: SecondaryReplica is joined
WARNING: 09:21:51.350: ConnectionState of AvailabilityReplicaSecondary is still Disconnected
WARNING: 09:21:51.630: ConnectionState of AvailabilityReplicaSecondary is still Disconnected

ConnectionState                JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
---------------                --------- ----------- ---------------- ------------------- --------------------------    -----
      Connected JoinedStandaloneInstance      Online           Online             Unknown           NotSynchronizing Existing



ConnectionState                JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
---------------                --------- ----------- ---------------- ------------------- --------------------------    -----
      Connected JoinedStandaloneInstance      Online          Unknown             Unknown           NotSynchronizing Existing

#>

} else {
    # How to do it per SQL?

    $replicaNamePrimary = $sqlInstancePrimary.DomainInstanceName
    $replicaNameSecondary = $sqlInstanceSecondary.DomainInstanceName

    $endpointUrlPrimary = (Get-DbaEndpoint -SqlInstance $sqlInstancePrimary -Type DatabaseMirroring).Fqdn
    $endpointUrlSecondary = (Get-DbaEndpoint -SqlInstance $sqlInstanceSecondary -Type DatabaseMirroring).Fqdn

    if ( ($sqlInstancePrimary.VersionMajor -ge 14) -and ($agClusterType -eq 'Wsfc') ) {
        $sql = "GRANT ALTER ANY AVAILABILITY GROUP TO [NT AUTHORITY\SYSTEM]
                GRANT CONNECT SQL TO [NT AUTHORITY\SYSTEM]
                GRANT VIEW SERVER STATE TO [NT AUTHORITY\SYSTEM]"
        $sqlInstancePrimary.Query($sql)
        $sqlInstanceSecondary.Query($sql)
        Write-LocalHost -Message "GRANTS are set up"
    }

    $sql = "CREATE AVAILABILITY GROUP [$agName]
            WITH (AUTOMATED_BACKUP_PREFERENCE = $agAutomatedBackupPreference)
            FOR REPLICA ON 
            N'$replicaNamePrimary' WITH (ENDPOINT_URL = N'$endpointUrlPrimary', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityModeSQL, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL)),
	        N'$replicaNameSecondary' WITH (ENDPOINT_URL = N'$endpointUrlSecondary', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityModeSQL, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL))"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "CREATE AVAILABILITY GROUP is executed"

    $sql = "ALTER AVAILABILITY GROUP [$agName] JOIN"
    $sqlInstanceSecondary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP JOIN is executed"
}

# Wait for the monitoring to finish and then get it
Start-Sleep -Seconds 10
$agHealth2016 = $sqlInstancePrimary.Query($getHealthSql) 
$agHealth2016 += $sqlInstanceSecondary.Query($getHealthSql) 
$agHealth2016 = $agHealth2016 | Sort-Object -Property date

# $agHealth2016 | Out-GridView

$agHealth2016 | Where-Object -Property server -Match 'SRV1' | Select-Object -First 20 | Format-Table -Property date, ag_synchronization_health_desc, primary_operational_state_desc, primary_connected_state_desc, secondary_connected_state_desc, primary_synchronization_health_desc, secondary_synchronization_health_desc
<#
date                    ag_synchronization_health_desc primary_operational_state_desc primary_connected_state_desc secondary_connected_state_desc primary_synchronization_health_desc secondary_synchronization_health_desc
----                    ------------------------------ ------------------------------ ---------------------------- ------------------------------ ----------------------------------- -------------------------------------
2020-08-31T09:21:49.693 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:21:49.787 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:21:49.820 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:21:49.897 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.037 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.147 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.193 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.273 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.413 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.710 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.787 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.833 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.880 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.897 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.913 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.930 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.943 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.960 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:50.990 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:21:51.007 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
#>

$agHealth2016 | Where-Object -Property server -Match 'SRV2' | Select-Object -First 20 | Format-Table -Property date, ag_synchronization_health_desc, secondary_operational_state_desc, secondary_connected_state_desc, secondary_synchronization_health_desc
<#
date                    ag_synchronization_health_desc secondary_operational_state_desc secondary_connected_state_desc secondary_synchronization_health_desc
----                    ------------------------------ -------------------------------- ------------------------------ -------------------------------------
2020-08-31T09:21:51.310 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:21:51.467 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:21:51.513 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:21:51.560 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:21:51.623 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:51.780 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:52.123 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:52.483 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:52.857 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:53.247 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:53.687 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:53.810 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:53.937 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:53.983 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:54.043 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:54.107 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:54.233 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:54.373 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:54.390 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:21:54.420 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
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

Write-LocalHost -Message "Starting main tasks"
if ( $useDBAtools ) {
    if ( ($sqlInstancePrimary.VersionMajor -ge 14) -and ($agClusterType -eq 'Wsfc') ) {
        $sql = "GRANT ALTER ANY AVAILABILITY GROUP TO [NT AUTHORITY\SYSTEM]
                GRANT CONNECT SQL TO [NT AUTHORITY\SYSTEM]
                GRANT VIEW SERVER STATE TO [NT AUTHORITY\SYSTEM]"
        $sqlInstancePrimary.Query($sql)
        $sqlInstanceSecondary.Query($sql)
        Write-LocalHost -Message "GRANTS are set up"
    }

    $smoAvailabilityGroup = New-DbaAvailabilityGroup -Primary $sqlInstancePrimary -Secondary $sqlInstanceSecondary -Name $agName -ClusterType $agClusterType -AutomatedBackupPreference $agAutomatedBackupPreference -FailureConditionLevel $agFailureConditionLevelPS -HealthCheckTimeout $agHealthCheckTimeout -Passthru -Confirm:$false
    Write-LocalHost -Message "smoAvailabilityGroup is ready"

    $smoAvailabilityReplicaPrimary = $smoAvailabilityGroup | Add-DbaAgReplica -SqlInstance $sqlInstancePrimary -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
    $smoAvailabilityGroup.AvailabilityReplicas.Add($smoAvailabilityReplicaPrimary)
    Write-LocalHost -Message "smoAvailabilityReplicaPrimary is ready"

    $smoAvailabilityReplicaSecondary = $smoAvailabilityGroup | Add-DbaAgReplica -SqlInstance $sqlInstanceSecondary -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
    $smoAvailabilityGroup.AvailabilityReplicas.Add($smoAvailabilityReplicaSecondary)
    Write-LocalHost -Message "smoAvailabilityReplicaSecondary is ready"

    $smoAvailabilityGroup.Create()
    Write-LocalHost -Message "AvailabilityGroup is created"

    while ( $smoAvailabilityGroup.State -ne 'Existing' ) {
        Write-LocalWarning -Message "State of AvailabilityGroup is still $($smoAvailabilityGroup.State)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityGroup.Refresh()
    }
    while ( $smoAvailabilityReplicaPrimary.OperationalState -ne 'Online' ) {
        Write-LocalWarning -Message "OperationalState of AvailabilityReplicaPrimary is still $($smoAvailabilityReplicaPrimary.OperationalState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityReplicaPrimary.Refresh()
    }
    $smoAvailabilityReplicaPrimary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State
    $smoAvailabilityReplicaSecondary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State

    $sqlInstanceSecondary.JoinAvailabilityGroup($agName)
    Write-LocalHost -Message "SecondaryReplica is joined"

    while ( $smoAvailabilityReplicaSecondary.ConnectionState -ne 'Connected' ) {
        Write-LocalWarning -Message "ConnectionState of AvailabilityReplicaSecondary is still $($smoAvailabilityReplicaSecondary.ConnectionState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityReplicaSecondary.Refresh()
    }
    $smoAvailabilityReplicaPrimary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State
    $smoAvailabilityReplicaSecondary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State

    # This one command would do all things in this block, but some more I don't like (at the moment):
    # New-DbaAvailabilityGroup -Primary $sqlInstancePrimary -Secondary $sqlInstanceSecondary -Name $agName -ClusterType $agClusterType -AutomatedBackupPreference $agAutomatedBackupPreference -FailureConditionLevel $agFailureConditionLevelPS -HealthCheckTimeout $agHealthCheckTimeout -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Confirm:$false

<# Output:

09:22:02.068: Starting building MyTestAg2017
09:22:02.083: Setting up monitoring
09:22:16.630: Starting main tasks
09:22:16.989: GRANTS are set up
09:22:17.239: smoAvailabilityGroup is ready
09:22:19.474: smoAvailabilityReplicaPrimary is ready
09:22:20.005: smoAvailabilityReplicaSecondary is ready
09:22:21.271: AvailabilityGroup is created

ConnectionState                JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
---------------                --------- ----------- ---------------- ------------------- --------------------------    -----
      Connected JoinedStandaloneInstance      Online           Online             Unknown           NotSynchronizing Existing



ConnectionState JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
--------------- --------- ----------- ---------------- ------------------- --------------------------    -----
   Disconnected NotJoined      Online          Unknown             Unknown           NotSynchronizing Existing


09:22:22.224: SecondaryReplica is joined
WARNING: 09:22:22.224: ConnectionState of AvailabilityReplicaSecondary is still Disconnected
WARNING: 09:22:22.552: ConnectionState of AvailabilityReplicaSecondary is still Disconnected

ConnectionState                JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
---------------                --------- ----------- ---------------- ------------------- --------------------------    -----
      Connected JoinedStandaloneInstance      Online           Online             Unknown           NotSynchronizing Existing



ConnectionState                JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
---------------                --------- ----------- ---------------- ------------------- --------------------------    -----
      Connected JoinedStandaloneInstance      Online          Unknown             Unknown           NotSynchronizing Existing

#>

} else {
    # How to do it per SQL?

    $replicaNamePrimary = $sqlInstancePrimary.DomainInstanceName
    $replicaNameSecondary = $sqlInstanceSecondary.DomainInstanceName

    $endpointUrlPrimary = (Get-DbaEndpoint -SqlInstance $sqlInstancePrimary -Type DatabaseMirroring).Fqdn
    $endpointUrlSecondary = (Get-DbaEndpoint -SqlInstance $sqlInstanceSecondary -Type DatabaseMirroring).Fqdn

    if ( ($sqlInstancePrimary.VersionMajor -ge 14) -and ($agClusterType -eq 'Wsfc') ) {
        $sql = "GRANT ALTER ANY AVAILABILITY GROUP TO [NT AUTHORITY\SYSTEM]
                GRANT CONNECT SQL TO [NT AUTHORITY\SYSTEM]
                GRANT VIEW SERVER STATE TO [NT AUTHORITY\SYSTEM]"
        $sqlInstancePrimary.Query($sql)
        $sqlInstanceSecondary.Query($sql)
    }

    $sql = "CREATE AVAILABILITY GROUP [$agName]
            WITH (AUTOMATED_BACKUP_PREFERENCE = $agAutomatedBackupPreference)
            FOR REPLICA ON 
            N'$replicaNamePrimary' WITH (ENDPOINT_URL = N'$endpointUrlPrimary', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityModeSQL, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL)),
	        N'$replicaNameSecondary' WITH (ENDPOINT_URL = N'$endpointUrlSecondary', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityModeSQL, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL))"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "CREATE AVAILABILITY GROUP is executed"

    $sql = "ALTER AVAILABILITY GROUP [$agName] JOIN"
    $sqlInstanceSecondary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP JOIN is executed"
}

# Wait for the monitoring to finish and then get it
Start-Sleep -Seconds 10
$agHealth2017 = $sqlInstancePrimary.Query($getHealthSql) 
$agHealth2017 += $sqlInstanceSecondary.Query($getHealthSql) 
$agHealth2017 = $agHealth2017 | Sort-Object -Property date

# $agHealth2017 | Out-GridView

$agHealth2017 | Where-Object -Property server -Match 'SRV1' | Select-Object -First 20 | Format-Table -Property date, ag_synchronization_health_desc, primary_operational_state_desc, primary_connected_state_desc, secondary_connected_state_desc, primary_synchronization_health_desc, secondary_synchronization_health_desc
<#
date                    ag_synchronization_health_desc primary_operational_state_desc primary_connected_state_desc secondary_connected_state_desc primary_synchronization_health_desc secondary_synchronization_health_desc
----                    ------------------------------ ------------------------------ ---------------------------- ------------------------------ ----------------------------------- -------------------------------------
2020-08-31T09:22:21.100 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:22:21.180 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:22:21.193 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:22:21.210 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:22:21.240 NOT_HEALTHY                    PENDING                        CONNECTED                                                   NOT_HEALTHY                                                              
2020-08-31T09:22:21.367 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:21.490 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:21.630 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:21.710 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:21.833 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:21.930 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:21.990 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:22.037 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:22.070 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:22.100 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:22.147 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:22.193 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:22.240 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:22.287 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:22.320 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
#>

$agHealth2017 | Where-Object -Property server -Match 'SRV2' | Select-Object -First 20 | Format-Table -Property date, ag_synchronization_health_desc, secondary_operational_state_desc, secondary_connected_state_desc, secondary_synchronization_health_desc
<#
date                    ag_synchronization_health_desc secondary_operational_state_desc secondary_connected_state_desc secondary_synchronization_health_desc
----                    ------------------------------ -------------------------------- ------------------------------ -------------------------------------
2020-08-31T09:22:22.210 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:22:22.413 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:22:22.693 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:22.773 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:22.837 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:22.880 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:22.930 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:22.977 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:23.023 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:23.070 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:23.100 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:23.163 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:23.210 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:23.257 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:23.303 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:23.350 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:23.380 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:23.430 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:23.460 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:23.507 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
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

Write-LocalHost -Message "Starting main tasks"
if ( $useDBAtools ) {
    if ( ($sqlInstancePrimary.VersionMajor -ge 14) -and ($agClusterType -eq 'Wsfc') ) {
        $sql = "GRANT ALTER ANY AVAILABILITY GROUP TO [NT AUTHORITY\SYSTEM]
                GRANT CONNECT SQL TO [NT AUTHORITY\SYSTEM]
                GRANT VIEW SERVER STATE TO [NT AUTHORITY\SYSTEM]"
        $sqlInstancePrimary.Query($sql)
        $sqlInstanceSecondary.Query($sql)
        Write-LocalHost -Message "GRANTS are set up"
    }

    $smoAvailabilityGroup = New-DbaAvailabilityGroup -Primary $sqlInstancePrimary -Secondary $sqlInstanceSecondary -Name $agName -ClusterType $agClusterType -AutomatedBackupPreference $agAutomatedBackupPreference -FailureConditionLevel $agFailureConditionLevelPS -HealthCheckTimeout $agHealthCheckTimeout -Passthru -Confirm:$false
    Write-LocalHost -Message "smoAvailabilityGroup is ready"

    $smoAvailabilityReplicaPrimary = $smoAvailabilityGroup | Add-DbaAgReplica -SqlInstance $sqlInstancePrimary -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
    $smoAvailabilityGroup.AvailabilityReplicas.Add($smoAvailabilityReplicaPrimary)
    Write-LocalHost -Message "smoAvailabilityReplicaPrimary is ready"

    $smoAvailabilityReplicaSecondary = $smoAvailabilityGroup | Add-DbaAgReplica -SqlInstance $sqlInstanceSecondary -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
    $smoAvailabilityGroup.AvailabilityReplicas.Add($smoAvailabilityReplicaSecondary)
    Write-LocalHost -Message "smoAvailabilityReplicaSecondary is ready"

    $smoAvailabilityGroup.Create()
    Write-LocalHost -Message "AvailabilityGroup is created"

    while ( $smoAvailabilityGroup.State -ne 'Existing' ) {
        Write-LocalWarning -Message "State of AvailabilityGroup is still $($smoAvailabilityGroup.State)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityGroup.Refresh()
    }
    while ( $smoAvailabilityReplicaPrimary.OperationalState -ne 'Online' ) {
        Write-LocalWarning -Message "OperationalState of AvailabilityReplicaPrimary is still $($smoAvailabilityReplicaPrimary.OperationalState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityReplicaPrimary.Refresh()
    }
    $smoAvailabilityReplicaPrimary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State
    $smoAvailabilityReplicaSecondary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State

    $sqlInstanceSecondary.JoinAvailabilityGroup($agName)
    Write-LocalHost -Message "SecondaryReplica is joined"

    while ( $smoAvailabilityReplicaSecondary.ConnectionState -ne 'Connected' ) {
        Write-LocalWarning -Message "ConnectionState of AvailabilityReplicaSecondary is still $($smoAvailabilityReplicaSecondary.ConnectionState)"
        Start-Sleep -Milliseconds 100
        $smoAvailabilityReplicaSecondary.Refresh()
    }
    $smoAvailabilityReplicaPrimary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State
    $smoAvailabilityReplicaSecondary | Format-Table -Property ConnectionState, JoinState, MemberState, OperationalState, RollupRecoveryState, RollupSynchronizationState, State

    # This one command would do all things in this block, but some more I don't like (at the moment):
    # New-DbaAvailabilityGroup -Primary $sqlInstancePrimary -Secondary $sqlInstanceSecondary -Name $agName -ClusterType $agClusterType -AutomatedBackupPreference $agAutomatedBackupPreference -FailureConditionLevel $agFailureConditionLevelPS -HealthCheckTimeout $agHealthCheckTimeout -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Confirm:$false

<# Output:

09:22:33.083: Starting building MyTestAg2019
09:22:33.083: Setting up monitoring
09:22:44.302: Starting main tasks
09:22:44.818: GRANTS are set up
09:22:45.052: smoAvailabilityGroup is ready
09:22:47.271: smoAvailabilityReplicaPrimary is ready
09:22:49.521: smoAvailabilityReplicaSecondary is ready
09:22:50.568: AvailabilityGroup is created

ConnectionState                JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
---------------                --------- ----------- ---------------- ------------------- --------------------------    -----
      Connected JoinedStandaloneInstance      Online           Online             Unknown           NotSynchronizing Existing



ConnectionState JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
--------------- --------- ----------- ---------------- ------------------- --------------------------    -----
   Disconnected NotJoined      Online          Unknown             Unknown           NotSynchronizing Existing


09:22:52.146: SecondaryReplica is joined
WARNING: 09:22:52.146: ConnectionState of AvailabilityReplicaSecondary is still Disconnected
WARNING: 09:22:52.630: ConnectionState of AvailabilityReplicaSecondary is still Disconnected

ConnectionState                JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
---------------                --------- ----------- ---------------- ------------------- --------------------------    -----
      Connected JoinedStandaloneInstance      Online           Online             Unknown           NotSynchronizing Existing



ConnectionState                JoinState MemberState OperationalState RollupRecoveryState RollupSynchronizationState    State
---------------                --------- ----------- ---------------- ------------------- --------------------------    -----
      Connected JoinedStandaloneInstance      Online          Unknown             Unknown           NotSynchronizing Existing

#>

} else {
    # How to do it per SQL?

    $replicaNamePrimary = $sqlInstancePrimary.DomainInstanceName
    $replicaNameSecondary = $sqlInstanceSecondary.DomainInstanceName

    $endpointUrlPrimary = (Get-DbaEndpoint -SqlInstance $sqlInstancePrimary -Type DatabaseMirroring).Fqdn
    $endpointUrlSecondary = (Get-DbaEndpoint -SqlInstance $sqlInstanceSecondary -Type DatabaseMirroring).Fqdn

    if ( ($sqlInstancePrimary.VersionMajor -ge 14) -and ($agClusterType -eq 'Wsfc') ) {
        $sql = "GRANT ALTER ANY AVAILABILITY GROUP TO [NT AUTHORITY\SYSTEM]
                GRANT CONNECT SQL TO [NT AUTHORITY\SYSTEM]
                GRANT VIEW SERVER STATE TO [NT AUTHORITY\SYSTEM]"
        $sqlInstancePrimary.Query($sql)
        $sqlInstanceSecondary.Query($sql)
    }

    $sql = "CREATE AVAILABILITY GROUP [$agName]
            WITH (AUTOMATED_BACKUP_PREFERENCE = $agAutomatedBackupPreference)
            FOR REPLICA ON 
            N'$replicaNamePrimary' WITH (ENDPOINT_URL = N'$endpointUrlPrimary', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityModeSQL, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL)),
	        N'$replicaNameSecondary' WITH (ENDPOINT_URL = N'$endpointUrlSecondary', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityModeSQL, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL))"
    $sqlInstancePrimary.Query($sql)
    Write-LocalHost -Message "CREATE AVAILABILITY GROUP is executed"

    $sql = "ALTER AVAILABILITY GROUP [$agName] JOIN"
    $sqlInstanceSecondary.Query($sql)
    Write-LocalHost -Message "ALTER AVAILABILITY GROUP JOIN is executed"
}

# Wait for the monitoring to finish and then get it
Start-Sleep -Seconds 10
$agHealth2019 = $sqlInstancePrimary.Query($getHealthSql) 
$agHealth2019 += $sqlInstanceSecondary.Query($getHealthSql) 
$agHealth2019 = $agHealth2019 | Sort-Object -Property date

# $agHealth2019 | Out-GridView

$agHealth2019 | Where-Object -Property server -Match 'SRV1' | Select-Object -First 20 | Format-Table -Property date, ag_synchronization_health_desc, primary_operational_state_desc, primary_connected_state_desc, secondary_connected_state_desc, primary_synchronization_health_desc, secondary_synchronization_health_desc
<#
date                    ag_synchronization_health_desc primary_operational_state_desc primary_connected_state_desc secondary_connected_state_desc primary_synchronization_health_desc secondary_synchronization_health_desc
----                    ------------------------------ ------------------------------ ---------------------------- ------------------------------ ----------------------------------- -------------------------------------
2020-08-31T09:22:50.380 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:22:50.440 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:22:50.480 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:22:50.513 NOT_HEALTHY                                                                                                                                                                                        
2020-08-31T09:22:50.537 NOT_HEALTHY                    PENDING                        CONNECTED                                                   NOT_HEALTHY                                                              
2020-08-31T09:22:50.647 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:50.787 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:50.910 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:50.990 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:51.073 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:51.180 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:51.253 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:51.303 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:51.350 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:51.397 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:51.437 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:51.483 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:51.540 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:51.590 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
2020-08-31T09:22:51.640 NOT_HEALTHY                    ONLINE                         CONNECTED                    DISCONNECTED                   NOT_HEALTHY                         NOT_HEALTHY                          
#>

$agHealth2019 | Where-Object -Property server -Match 'SRV2' | Select-Object -First 20 | Format-Table -Property date, ag_synchronization_health_desc, secondary_operational_state_desc, secondary_connected_state_desc, secondary_synchronization_health_desc
<#
date                    ag_synchronization_health_desc secondary_operational_state_desc secondary_connected_state_desc secondary_synchronization_health_desc
----                    ------------------------------ -------------------------------- ------------------------------ -------------------------------------
2020-08-31T09:22:52.153 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:22:52.220 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:22:52.273 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:22:52.327 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:22:52.387 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:22:52.433 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:22:52.490 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:22:52.540 NOT_HEALTHY                    ONLINE                           DISCONNECTED                   NOT_HEALTHY                          
2020-08-31T09:22:52.583 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:52.647 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:52.703 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:52.763 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:52.820 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:52.870 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:52.920 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:52.970 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:53.023 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:53.070 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:53.120 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
2020-08-31T09:22:53.177 NOT_HEALTHY                    ONLINE                           CONNECTED                      NOT_HEALTHY                          
#>



# My personal summary: All the availability groups are there but NOT_HEALTHY. All the replicas are there and NOT_HEALTHY as well, but are CONNECTED.

