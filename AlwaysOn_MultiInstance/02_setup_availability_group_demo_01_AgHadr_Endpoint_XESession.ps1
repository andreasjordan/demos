<#
Script to prepare every instance of SRV1 and SRV2 to build an availability group
But step by step with only a little help from dbatools
And with the choice to run some parts as plain SQL

Run this script after: 01_setup_instances.ps1

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

if ( $useDBAtools ) {
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


} else {
    # How to do it per SQL?

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
}



#######
# Task: Configure and start the AlwaysOn_health extended event session
#######

# This is not done by the dbatools command New-DbaAvailabilityGroup, but it is done by the SSMS wizard - I will do it here

# https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-extended-events
# https://www.sqlservercentral.com/blogs/alwayson_health-extended-event-session
# https://www.mssqltips.com/sqlservertip/5287/monitoring-sql-server-availability-groups-with-alwayson-extended-events-health-session/

if ( $useDBAtools ) {
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

} else {
    # How to do it per SQL?

    foreach ( $instance in $sqlInstanceAll ) {
        $instance.Query("ALTER EVENT SESSION [AlwaysOn_health] ON SERVER WITH (STARTUP_STATE = ON)")
        $instance.Query("ALTER EVENT SESSION [AlwaysOn_health] ON SERVER STATE = START")
    }
}

