<#
Script to build an availability group on every instance of SRV1 and SRV2
But step by step with only a little help from dbatools
And with some internal code and the SQL as info
#>

$ErrorActionPreference = 'Stop'

Import-Module -Name dbatools

$sqlInstance2014 = Connect-DbaInstance -SqlInstance 'SRV1\SQL2014', 'SRV2\SQL2014'
$sqlInstance2016 = Connect-DbaInstance -SqlInstance 'SRV1\SQL2016', 'SRV2\SQL2016'
$sqlInstance2017 = Connect-DbaInstance -SqlInstance 'SRV1\SQL2017', 'SRV2\SQL2017'
$sqlInstance2019 = Connect-DbaInstance -SqlInstance 'SRV1\SQL2019', 'SRV2\SQL2019'

$sqlInstanceAll = $sqlInstance2014 + $sqlInstance2016 + $sqlInstance2017 + $sqlInstance2019


# We start with the prerequisites:
# https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/prereqs-restrictions-recommendations-always-on-availability


#######
# Task: Enable HADR on every instance
#######

# https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/enable-and-disable-always-on-availability-groups-sql-server
# To enable HADR, we will use dbatools, that works perfect:
Enable-DbaAgHadr -SqlInstance $sqlInstanceAll -Force | Format-Table

<# Output:

ComputerName InstanceName SqlInstance  IsHadrEnabled
------------ ------------ -----------  -------------
SRV1         SQL2014      SRV1\SQL2014          True
SRV2         SQL2014      SRV2\SQL2014          True
SRV1         SQL2016      SRV1\SQL2016          True
SRV2         SQL2016      SRV2\SQL2016          True
SRV1         SQL2017      SRV1\SQL2017          True
SRV2         SQL2017      SRV2\SQL2017          True
SRV1         SQL2019      SRV1\SQL2019          True
SRV2         SQL2019      SRV2\SQL2019          True

#>

<# What does Enable-DbaAgHadr do?

$sqlInstance = Connect-DbaInstance -SqlInstance 'SRV1\SQL2014'
$computerName = $sqlInstance.ComputerName
$instanceName = $sqlInstance.InstanceName
$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $computerName
$null = $wmi.Initialize()
$sqlService = $wmi.Services | Where-Object DisplayName -EQ "SQL Server ($instanceName)"
$sqlService.ChangeHadrServiceSetting(1)
Invoke-Command -ComputerName $computerName -ScriptBlock { Restart-Service -DisplayName "SQL Server ($using:instanceName)" -Force }

#>

# There is no way to do this with SQL - only with Configuration Manager


# Now we can create the availability groups

# The wizard in SSMS can only create an availability group with one or more databases, but I will show here that we can build an empty availability group.
# It will not be in healthy state untill we ad a database, but that's ok for me.

# Here is the documentation for all the following steps for those who like to do it with SQL:
# https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/create-an-availability-group-transact-sql

# I will create all the endpoints in advance. Because I need different ports and because I want to show it step by step.
# https://docs.microsoft.com/en-us/sql/t-sql/statements/create-endpoint-transact-sql

# Differences between SSMS wizard and dbatools:
# SSMS wizard uses "ENCRYPTION = REQUIRED", which is default to "CREATE ENDPOINT" and also used in the Microsoft documentation
# dbatools uses "-EndpointEncryption Supported" when using "New-DbaEndpoint" inside of "Add-DbaAgReplica"
# I will use "ENCRYPTION = REQUIRED" to follow the SSMS wizard

# The service account is the same in all instances of the lab, so I have this fixed:
$serviceAccount = 'COMPANY\SQLServer'


#######
# Task: Create the endpoints and grant permissions to the service account
#######

New-DbaEndpoint -SqlInstance $sqlInstance2014 -Name hadr_endpoint -Type DatabaseMirroring -Protocol Tcp -Role All -EndpointEncryption Required -EncryptionAlgorithm Aes -Port 5022 | Start-DbaEndpoint | Format-Table
New-DbaEndpoint -SqlInstance $sqlInstance2016 -Name hadr_endpoint -Type DatabaseMirroring -Protocol Tcp -Role All -EndpointEncryption Required -EncryptionAlgorithm Aes -Port 5023 | Start-DbaEndpoint | Format-Table
New-DbaEndpoint -SqlInstance $sqlInstance2017 -Name hadr_endpoint -Type DatabaseMirroring -Protocol Tcp -Role All -EndpointEncryption Required -EncryptionAlgorithm Aes -Port 5024 | Start-DbaEndpoint | Format-Table
New-DbaEndpoint -SqlInstance $sqlInstance2019 -Name hadr_endpoint -Type DatabaseMirroring -Protocol Tcp -Role All -EndpointEncryption Required -EncryptionAlgorithm Aes -Port 5025 | Start-DbaEndpoint | Format-Table

New-DbaLogin -SqlInstance $sqlInstanceAll -Login $serviceAccount | Format-Table

Grant-DbaAgPermission -SqlInstance $sqlInstanceAll -Login $serviceAccount -Type Endpoint -Permission Connect | Format-Table

<# Output:

ComputerName InstanceName SqlInstance     ID Name          Port EndpointState      EndpointType Owner IsAdminEndpoint Fqdn                        IsSystemObject
------------ ------------ -----------     -- ----          ---- -------------      ------------ ----- --------------- ----                        --------------
SRV1         SQL2014      SRV1\SQL2014 65536 hadr_endpoint 5022       Started DatabaseMirroring sa              False TCP://srv1.Company.Pri:5022          False
SRV2         SQL2014      SRV2\SQL2014 65536 hadr_endpoint 5022       Started DatabaseMirroring sa              False TCP://srv2.Company.Pri:5022          False



ComputerName InstanceName SqlInstance     ID Name          Port EndpointState      EndpointType Owner IsAdminEndpoint Fqdn                        IsSystemObject
------------ ------------ -----------     -- ----          ---- -------------      ------------ ----- --------------- ----                        --------------
SRV1         SQL2016      SRV1\SQL2016 65536 hadr_endpoint 5023       Started DatabaseMirroring sa              False TCP://srv1.Company.Pri:5023          False
SRV2         SQL2016      SRV2\SQL2016 65536 hadr_endpoint 5023       Started DatabaseMirroring sa              False TCP://srv2.Company.Pri:5023          False



ComputerName InstanceName SqlInstance     ID Name          Port EndpointState      EndpointType Owner IsAdminEndpoint Fqdn                        IsSystemObject
------------ ------------ -----------     -- ----          ---- -------------      ------------ ----- --------------- ----                        --------------
SRV1         SQL2017      SRV1\SQL2017 65536 hadr_endpoint 5024       Started DatabaseMirroring sa              False TCP://srv1.Company.Pri:5024          False
SRV2         SQL2017      SRV2\SQL2017 65536 hadr_endpoint 5024       Started DatabaseMirroring sa              False TCP://SRV2.Company.Pri:5024          False



ComputerName InstanceName SqlInstance     ID Name          Port EndpointState      EndpointType Owner IsAdminEndpoint Fqdn                        IsSystemObject
------------ ------------ -----------     -- ----          ---- -------------      ------------ ----- --------------- ----                        --------------
SRV1         SQL2019      SRV1\SQL2019 65536 hadr_endpoint 5025       Started DatabaseMirroring sa              False TCP://srv1.Company.Pri:5025          False
SRV2         SQL2019      SRV2\SQL2019 65536 hadr_endpoint 5025       Started DatabaseMirroring sa              False TCP://SRV2.Company.Pri:5025          False



ComputerName InstanceName SqlInstance  Name                LoginType CreateDate           LastLogin            HasAccess IsLocked IsDisabled
------------ ------------ -----------  ----                --------- ----------           ---------            --------- -------- ----------
SRV1         SQL2014      SRV1\SQL2014 COMPANY\SQLServer WindowsUser 8/24/2020 7:17:45 PM 8/24/2020 6:57:45 PM      True               False
SRV2         SQL2014      SRV2\SQL2014 COMPANY\SQLServer WindowsUser 8/24/2020 7:17:47 PM 8/24/2020 6:58:11 PM      True               False
SRV1         SQL2016      SRV1\SQL2016 COMPANY\SQLServer WindowsUser 8/24/2020 7:17:47 PM 8/24/2020 6:58:38 PM      True               False
SRV2         SQL2016      SRV2\SQL2016 COMPANY\SQLServer WindowsUser 8/24/2020 7:17:49 PM 8/24/2020 6:58:53 PM      True               False
SRV1         SQL2017      SRV1\SQL2017 COMPANY\SQLServer WindowsUser 8/24/2020 7:17:49 PM 8/24/2020 6:59:12 PM      True               False
SRV2         SQL2017      SRV2\SQL2017 COMPANY\SQLServer WindowsUser 8/24/2020 7:17:51 PM 8/24/2020 6:59:26 PM      True               False
SRV1         SQL2019      SRV1\SQL2019 COMPANY\SQLServer WindowsUser 8/24/2020 7:17:51 PM 8/24/2020 6:59:45 PM      True               False
SRV2         SQL2019      SRV2\SQL2019 COMPANY\SQLServer WindowsUser 8/24/2020 7:17:53 PM 8/24/2020 7:00:05 PM      True               False



ComputerName InstanceName SqlInstance  Name              Permission Type  Status 
------------ ------------ -----------  ----              ---------- ----  ------ 
SRV1         SQL2014      SRV1\SQL2014 COMPANY\SQLServer Connect    Grant Success
SRV2         SQL2014      SRV2\SQL2014 COMPANY\SQLServer Connect    Grant Success
SRV1         SQL2016      SRV1\SQL2016 COMPANY\SQLServer Connect    Grant Success
SRV2         SQL2016      SRV2\SQL2016 COMPANY\SQLServer Connect    Grant Success
SRV1         SQL2017      SRV1\SQL2017 COMPANY\SQLServer Connect    Grant Success
SRV2         SQL2017      SRV2\SQL2017 COMPANY\SQLServer Connect    Grant Success
SRV1         SQL2019      SRV1\SQL2019 COMPANY\SQLServer Connect    Grant Success
SRV2         SQL2019      SRV2\SQL2019 COMPANY\SQLServer Connect    Grant Success

#>


<# How to do it per SQL?

foreach ( $instance in $sqlInstance2014 ) {
    $instance.Query("CREATE ENDPOINT [hadr_endpoint] STATE = STARTED AS TCP (LISTENER_PORT = 5022) FOR DATA_MIRRORING (ROLE = ALL, ENCRYPTION = REQUIRED ALGORITHM AES)")
    $instance.Query("CREATE LOGIN [$serviceAccount] FROM WINDOWS")
    $instance.Query("GRANT CONNECT ON ENDPOINT::[hadr_endpoint] TO [$serviceAccount]")
}

foreach ( $instance in $sqlInstance2016 ) {
    $instance.Query("CREATE ENDPOINT [hadr_endpoint] STATE = STARTED AS TCP (LISTENER_PORT = 5023) FOR DATA_MIRRORING (ROLE = ALL, ENCRYPTION = REQUIRED ALGORITHM AES)")
    $instance.Query("CREATE LOGIN [$serviceAccount] FROM WINDOWS")
    $instance.Query("GRANT CONNECT ON ENDPOINT::[hadr_endpoint] TO [$serviceAccount]")
}

foreach ( $instance in $sqlInstance2017 ) {
    $instance.Query("CREATE ENDPOINT [hadr_endpoint] STATE = STARTED AS TCP (LISTENER_PORT = 5024) FOR DATA_MIRRORING (ROLE = ALL, ENCRYPTION = REQUIRED ALGORITHM AES)")
    $instance.Query("CREATE LOGIN [$serviceAccount] FROM WINDOWS")
    $instance.Query("GRANT CONNECT ON ENDPOINT::[hadr_endpoint] TO [$serviceAccount]")
}

foreach ( $instance in $sqlInstance2019 ) {
    $instance.Query("CREATE ENDPOINT [hadr_endpoint] STATE = STARTED AS TCP (LISTENER_PORT = 5025) FOR DATA_MIRRORING (ROLE = ALL, ENCRYPTION = REQUIRED ALGORITHM AES)")
    $instance.Query("CREATE LOGIN [$serviceAccount] FROM WINDOWS")
    $instance.Query("GRANT CONNECT ON ENDPOINT::[hadr_endpoint] TO [$serviceAccount]")
}

#>



#######
# Task: Configure and start the AlwaysOn_health extended event session
#######

# This is not done by the dbatools command New-DbaAvailabilityGroup, but it is done by the SSMS wizard - I will do it here

# https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-extended-events
# https://www.sqlservercentral.com/blogs/alwayson_health-extended-event-session
# https://www.mssqltips.com/sqlservertip/5287/monitoring-sql-server-availability-groups-with-alwayson-extended-events-health-session/

Get-DbaXESession -SqlInstance $sqlInstanceAll -Session AlwaysOn_health | ForEach-Object -Process { $_.AutoStart = $true ; $_.Alter() ; $_ | Start-DbaXESession } | Format-Table

<# Output:

ComputerName InstanceName SqlInstance  Name            Status  StartTime            AutoStart    State Targets               TargetFile                                                                            Events                                        
------------ ------------ -----------  ----            ------  ---------            ---------    ----- -------               ----------                                                                            ------                                        
SRV1         SQL2014      SRV1\SQL2014 AlwaysOn_health Running 8/24/2020 7:23:11 PM      True Existing {package0.event_file} {C:\Program Files\Microsoft SQL Server\MSSQL12.SQL2014\MSSQL\Log\AlwaysOn_health.xel} {sqlserver.alwayson_ddl_executed, sqlserver...
SRV2         SQL2014      SRV2\SQL2014 AlwaysOn_health Running 8/24/2020 7:23:14 PM      True Existing {package0.event_file} {C:\Program Files\Microsoft SQL Server\MSSQL12.SQL2014\MSSQL\Log\AlwaysOn_health.xel} {sqlserver.alwayson_ddl_executed, sqlserver...
SRV1         SQL2016      SRV1\SQL2016 AlwaysOn_health Running 8/24/2020 7:23:16 PM      True Existing {package0.event_file} {C:\Program Files\Microsoft SQL Server\MSSQL13.SQL2016\MSSQL\Log\AlwaysOn_health.xel} {sqlserver.alwayson_ddl_executed, sqlserver...
SRV2         SQL2016      SRV2\SQL2016 AlwaysOn_health Running 8/24/2020 7:23:24 PM      True Existing {package0.event_file} {C:\Program Files\Microsoft SQL Server\MSSQL13.SQL2016\MSSQL\Log\AlwaysOn_health.xel} {sqlserver.alwayson_ddl_executed, sqlserver...
SRV1         SQL2017      SRV1\SQL2017 AlwaysOn_health Running 8/24/2020 7:23:25 PM      True Existing {package0.event_file} {C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Log\AlwaysOn_health.xel} {sqlserver.alwayson_ddl_executed, sqlserver...
SRV2         SQL2017      SRV2\SQL2017 AlwaysOn_health Running 8/24/2020 7:23:50 PM      True Existing {package0.event_file} {C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Log\AlwaysOn_health.xel} {sqlserver.alwayson_ddl_executed, sqlserver...
SRV1         SQL2019      SRV1\SQL2019 AlwaysOn_health Running 8/24/2020 7:23:51 PM      True Existing {package0.event_file} {C:\Program Files\Microsoft SQL Server\MSSQL15.SQL2019\MSSQL\Log\AlwaysOn_health.xel} {sqlserver.alwayson_ddl_executed, sqlserver...
SRV2         SQL2019      SRV2\SQL2019 AlwaysOn_health Running 8/24/2020 7:23:53 PM      True Existing {package0.event_file} {C:\Program Files\Microsoft SQL Server\MSSQL15.SQL2019\MSSQL\Log\AlwaysOn_health.xel} {sqlserver.alwayson_ddl_executed, sqlserver...

#>


<# What does Get-DbaXESession do?

$smoServer = $sqlInstance2014[0]
$sqlConn = $smoServer.ConnectionContext.SqlConnectionObject
$sqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sqlConn
$xeStore = New-Object Microsoft.SqlServer.Management.XEvent.XEStore $sqlStoreConnection
$xeSession = $xeStore.sessions | Where-Object Name -EQ 'AlwaysOn_health'
$xeSession.AutoStart = $true
$xeSession.Alter()
$xeSession.Start()

#>


<# How to do it per SQL?

foreach ( $instance in $sqlInstanceAll ) {
    $instance.Query("ALTER EVENT SESSION [AlwaysOn_health] ON SERVER WITH (STARTUP_STATE = ON)")
    $instance.Query("ALTER EVENT SESSION [AlwaysOn_health] ON SERVER STATE = START")
}

#>



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

$replicaAvailabilityModePS = 'SynchronousCommit'                  # Default in New-DbaAvailabilityGroup
$replicaAvailabilityModeSQL = 'SYNCHRONOUS_COMMIT' 
$replicaFailoverMode = 'Automatic'                                # Default in New-DbaAvailabilityGroup
$replicaSeedingMode = 'Manual'                                    # Default in CREATE AVAILABILITY GROUP and New-DbaAvailabilityGroup
$replicaBackupPriority = 50                                       # Default in New-DbaAvailabilityGroup and default in SSMS wizard
#$replicaConnectionModeInSecondaryRolePS = 'AllowAllConnections'  # Default in New-DbaAvailabilityGroup
$replicaConnectionModeInSecondaryRolePS = 'AllowNoConnections'    # Default in CREATE AVAILABILITY GROUP
$replicaConnectionModeInSecondaryRoleSQL = 'NO'                   # Default in CREATE AVAILABILITY GROUP
$replicaConnectionModeInPrimaryRolePS = 'AllowAllConnections'     # Default in CREATE AVAILABILITY GROUP and New-DbaAvailabilityGroup

# Let the smo objects know, that we have enabled HADR:
$sqlInstanceAll | ForEach-Object { $_.Refresh() }  # to prevent: WARNING: [11:26:01][Get-DbaAvailabilityGroup] Availability Group (HADR) is not configured for the instance: SRV1\SQL2014.

# I will use -Passthru with New-DbaAvailabilityGroup and Add-DbaAgReplica to only get well formed smo objects and not let them do to much "magic" in the background
# This is also a demo to prove that some of this "magic" is not necessary and can be deleted

$agName = 'MyTestAg2014'

$smoAvailabilityGroup2014 = New-DbaAvailabilityGroup -Primary $sqlInstance2014[0] -Secondary $sqlInstance2014[1] -Name $agName -AutomatedBackupPreference $agAutomatedBackupPreference -FailureConditionLevel $agFailureConditionLevelPS -HealthCheckTimeout $agHealthCheckTimeout -Passthru -Confirm:$false

$smoAvailabilityReplicaPrimary = $smoAvailabilityGroup2014 | Add-DbaAgReplica -SqlInstance $sqlInstance2014[0] -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
$smoAvailabilityGroup2014.AvailabilityReplicas.Add($smoAvailabilityReplicaPrimary)

$smoAvailabilityReplicaSecondary = $smoAvailabilityGroup2014 | Add-DbaAgReplica -SqlInstance $sqlInstance2014[1] -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
$smoAvailabilityGroup2014.AvailabilityReplicas.Add($smoAvailabilityReplicaSecondary)

$smoAvailabilityGroup2014.Create()
$sqlInstance2014[1].JoinAvailabilityGroup($agName)


$agName = 'MyTestAg2016'

$smoAvailabilityGroup2016 = New-DbaAvailabilityGroup -Primary $sqlInstance2016[0] -Secondary $sqlInstance2016[1] -Name $agName -AutomatedBackupPreference $agAutomatedBackupPreference -FailureConditionLevel $agFailureConditionLevelPS -HealthCheckTimeout $agHealthCheckTimeout -Passthru -Confirm:$false

$smoAvailabilityReplicaPrimary = $smoAvailabilityGroup2016 | Add-DbaAgReplica -SqlInstance $sqlInstance2016[0] -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
$smoAvailabilityGroup2016.AvailabilityReplicas.Add($smoAvailabilityReplicaPrimary)

$smoAvailabilityReplicaSecondary = $smoAvailabilityGroup2016 | Add-DbaAgReplica -SqlInstance $sqlInstance2016[1] -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
$smoAvailabilityGroup2016.AvailabilityReplicas.Add($smoAvailabilityReplicaSecondary)

$smoAvailabilityGroup2016.Create()
$sqlInstance2016[1].JoinAvailabilityGroup($agName)


$agName = 'MyTestAg2017'

$sql = "GRANT ALTER ANY AVAILABILITY GROUP TO [NT AUTHORITY\SYSTEM]
        GRANT CONNECT SQL TO [NT AUTHORITY\SYSTEM]
        GRANT VIEW SERVER STATE TO [NT AUTHORITY\SYSTEM]"
$sqlInstance2017[0].Query($sql)
$sqlInstance2017[1].Query($sql)

$smoAvailabilityGroup2017 = New-DbaAvailabilityGroup -Primary $sqlInstance2017[0] -Secondary $sqlInstance2017[1] -Name $agName -AutomatedBackupPreference $agAutomatedBackupPreference -FailureConditionLevel $agFailureConditionLevelPS -HealthCheckTimeout $agHealthCheckTimeout -Passthru -Confirm:$false -ClusterType Wsfc

$smoAvailabilityReplicaPrimary = $smoAvailabilityGroup2017 | Add-DbaAgReplica -SqlInstance $sqlInstance2017[0] -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
$smoAvailabilityGroup2017.AvailabilityReplicas.Add($smoAvailabilityReplicaPrimary)

$smoAvailabilityReplicaSecondary = $smoAvailabilityGroup2017 | Add-DbaAgReplica -SqlInstance $sqlInstance2017[1] -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
$smoAvailabilityGroup2017.AvailabilityReplicas.Add($smoAvailabilityReplicaSecondary)

$smoAvailabilityGroup2017.Create()
$sqlInstance2017[1].JoinAvailabilityGroup($agName)  # TODO: Why does New-DbaAvailabilityGroup uses this: $server.Query("ALTER AVAILABILITY GROUP [$ag] JOIN WITH (CLUSTER_TYPE = $ClusterType)")


$agName = 'MyTestAg2019'

$sql = "GRANT ALTER ANY AVAILABILITY GROUP TO [NT AUTHORITY\SYSTEM]
        GRANT CONNECT SQL TO [NT AUTHORITY\SYSTEM]
        GRANT VIEW SERVER STATE TO [NT AUTHORITY\SYSTEM]"
$sqlInstance2019[0].Query($sql)
$sqlInstance2019[1].Query($sql)

$smoAvailabilityGroup2019 = New-DbaAvailabilityGroup -Primary $sqlInstance2019[0] -Secondary $sqlInstance2019[1] -Name $agName -AutomatedBackupPreference $agAutomatedBackupPreference -FailureConditionLevel $agFailureConditionLevelPS -HealthCheckTimeout $agHealthCheckTimeout -Passthru -Confirm:$false -ClusterType Wsfc

$smoAvailabilityReplicaPrimary = $smoAvailabilityGroup2019 | Add-DbaAgReplica -SqlInstance $sqlInstance2019[0] -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
$smoAvailabilityGroup2019.AvailabilityReplicas.Add($smoAvailabilityReplicaPrimary)

$smoAvailabilityReplicaSecondary = $smoAvailabilityGroup2019 | Add-DbaAgReplica -SqlInstance $sqlInstance2019[1] -AvailabilityMode $replicaAvailabilityModePS -FailoverMode $replicaFailoverMode -BackupPriority $replicaBackupPriority -ConnectionModeInPrimaryRole $replicaConnectionModeInPrimaryRolePS -ConnectionModeInSecondaryRole $replicaConnectionModeInSecondaryRolePS -SeedingMode $replicaSeedingMode -Passthru
$smoAvailabilityGroup2019.AvailabilityReplicas.Add($smoAvailabilityReplicaSecondary)

$smoAvailabilityGroup2019.Create()
$sqlInstance2019[1].JoinAvailabilityGroup($agName)  # TODO: Why does New-DbaAvailabilityGroup uses this: $server.Query("ALTER AVAILABILITY GROUP [$ag] JOIN WITH (CLUSTER_TYPE = $ClusterType)")


<# Output:

Sorry, there is no output. All commands are totally silent - if there is not error...

#>


<# How to do it per SQL?

$agName = 'MyTestAg2014'

$sql = "CREATE AVAILABILITY GROUP [$agName]
WITH (AUTOMATED_BACKUP_PREFERENCE = $agAutomatedBackupPreference)
FOR 
REPLICA ON 
    N'SRV1\SQL2014' WITH (ENDPOINT_URL = N'TCP://SRV1.Company.Pri:5022', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityModeSQL, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL)),
	N'SRV2\SQL2014' WITH (ENDPOINT_URL = N'TCP://SRV2.Company.Pri:5022', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityModeSQL, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL))"
$sqlInstance2014[0].Query($sql)

$sql = "ALTER AVAILABILITY GROUP [$agName] JOIN"
$sqlInstance2014[1].Query($sql)


$agName = 'MyTestAg2016'

$sql = "CREATE AVAILABILITY GROUP [$agName]
WITH (AUTOMATED_BACKUP_PREFERENCE = $agAutomatedBackupPreference)
FOR 
REPLICA ON 
    N'SRV1\SQL2016' WITH (ENDPOINT_URL = N'TCP://SRV1.Company.Pri:5023', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityMode, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL)),
	N'SRV2\SQL2016' WITH (ENDPOINT_URL = N'TCP://SRV2.Company.Pri:5023', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityMode, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL))"
$sqlInstance2016[0].Query($sql)

$sql = "ALTER AVAILABILITY GROUP [$agName] JOIN"
$sqlInstance2016[1].Query($sql)


$agName = 'MyTestAg2017'

$sql = "CREATE AVAILABILITY GROUP [$agName]
WITH (AUTOMATED_BACKUP_PREFERENCE = $agAutomatedBackupPreference)
FOR 
REPLICA ON 
    N'SRV1\SQL2017' WITH (ENDPOINT_URL = N'TCP://SRV1.Company.Pri:5024', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityMode, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL)),
	N'SRV2\SQL2017' WITH (ENDPOINT_URL = N'TCP://SRV2.Company.Pri:5024', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityMode, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL))"
$sqlInstance2017[0].Query($sql)

$sql = "ALTER AVAILABILITY GROUP [$agName] JOIN"
$sqlInstance2017[1].Query($sql)


$agName = 'MyTestAg2019'

$sql = "CREATE AVAILABILITY GROUP [$agName]
WITH (AUTOMATED_BACKUP_PREFERENCE = $agAutomatedBackupPreference)
FOR 
REPLICA ON 
    N'SRV1\SQL2019' WITH (ENDPOINT_URL = N'TCP://SRV1.Company.Pri:5025', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityMode, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL)),
	N'SRV2\SQL2019' WITH (ENDPOINT_URL = N'TCP://SRV2.Company.Pri:5025', FAILOVER_MODE = $replicaFailoverMode, AVAILABILITY_MODE = $replicaAvailabilityMode, BACKUP_PRIORITY = $replicaBackupPriority, SECONDARY_ROLE(ALLOW_CONNECTIONS = $replicaConnectionModeInSecondaryRoleSQL))"
$sqlInstance2019[0].Query($sql)

$sql = "ALTER AVAILABILITY GROUP [$agName] JOIN"
$sqlInstance2019[1].Query($sql)

#>


<# What does the SSMS wizard do after that? I just wait for some seconds, but a TODO is to script this in PowerShell...

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


# Checking the status of the availability groups:

$sqlInstance2014[0].Query("select * from sys.dm_hadr_availability_group_states")
$sqlInstance2014[0].Query("select * from sys.dm_hadr_availability_replica_states")  # wait for connected_state = 1 (CONNECTED)

$sqlInstance2016[0].Query("select * from sys.dm_hadr_availability_group_states")
$sqlInstance2016[0].Query("select * from sys.dm_hadr_availability_replica_states")  # wait for connected_state = 1 (CONNECTED)

$sqlInstance2017[0].Query("select * from sys.dm_hadr_availability_group_states")
$sqlInstance2017[0].Query("select * from sys.dm_hadr_availability_replica_states")  # wait for connected_state = 1 (CONNECTED)

$sqlInstance2019[0].Query("select * from sys.dm_hadr_availability_group_states")
$sqlInstance2019[0].Query("select * from sys.dm_hadr_availability_replica_states")  # wait for connected_state = 1 (CONNECTED)

<# Output:

group_id                       : ee5bb83e-352a-4f51-ba3c-633fe1664bec
primary_replica                : SRV1\SQL2014
primary_recovery_health        : 
primary_recovery_health_desc   : 
secondary_recovery_health      : 
secondary_recovery_health_desc : 
synchronization_health         : 0
synchronization_health_desc    : NOT_HEALTHY

replica_id                     : 636bd38c-97f9-4535-893d-507b3c23097a
group_id                       : ee5bb83e-352a-4f51-ba3c-633fe1664bec
is_local                       : True
role                           : 1
role_desc                      : PRIMARY
operational_state              : 2
operational_state_desc         : ONLINE
connected_state                : 1
connected_state_desc           : CONNECTED
recovery_health                : 
recovery_health_desc           : 
synchronization_health         : 0
synchronization_health_desc    : NOT_HEALTHY
last_connect_error_number      : 
last_connect_error_description : 
last_connect_error_timestamp   : 

replica_id                     : 8a718579-50c9-4854-b39e-9f544fe59afc
group_id                       : ee5bb83e-352a-4f51-ba3c-633fe1664bec
is_local                       : False
role                           : 2
role_desc                      : SECONDARY
operational_state              : 
operational_state_desc         : 
connected_state                : 1
connected_state_desc           : CONNECTED
recovery_health                : 
recovery_health_desc           : 
synchronization_health         : 0
synchronization_health_desc    : NOT_HEALTHY
last_connect_error_number      : 
last_connect_error_description : 
last_connect_error_timestamp   : 

group_id                       : d3bca60a-3938-4356-a551-da5b4f255555
primary_replica                : SRV1\SQL2016
primary_recovery_health        : 
primary_recovery_health_desc   : 
secondary_recovery_health      : 
secondary_recovery_health_desc : 
synchronization_health         : 0
synchronization_health_desc    : NOT_HEALTHY

replica_id                     : 3a789392-541a-4d6d-90cc-9e784714314d
group_id                       : d3bca60a-3938-4356-a551-da5b4f255555
is_local                       : True
role                           : 1
role_desc                      : PRIMARY
operational_state              : 2
operational_state_desc         : ONLINE
connected_state                : 1
connected_state_desc           : CONNECTED
recovery_health                : 
recovery_health_desc           : 
synchronization_health         : 0
synchronization_health_desc    : NOT_HEALTHY
last_connect_error_number      : 
last_connect_error_description : 
last_connect_error_timestamp   : 

replica_id                     : 3b62f7da-f4fa-42a2-bc60-59514e64eb28
group_id                       : d3bca60a-3938-4356-a551-da5b4f255555
is_local                       : False
role                           : 2
role_desc                      : SECONDARY
operational_state              : 
operational_state_desc         : 
connected_state                : 1
connected_state_desc           : CONNECTED
recovery_health                : 
recovery_health_desc           : 
synchronization_health         : 0
synchronization_health_desc    : NOT_HEALTHY
last_connect_error_number      : 
last_connect_error_description : 
last_connect_error_timestamp   : 

group_id                       : f85f2d3c-333d-4b38-8993-dd55d90b0e65
primary_replica                : SRV1\SQL2017
primary_recovery_health        : 
primary_recovery_health_desc   : 
secondary_recovery_health      : 
secondary_recovery_health_desc : 
synchronization_health         : 0
synchronization_health_desc    : NOT_HEALTHY

replica_id                     : bd9f89a9-2b0e-4fa7-861c-ae0115cc5e73
group_id                       : f85f2d3c-333d-4b38-8993-dd55d90b0e65
is_local                       : True
role                           : 1
role_desc                      : PRIMARY
operational_state              : 2
operational_state_desc         : ONLINE
connected_state                : 1
connected_state_desc           : CONNECTED
recovery_health                : 
recovery_health_desc           : 
synchronization_health         : 0
synchronization_health_desc    : NOT_HEALTHY
last_connect_error_number      : 
last_connect_error_description : 
last_connect_error_timestamp   : 
write_lease_remaining_ticks    : 9984

replica_id                     : f98bb6a1-b87e-4b6b-8d85-f5e23e324323
group_id                       : f85f2d3c-333d-4b38-8993-dd55d90b0e65
is_local                       : False
role                           : 2
role_desc                      : SECONDARY
operational_state              : 
operational_state_desc         : 
connected_state                : 1
connected_state_desc           : CONNECTED
recovery_health                : 
recovery_health_desc           : 
synchronization_health         : 0
synchronization_health_desc    : NOT_HEALTHY
last_connect_error_number      : 
last_connect_error_description : 
last_connect_error_timestamp   : 
write_lease_remaining_ticks    : 

group_id                       : 53b35ac1-502b-40fd-b8a6-6d136aadfc08
primary_replica                : SRV1\SQL2019
primary_recovery_health        : 
primary_recovery_health_desc   : 
secondary_recovery_health      : 
secondary_recovery_health_desc : 
synchronization_health         : 0
synchronization_health_desc    : NOT_HEALTHY

replica_id                                  : 9d03c765-4226-40ab-bcc0-76afb22d4628
group_id                                    : 53b35ac1-502b-40fd-b8a6-6d136aadfc08
is_local                                    : True
role                                        : 1
role_desc                                   : PRIMARY
operational_state                           : 2
operational_state_desc                      : ONLINE
connected_state                             : 1
connected_state_desc                        : CONNECTED
recovery_health                             : 
recovery_health_desc                        : 
synchronization_health                      : 0
synchronization_health_desc                 : NOT_HEALTHY
last_connect_error_number                   : 
last_connect_error_description              : 
last_connect_error_timestamp                : 
write_lease_remaining_ticks                 : 8594
current_configuration_commit_start_time_utc : 

replica_id                                  : b04ac38c-2012-4111-ac07-5a5e1254553e
group_id                                    : 53b35ac1-502b-40fd-b8a6-6d136aadfc08
is_local                                    : False
role                                        : 2
role_desc                                   : SECONDARY
operational_state                           : 
operational_state_desc                      : 
connected_state                             : 1
connected_state_desc                        : CONNECTED
recovery_health                             : 
recovery_health_desc                        : 
synchronization_health                      : 0
synchronization_health_desc                 : NOT_HEALTHY
last_connect_error_number                   : 
last_connect_error_description              : 
last_connect_error_timestamp                : 
write_lease_remaining_ticks                 : 
current_configuration_commit_start_time_utc : 


My personal summary: All the availability groups are there but NOT_HEALTHY. All the replicas are there and NOT_HEALTHY as well, but are CONNECTED.

#>



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



#######
# Task: Add the Database to the availability group
#######

$agName = 'MyTestAg2014'

$smoAvailabilityDatabase = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($smoAvailabilityGroup2014, 'AdventureWorks')
$smoAvailabilityDatabase.Create()

$smoReplicaDatabase = Get-DbaAgDatabase -SqlInstance 'SRV2\SQL2014' -Database AdventureWorks -AvailabilityGroup $agName   # I use 'SRV2\SQL2014' instead of $sqlInstance2014[1], because the latter is not up to date
$smoReplicaDatabase.JoinAvailablityGroup()


$agName = 'MyTestAg2016'

$smoAvailabilityDatabase = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($smoAvailabilityGroup2016, 'AdventureWorks')
$smoAvailabilityDatabase.Create()

$smoReplicaDatabase = Get-DbaAgDatabase -SqlInstance 'SRV2\SQL2016' -Database AdventureWorks -AvailabilityGroup $agName
$smoReplicaDatabase.JoinAvailablityGroup()


$agName = 'MyTestAg2017'

$smoAvailabilityDatabase = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($smoAvailabilityGroup2017, 'AdventureWorks')
$smoAvailabilityDatabase.Create()

$smoReplicaDatabase = Get-DbaAgDatabase -SqlInstance 'SRV2\SQL2017' -Database AdventureWorks -AvailabilityGroup $agName
$smoReplicaDatabase.JoinAvailablityGroup()


$agName = 'MyTestAg2019'

$smoAvailabilityDatabase = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($smoAvailabilityGroup2019, 'AdventureWorks')
$smoAvailabilityDatabase.Create()

$smoReplicaDatabase = Get-DbaAgDatabase -SqlInstance 'SRV2\SQL2019' -Database AdventureWorks -AvailabilityGroup $agName
$smoReplicaDatabase.JoinAvailablityGroup()


<# Output:

Sorry, there is no output. All commands are totally silent - if there is not error...

#>


<# How to do it per SQL?

$agName = 'MyTestAg2014'

$sql = "ALTER AVAILABILITY GROUP [$agName] ADD DATABASE [AdventureWorks]"
$sqlInstance2014[0].Query($sql)

$sql = "ALTER DATABASE [AdventureWorks] SET HADR AVAILABILITY GROUP = [$agName]"
$sqlInstance2014[1].Query($sql)


$agName = 'MyTestAg2016'

$sql = "ALTER AVAILABILITY GROUP [$agName] ADD DATABASE [AdventureWorks]"
$sqlInstance2016[0].Query($sql)

$sql = "ALTER DATABASE [AdventureWorks] SET HADR AVAILABILITY GROUP = [$agName]"
$sqlInstance2016[1].Query($sql)


$agName = 'MyTestAg2017'

$sql = "ALTER AVAILABILITY GROUP [$agName] ADD DATABASE [AdventureWorks]"
$sqlInstance2017[0].Query($sql)

$sql = "ALTER DATABASE [AdventureWorks] SET HADR AVAILABILITY GROUP = [$agName]"
$sqlInstance2017[1].Query($sql)


$agName = 'MyTestAg2019'

$sql = "ALTER AVAILABILITY GROUP [$agName] ADD DATABASE [AdventureWorks]"
$sqlInstance2019[0].Query($sql)

$sql = "ALTER DATABASE [AdventureWorks] SET HADR AVAILABILITY GROUP = [$agName]"
$sqlInstance2019[1].Query($sql)

#>


# Checking the result:

$sqlInstance2014[0].Query("select * from sys.dm_hadr_availability_group_states")
$sqlInstance2014[0].Query("select * from sys.dm_hadr_availability_replica_states")

$sqlInstance2016[0].Query("select * from sys.dm_hadr_availability_group_states")
$sqlInstance2016[0].Query("select * from sys.dm_hadr_availability_replica_states")

$sqlInstance2017[0].Query("select * from sys.dm_hadr_availability_group_states")
$sqlInstance2017[0].Query("select * from sys.dm_hadr_availability_replica_states")

$sqlInstance2019[0].Query("select * from sys.dm_hadr_availability_group_states")
$sqlInstance2019[0].Query("select * from sys.dm_hadr_availability_replica_states")

<# Output:



group_id                       : ee5bb83e-352a-4f51-ba3c-633fe1664bec
primary_replica                : SRV1\SQL2014
primary_recovery_health        : 1
primary_recovery_health_desc   : ONLINE
secondary_recovery_health      : 
secondary_recovery_health_desc : 
synchronization_health         : 2
synchronization_health_desc    : HEALTHY

replica_id                     : 636bd38c-97f9-4535-893d-507b3c23097a
group_id                       : ee5bb83e-352a-4f51-ba3c-633fe1664bec
is_local                       : True
role                           : 1
role_desc                      : PRIMARY
operational_state              : 2
operational_state_desc         : ONLINE
connected_state                : 1
connected_state_desc           : CONNECTED
recovery_health                : 1
recovery_health_desc           : ONLINE
synchronization_health         : 2
synchronization_health_desc    : HEALTHY
last_connect_error_number      : 
last_connect_error_description : 
last_connect_error_timestamp   : 

replica_id                     : 8a718579-50c9-4854-b39e-9f544fe59afc
group_id                       : ee5bb83e-352a-4f51-ba3c-633fe1664bec
is_local                       : False
role                           : 2
role_desc                      : SECONDARY
operational_state              : 
operational_state_desc         : 
connected_state                : 1
connected_state_desc           : CONNECTED
recovery_health                : 
recovery_health_desc           : 
synchronization_health         : 2
synchronization_health_desc    : HEALTHY
last_connect_error_number      : 
last_connect_error_description : 
last_connect_error_timestamp   : 

group_id                       : d3bca60a-3938-4356-a551-da5b4f255555
primary_replica                : SRV1\SQL2016
primary_recovery_health        : 1
primary_recovery_health_desc   : ONLINE
secondary_recovery_health      : 
secondary_recovery_health_desc : 
synchronization_health         : 2
synchronization_health_desc    : HEALTHY

replica_id                     : 3a789392-541a-4d6d-90cc-9e784714314d
group_id                       : d3bca60a-3938-4356-a551-da5b4f255555
is_local                       : True
role                           : 1
role_desc                      : PRIMARY
operational_state              : 2
operational_state_desc         : ONLINE
connected_state                : 1
connected_state_desc           : CONNECTED
recovery_health                : 1
recovery_health_desc           : ONLINE
synchronization_health         : 2
synchronization_health_desc    : HEALTHY
last_connect_error_number      : 
last_connect_error_description : 
last_connect_error_timestamp   : 

replica_id                     : 3b62f7da-f4fa-42a2-bc60-59514e64eb28
group_id                       : d3bca60a-3938-4356-a551-da5b4f255555
is_local                       : False
role                           : 2
role_desc                      : SECONDARY
operational_state              : 
operational_state_desc         : 
connected_state                : 1
connected_state_desc           : CONNECTED
recovery_health                : 
recovery_health_desc           : 
synchronization_health         : 2
synchronization_health_desc    : HEALTHY
last_connect_error_number      : 
last_connect_error_description : 
last_connect_error_timestamp   : 

group_id                       : f85f2d3c-333d-4b38-8993-dd55d90b0e65
primary_replica                : SRV1\SQL2017
primary_recovery_health        : 1
primary_recovery_health_desc   : ONLINE
secondary_recovery_health      : 
secondary_recovery_health_desc : 
synchronization_health         : 2
synchronization_health_desc    : HEALTHY

replica_id                     : bd9f89a9-2b0e-4fa7-861c-ae0115cc5e73
group_id                       : f85f2d3c-333d-4b38-8993-dd55d90b0e65
is_local                       : True
role                           : 1
role_desc                      : PRIMARY
operational_state              : 2
operational_state_desc         : ONLINE
connected_state                : 1
connected_state_desc           : CONNECTED
recovery_health                : 1
recovery_health_desc           : ONLINE
synchronization_health         : 2
synchronization_health_desc    : HEALTHY
last_connect_error_number      : 
last_connect_error_description : 
last_connect_error_timestamp   : 
write_lease_remaining_ticks    : 6297

replica_id                     : f98bb6a1-b87e-4b6b-8d85-f5e23e324323
group_id                       : f85f2d3c-333d-4b38-8993-dd55d90b0e65
is_local                       : False
role                           : 2
role_desc                      : SECONDARY
operational_state              : 
operational_state_desc         : 
connected_state                : 1
connected_state_desc           : CONNECTED
recovery_health                : 
recovery_health_desc           : 
synchronization_health         : 2
synchronization_health_desc    : HEALTHY
last_connect_error_number      : 
last_connect_error_description : 
last_connect_error_timestamp   : 
write_lease_remaining_ticks    : 

group_id                       : 53b35ac1-502b-40fd-b8a6-6d136aadfc08
primary_replica                : SRV1\SQL2019
primary_recovery_health        : 1
primary_recovery_health_desc   : ONLINE
secondary_recovery_health      : 
secondary_recovery_health_desc : 
synchronization_health         : 2
synchronization_health_desc    : HEALTHY

replica_id                                  : 9d03c765-4226-40ab-bcc0-76afb22d4628
group_id                                    : 53b35ac1-502b-40fd-b8a6-6d136aadfc08
is_local                                    : True
role                                        : 1
role_desc                                   : PRIMARY
operational_state                           : 2
operational_state_desc                      : ONLINE
connected_state                             : 1
connected_state_desc                        : CONNECTED
recovery_health                             : 1
recovery_health_desc                        : ONLINE
synchronization_health                      : 2
synchronization_health_desc                 : HEALTHY
last_connect_error_number                   : 
last_connect_error_description              : 
last_connect_error_timestamp                : 
write_lease_remaining_ticks                 : 6141
current_configuration_commit_start_time_utc : 

replica_id                                  : b04ac38c-2012-4111-ac07-5a5e1254553e
group_id                                    : 53b35ac1-502b-40fd-b8a6-6d136aadfc08
is_local                                    : False
role                                        : 2
role_desc                                   : SECONDARY
operational_state                           : 
operational_state_desc                      : 
connected_state                             : 1
connected_state_desc                        : CONNECTED
recovery_health                             : 
recovery_health_desc                        : 
synchronization_health                      : 2
synchronization_health_desc                 : HEALTHY
last_connect_error_number                   : 
last_connect_error_description              : 
last_connect_error_timestamp                : 
write_lease_remaining_ticks                 : 
current_configuration_commit_start_time_utc : 


My personal summary: All the availability groups and replicas HEALTHY.

#>


# Let's have a look at the databases at the secondary:

$sqlInstance2014[1].Query("select * from sys.dm_hadr_database_replica_states")
$sqlInstance2016[1].Query("select * from sys.dm_hadr_database_replica_states")
$sqlInstance2017[1].Query("select * from sys.dm_hadr_database_replica_states")
$sqlInstance2019[1].Query("select * from sys.dm_hadr_database_replica_states")

<# Output:

database_id                 : 5
group_id                    : ee5bb83e-352a-4f51-ba3c-633fe1664bec
replica_id                  : 8a718579-50c9-4854-b39e-9f544fe59afc
group_database_id           : 9c8644c0-ecd3-4d9e-936a-8584f0b0b0db
is_local                    : True
is_primary_replica          : False
synchronization_state       : 2
synchronization_state_desc  : SYNCHRONIZED
is_commit_participant       : False
synchronization_health      : 2
synchronization_health_desc : HEALTHY
database_state              : 0
database_state_desc         : ONLINE
is_suspended                : False
suspend_reason              : 
suspend_reason_desc         : 
recovery_lsn                : 45000000073600001
truncation_lsn              : 45000000068000037
last_sent_lsn               : 1
last_sent_time              : 8/24/2020 7:55:33 PM
last_received_lsn           : 45000000075200001
last_received_time          : 8/24/2020 7:55:33 PM
last_hardened_lsn           : 45000000076000001
last_hardened_time          : 8/24/2020 7:50:47 PM
last_redone_lsn             : 45000000075200001
last_redone_time            : 8/24/2020 7:44:57 PM
log_send_queue_size         : 0
log_send_rate               : 0
redo_queue_size             : 0
redo_rate                   : 13333
filestream_send_rate        : 0
end_of_log_lsn              : 45000000075200001
last_commit_lsn             : 45000000073600008
last_commit_time            : 8/24/2020 7:44:57 PM
low_water_mark_for_ghosts   : 

database_id                 : 5
group_id                    : d3bca60a-3938-4356-a551-da5b4f255555
replica_id                  : 3b62f7da-f4fa-42a2-bc60-59514e64eb28
group_database_id           : 26062e65-5811-4bf2-8a16-2acdc75709ae
is_local                    : True
is_primary_replica          : False
synchronization_state       : 2
synchronization_state_desc  : SYNCHRONIZED
is_commit_participant       : False
synchronization_health      : 2
synchronization_health_desc : HEALTHY
database_state              : 0
database_state_desc         : ONLINE
is_suspended                : False
suspend_reason              : 
suspend_reason_desc         : 
recovery_lsn                : 41000000035200001
truncation_lsn              : 41000000032800001
last_sent_lsn               : 1
last_sent_time              : 8/24/2020 7:55:33 PM
last_received_lsn           : 41000000038400001
last_received_time          : 8/24/2020 7:55:33 PM
last_hardened_lsn           : 41000000039200001
last_hardened_time          : 8/24/2020 7:51:09 PM
last_redone_lsn             : 41000000038400001
last_redone_time            : 8/24/2020 7:45:29 PM
log_send_queue_size         : 0
log_send_rate               : 36000
redo_queue_size             : 0
redo_rate                   : 813
filestream_send_rate        : 0
end_of_log_lsn              : 41000000038400001
last_commit_lsn             : 41000000035200008
last_commit_time            : 8/24/2020 7:45:29 PM
low_water_mark_for_ghosts   : 
secondary_lag_seconds       : 

database_id                 : 5
group_id                    : f85f2d3c-333d-4b38-8993-dd55d90b0e65
replica_id                  : f98bb6a1-b87e-4b6b-8d85-f5e23e324323
group_database_id           : 24ebf780-0594-4d97-9ea4-007cca9b75d8
is_local                    : True
is_primary_replica          : False
synchronization_state       : 2
synchronization_state_desc  : SYNCHRONIZED
is_commit_participant       : False
synchronization_health      : 2
synchronization_health_desc : HEALTHY
database_state              : 0
database_state_desc         : ONLINE
is_suspended                : False
suspend_reason              : 
suspend_reason_desc         : 
recovery_lsn                : 39000002259200001
truncation_lsn              : 39000002256800001
last_sent_lsn               : 1
last_sent_time              : 8/24/2020 7:55:33 PM
last_received_lsn           : 39000002262400001
last_received_time          : 8/24/2020 7:55:33 PM
last_hardened_lsn           : 39000002263200001
last_hardened_time          : 8/24/2020 7:51:12 PM
last_redone_lsn             : 39000002262400001
last_redone_time            : 8/24/2020 7:45:49 PM
log_send_queue_size         : 0
log_send_rate               : 0
redo_queue_size             : 0
redo_rate                   : 444
filestream_send_rate        : 0
end_of_log_lsn              : 39000002262400001
last_commit_lsn             : 39000002259200008
last_commit_time            : 8/24/2020 7:45:49 PM
low_water_mark_for_ghosts   : 
secondary_lag_seconds       : 

database_id                 : 5
group_id                    : 53b35ac1-502b-40fd-b8a6-6d136aadfc08
replica_id                  : b04ac38c-2012-4111-ac07-5a5e1254553e
group_database_id           : d2afea23-99b4-4c5e-a2d3-b3d16d2c1de3
is_local                    : True
is_primary_replica          : False
synchronization_state       : 2
synchronization_state_desc  : SYNCHRONIZED
is_commit_participant       : False
synchronization_health      : 2
synchronization_health_desc : HEALTHY
database_state              : 0
database_state_desc         : ONLINE
is_suspended                : False
suspend_reason              : 
suspend_reason_desc         : 
recovery_lsn                : 39000002495200001
truncation_lsn              : 39000002492800001
last_sent_lsn               : 1
last_sent_time              : 8/24/2020 7:55:33 PM
last_received_lsn           : 39000002498400001
last_received_time          : 8/24/2020 7:55:33 PM
last_hardened_lsn           : 39000002499200001
last_hardened_time          : 8/24/2020 7:51:02 PM
last_redone_lsn             : 39000002498400001
last_redone_time            : 8/24/2020 7:45:54 PM
log_send_queue_size         : 0
log_send_rate               : 0
redo_queue_size             : 0
redo_rate                   : 4400
filestream_send_rate        : 0
end_of_log_lsn              : 39000002498400001
last_commit_lsn             : 39000002495200008
last_commit_time            : 8/24/2020 7:45:54 PM
low_water_mark_for_ghosts   : 
secondary_lag_seconds       : 
quorum_commit_lsn           : 
quorum_commit_time          : 


My personal summary: All databases are SYNCHRONIZED, HEALTHY and ONLINE.

#>



# What are availability groups for? Failover!

# Let's do it this dbatools:
Get-DbaAvailabilityGroup -SqlInstance SRV2\SQL2014 | Invoke-DbaAgFailover -Confirm:$false
Get-DbaAvailabilityGroup -SqlInstance SRV2\SQL2016 | Invoke-DbaAgFailover -Confirm:$false
Get-DbaAvailabilityGroup -SqlInstance SRV2\SQL2017 | Invoke-DbaAgFailover -Confirm:$false
Get-DbaAvailabilityGroup -SqlInstance SRV2\SQL2019 | Invoke-DbaAgFailover -Confirm:$false

<# Output:

ComputerName               : SRV2
InstanceName               : SQL2014
SqlInstance                : SRV2\SQL2014
LocalReplicaRole           : Primary
AvailabilityGroup          : MyTestAg2014
PrimaryReplica             : SRV2\SQL2014
ClusterType                : 
DtcSupportEnabled          : 
AutomatedBackupPreference  : Secondary
AvailabilityReplicas       : {SRV1\SQL2014, SRV2\SQL2014}
AvailabilityDatabases      : {AdventureWorks}
AvailabilityGroupListeners : {}

ComputerName               : SRV2
InstanceName               : SQL2016
SqlInstance                : SRV2\SQL2016
LocalReplicaRole           : Primary
AvailabilityGroup          : MyTestAg2016
PrimaryReplica             : SRV2\SQL2016
ClusterType                : 
DtcSupportEnabled          : False
AutomatedBackupPreference  : Secondary
AvailabilityReplicas       : {SRV1\SQL2016, SRV2\SQL2016}
AvailabilityDatabases      : {AdventureWorks}
AvailabilityGroupListeners : {}

ComputerName               : SRV2
InstanceName               : SQL2017
SqlInstance                : SRV2\SQL2017
LocalReplicaRole           : Primary
AvailabilityGroup          : MyTestAg2017
PrimaryReplica             : SRV2\SQL2017
ClusterType                : Wsfc
DtcSupportEnabled          : False
AutomatedBackupPreference  : Secondary
AvailabilityReplicas       : {SRV1\SQL2017, SRV2\SQL2017}
AvailabilityDatabases      : {AdventureWorks}
AvailabilityGroupListeners : {}

ComputerName               : SRV2
InstanceName               : SQL2019
SqlInstance                : SRV2\SQL2019
LocalReplicaRole           : Primary
AvailabilityGroup          : MyTestAg2019
PrimaryReplica             : SRV2\SQL2019
ClusterType                : Wsfc
DtcSupportEnabled          : False
AutomatedBackupPreference  : Secondary
AvailabilityReplicas       : {SRV1\SQL2019, SRV2\SQL2019}
AvailabilityDatabases      : {AdventureWorks}
AvailabilityGroupListeners : {}

#>


# Is everything HEALTHY? Let's ask dbatools this time:

Get-DbaAgDatabase -SqlInstance 'SRV2\SQL2014' -Database AdventureWorks
Get-DbaAgDatabase -SqlInstance 'SRV2\SQL2016' -Database AdventureWorks
Get-DbaAgDatabase -SqlInstance 'SRV2\SQL2017' -Database AdventureWorks
Get-DbaAgDatabase -SqlInstance 'SRV2\SQL2019' -Database AdventureWorks

<# Output:

ComputerName         : SRV2
InstanceName         : SQL2014
SqlInstance          : SRV2\SQL2014
AvailabilityGroup    : MyTestAg2014
Replica              : SRV2
Name                 : AdventureWorks
SynchronizationState : Synchronized
IsFailoverReady      : True
IsJoined             : True
IsSuspended          : False

ComputerName         : SRV2
InstanceName         : SQL2016
SqlInstance          : SRV2\SQL2016
AvailabilityGroup    : MyTestAg2016
Replica              : SRV2
Name                 : AdventureWorks
SynchronizationState : Synchronized
IsFailoverReady      : True
IsJoined             : True
IsSuspended          : False

ComputerName         : SRV2
InstanceName         : SQL2017
SqlInstance          : SRV2\SQL2017
AvailabilityGroup    : MyTestAg2017
Replica              : SRV2
Name                 : AdventureWorks
SynchronizationState : Synchronized
IsFailoverReady      : True
IsJoined             : True
IsSuspended          : False

ComputerName         : SRV2
InstanceName         : SQL2019
SqlInstance          : SRV2\SQL2019
AvailabilityGroup    : MyTestAg2019
Replica              : SRV2
Name                 : AdventureWorks
SynchronizationState : Synchronized
IsFailoverReady      : True
IsJoined             : True
IsSuspended          : False

#>


# Ok, everything is up and running, so this demo is finished here...
