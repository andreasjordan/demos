# Tests for the new Connect-DbaInstance
Import-Module -Name .\dbatools.psm1 -Force

# Let's start again
# Let's start with the central part: Connection pooling

$instanceName = 'SRV1\SQL2016'

'Test 1:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceName
    $server.ConnectionContext.ProcessID
}

'Test 2:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceName
    $server.ConnectionContext.ApplicationName = 'Test'
    $server.ConnectionContext.ProcessID
}

'Test 3:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceName
    $server.ConnectionContext.NonPooledConnection = $false  # This doesn't help
    $server.ConnectionContext.ConnectionString = "Data Source=$instanceName;Integrated Security=True;MultipleActiveResultSets=False;Encrypt=False;TrustServerCertificate=False;Application Name=Test"
    $server.ConnectionContext.ProcessID
}

'Test 4:'
1..5 | ForEach-Object -Process {
    $connInfo = New-Object Microsoft.SqlServer.Management.Common.SqlConnectionInfo $instanceName
    $connInfo.ApplicationName = 'Test'
    $srvConn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $connInfo
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $srvConn
    $server.ConnectionContext.ProcessID
}


# There a five different objects, but only one connection:
$serverList[0].Equals($serverList[1])
$serverList[0].ConnectionContext.Equals($serverList[1].ConnectionContext)
$serverList[0].ConnectionContext.SqlConnectionObject.Equals($serverList[1].ConnectionContext.SqlConnectionObject)


$connInfo = New-Object Microsoft.SqlServer.Management.Common.SqlConnectionInfo $instanceName
$connInfo.AdditionalParameters = 'MultipleActiveResultSets=True'
$connInfo.ConnectionString


$srvConn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $connInfo
$server = New-Object Microsoft.SqlServer.Management.Smo.Server $srvConn
$server.ConnectionContext.ProcessID
$server.ConnectionContext.ConnectionString

$connInfo = New-Object Microsoft.SqlServer.Management.Common.SqlConnectionInfo $instanceName
$connInfo.ApplicationName = 'Test'
$connInfo.DatabaseName = 'tempdb'
$srvConn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $connInfo
$serverTempdb = New-Object Microsoft.SqlServer.Management.Smo.Server $srvConn
$serverTempdb.ConnectionContext.ProcessID

$server.ConnectionContext.SqlConnectionObject


# Test with Connect-DbaInstance
Import-Module -Name .\dbatools.psm1 -Force
Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true
$server = Connect-DbaInstance -SqlInstance $instanceName -Debug
$server.ConnectionContext.ProcessID
$server = Connect-DbaInstance -SqlInstance $instanceName -Database tempdb -Debug
$server.ConnectionContext.ProcessID


$instanceName = 'SRV1\SQL2016'

'Test 1:'
1..3 | ForEach-Object -Process {
    $server = Connect-DbaInstance -SqlInstance $instanceName
    $server.ConnectionContext.ProcessID
}

'Test 2:'
1..3 | ForEach-Object -Process {
    $server = Connect-DbaInstance -SqlInstance $instanceName
    $server.ConnectionContext.ProcessID
    $server = Connect-DbaInstance -SqlInstance $instanceName -Database tempdb
    $server.ConnectionContext.ProcessID
}

'Test 3:'
1..3 | ForEach-Object -Process {
    Invoke-DbaQuery -SqlInstance $instanceName -Query 'SELECT @@SPID' -As SingleValue
}

'Test 4:'
1..3 | ForEach-Object -Process {
    Invoke-DbaQuery -SqlInstance $instanceName -Query 'SELECT @@SPID' -As SingleValue
    Invoke-DbaQuery -SqlInstance $instanceName -Database tempdb -Query 'SELECT @@SPID' -As SingleValue
}

'Test 5:'
$server = Connect-DbaInstance -SqlInstance $instanceName
1..3 | ForEach-Object -Process {
    Invoke-DbaQuery -SqlInstance $server -Query 'SELECT @@SPID' -As SingleValue
    Invoke-DbaQuery -SqlInstance $server -Database tempdb -Query 'SELECT @@SPID' -As SingleValue
}



Invoke-DbaQuery -SqlInstance $instanceName -Query 'SELECT @@SPID' -As SingleValue -Debug

$server = Connect-DbaInstance -SqlInstance $instanceName
Invoke-DbaQuery -SqlInstance $server -Query 'SELECT @@SPID' -As SingleValue -Debug



$server = Connect-DbaInstance -SqlInstance '192.168.6.29\pstest,14331'

# I have a test instance as a named instance with a custom port.
# There are different ways to structure this string, but the type [DbaInstanceParameter] will parse them all and create the exact same custom object.
# As every input for the parameter -SqlInstance will be converted into this type, we will do it beforehand to be able to have a look at the different properties.
$instanceFullnameAsString = 'sqlix.ordix.de\pstest,14331'
"The instance fullname as string is: " + $instanceFullnameAsString
[DbaInstanceParameter]$instanceFromString = $instanceFullnameAsString
"The type of the property InputObject of the object [DbaInstanceParameter]instanceFromString is: " + $instanceFromString.InputObject.GetType().ToString()
"Some interesting properties of [DbaInstanceParameter]instanceFromString:"
$instanceFromString | Format-List -Property Type, FullName, FullSmoName, ComputerName, InstanceName, Port, IsLocalHost, IsConnectionString

# Let's use instance to get a server - that is the typical name of a smo server object of type [Microsoft.SqlServer.Management.Smo.Server]
# This is the official documentation of the class: https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.server
$serverFromString = Connect-DbaInstance -SqlInstance $instanceFromString
"The type of serverFromString is: " + $serverFromString.GetType().ToString()
"The property Name is equal to instanceFromString.FullSmoName: " + $serverFromString.Name
"Here are the custom properties, added by Connect-DbaInstance:"
$serverFromString | Format-List -Property IsAzure, ComputerName, DbaInstanceName, NetPort, ConnectedAs
"Here are some properties that show we have a connection:"
$serverFromString | Format-List -Property NetName, InstanceName, Product, VersionString

# When we use this object for the parameter -SqlInstance, it is just returned.
$serverDuplicate = Connect-DbaInstance -SqlInstance $serverFromString
if ($serverDuplicate.Equals($serverFromString)) { "Yes, they are equal" }

# If we derive a second server from the instance, we have a new server object.
$server2 = Connect-DbaInstance -SqlInstance $instanceFromString
if (-not $server2.Equals($serverFromString)) { "No, we are not equal" }

# What do we know about the connection? Let's have a look at the connection string
"The connection string of server ist: " + $serverFromString.ConnectionContext.ConnectionString

# We can take a connection string and convert it into the type [DbaInstanceParameter]
[DbaInstanceParameter]$instanceFromConnectionString = $serverFromString.ConnectionContext.ConnectionString
"The type of the property InputObject of the object [DbaInstanceParameter]instanceConnString is: " + $instanceFromConnectionString.InputObject.GetType().ToString()
"Some interesting properties of [DbaInstanceParameter]instanceConnString:"
$instanceFromConnectionString | Format-List -Property Type, FullName, FullSmoName, ComputerName, InstanceName, Port, IsLocalHost, IsConnectionString

# What is the difference?
if ($instanceFromConnectionString.IsConnectionString) { "The object knows it is a connection string" }
"Here is the string in the property InputObject: " + $instanceFromConnectionString.InputObject

# Can we get a server from that? Yes, we can.
$serverFromConnectionString = Connect-DbaInstance -SqlInstance $instanceFromConnectionString
"The type of serverFromConnectionString is: " + $serverFromConnectionString.GetType().ToString()
"The property Name is equal to instanceFromConnectionString.FullSmoName: " + $serverFromConnectionString.Name
"Here are the custom properties, added by Connect-DbaInstance:"
$serverFromConnectionString | Format-List -Property IsAzure, ComputerName, DbaInstanceName, NetPort, ConnectedAs
"Here are some properties that show we have a connection:"
$serverFromConnectionString | Format-List -Property NetName, InstanceName, Product, VersionString


# If you want to have a look at the source code of the type [DbaInstanceParameter] you find the file here:
# dbatools\bin\projects\dbatools\dbatools\Parameter\DbaInstanceParameter.cs
# There we find the different constructors for this class:
# public DbaInstanceParameter(string Name)
# public DbaInstanceParameter(IPAddress Address)
# public DbaInstanceParameter(PingReply Ping)
# public DbaInstanceParameter(IPHostEntry Entry)
# public DbaInstanceParameter(System.Data.SqlClient.SqlConnection Connection)
# public DbaInstanceParameter(Discovery.DbaInstanceReport Report)
# public DbaInstanceParameter(object Input)

# So we can have use a connection and build a server from that.
# But how to build a connection? Ask: https://docs.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlconnection
# Please note the following:
<#
If the SqlConnection goes out of scope, it won't be closed.
Therefore, you must explicitly close the connection by calling Close or Dispose.
Close and Dispose are functionally equivalent.
If the connection pooling value Pooling is set to true or yes, the underlying connection is returned back to the connection pool.
On the other hand, if Pooling is set to false or no, the underlying connection to the server is actually closed.
#>
# We can build the connection from the connection string:
[System.Data.SqlClient.SqlConnection]$connection = New-Object -TypeName System.Data.SqlClient.SqlConnection -ArgumentList $serverFromConnectionString.ConnectionContext.ConnectionString

"Some of the properties:"
$connection | Format-List -Property ConnectionString, DataSource

# We can take a connection and convert it into the type [DbaInstanceParameter]
[DbaInstanceParameter]$instanceFromConnection = $connection
"The type of the property InputObject of the object [DbaInstanceParameter]instanceFromConnection is: " + $instanceFromConnection.InputObject.GetType().ToString()
"Some interesting properties of [DbaInstanceParameter]instanceFromConnection:"
$instanceFromConnection | Format-List -Property Type, FullName, FullSmoName, ComputerName, InstanceName, Port, IsLocalHost, IsConnectionString

# What is the difference?
if ($instanceFromConnection.Type -eq 'SqlConnection') { "The object knows it is a SqlConnection" }

# Can we get a server from that? Yes, we can.
$serverFromConnection = Connect-DbaInstance -SqlInstance $instanceFromConnection
"The type of serverFromConnection is: " + $serverFromConnection.GetType().ToString()
"The property Name is equal to instanceFromConnection.FullSmoName: " + $serverFromConnection.Name
"Here are the custom properties, added by Connect-DbaInstance:"
$serverFromConnection | Format-List -Property IsAzure, ComputerName, DbaInstanceName, NetPort, ConnectedAs
"Here are some properties that show we have a connection:"
$serverFromConnection | Format-List -Property NetName, InstanceName, Product, VersionString


# Let's go back to where we get a server from a server with Connect-DbaInstance.
# Inside the Connect-DbaInstance, the server is converted back to a [DbaInstanceParameter].
# So let's do that:
[DbaInstanceParameter]$instanceFromServer = $serverFromString
"The type of the property InputObject of the object [DbaInstanceParameter]instanceFromServer is: " + $instanceFromServer.InputObject.GetType().ToString()
"Some interesting properties of [DbaInstanceParameter]instanceFromServer:"
$instanceFromServer | Format-List -Property Type, FullName, FullSmoName, ComputerName, InstanceName, Port, IsLocalHost, IsConnectionString

# What is the difference?
if ($instanceFromServer.Type -eq 'Server') { "The object knows it is a Server" }
"The connection string is in instanceFromServer.InputObject.ConnectionContext.ConnectionString: " + $instanceFromServer.InputObject.ConnectionContext.ConnectionString
# So to get the pure server object back, we have to use the property InputObject
$serverFromInstanceFromServer = $instanceFromServer.InputObject
if ($serverFromInstanceFromServer.Equals($serverFromString)) { "Yes we are equal" }


# Now let's use sql.connection.experimental
Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true

$expServerFromString = Connect-DbaInstance -SqlInstance $instanceFromString -Debug
"The property Name is equal to instance.FullSmoName: " + $expServerFromString.Name
"The server: $expServerFromString"
"Here are the custom properties, added by Connect-DbaInstance:"
$expServerFromString | Format-List -Property IsAzure, ComputerName, DbaInstanceName, NetPort, ConnectedAs
"Here are some properties that show we have a connection:"
$expServerFromString | Format-List -Property NetName, InstanceName, Product, VersionString

$expServerFromStringDuplicate = Connect-DbaInstance -SqlInstance $expServerFromString -Debug
if ($expServerFromStringDuplicate.Equals($expServerFromString)) { "Yes, they are equal" }

# Test with connection string
$expServerFromConnectionString = Connect-DbaInstance -SqlInstance $instanceFromConnectionString -Debug
"The type of expServerFromConnectionString is: " + $expServerFromConnectionString.GetType().ToString()
"The property Name is equal to instance.FullSmoName: " + $expServerFromConnectionString.Name
"Here are the custom properties, added by Connect-DbaInstance:"
$expServerFromConnectionString | Format-List -Property IsAzure, ComputerName, DbaInstanceName, NetPort, ConnectedAs
"Here are some properties that show we have a connection:"
$expServerFromConnectionString | Format-List -Property NetName, InstanceName, Product, VersionString




##################
# Work on New-DbaConnectionString
##################

Import-Module -Name .\dbatools.psm1 -Force

Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true

$connectionString = New-DbaConnectionString -SqlInstance $instanceFullnameAsString -Debug
$server = Connect-DbaInstance -SqlInstance $connectionString -Debug
$server.ConnectionContext.ConnectionString
New-DbaConnectionString -SqlInstance $server -Debug

$credentialUser1 = New-Object -TypeName System.Management.Automation.PSCredential('user1', ("P@ssw0rd" | ConvertTo-SecureString -AsPlainText -Force))
[DbaInstanceParameter]$instanceAzure = "sqlserver-db-dbatools.database.windows.net"
$connectionString = New-DbaConnectionString -SqlInstance $instanceAzure -SqlCredential $credentialUser1 -Database "database-db-dbatools" -Debug
$server = Connect-DbaInstance -SqlInstance $connectionString -Debug

$credentialAzAdUser = Get-Credential -Message 'Enter credential of a Azure AD account that has access to the Azure database'
[DbaInstanceParameter]$instanceAzure = "mdoserver.database.windows.net"
$connectionString = New-DbaConnectionString -SqlInstance $instanceAzure -SqlCredential $credentialAzAdUser -Database "mdodb" -Debug
$server = Connect-DbaInstance -SqlInstance $connectionString -Debug

# Full test of all parameters of New-DbaConnectionString
New-DbaConnectionString -SqlInstance X -ApplicationIntent ReadOnly -ConnectTimeout 10 -Database DB -EncryptConnection -FailoverPartner FP -MaxPoolSize 20 -MinPoolSize 2 -MultipleActiveResultSets -MultiSubnetFailover -NonPooledConnection -PacketSize 1234 -PooledConnectionLifetime 240 -TrustServerCertificate -WorkstationId WID -Debug -LockTimeout 60

$server.ConnectionContext.SqlConnectionObject
$server.ConnectionContext

# Can we update the individual properties from the connection string?
$connStringBuilder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $server.ConnectionContext.ConnectionString
# Sorry, not allowed:
$server.ConnectionContext.ApplicationName = $connStringBuilder['Application Name']
$server.ConnectionContext.DatabaseName = $connStringBuilder['Initial Catalog']
# But we have the info here:
$server.ConnectionContext.SqlConnectionObject.Database


# Use parameter to build server
$server = Connect-DbaInstance -SqlInstance $instanceFullnameAsString -Debug -BatchSeparator XX -ConnectTimeout 20 -StatementTimeout 30
$server.ConnectionContext.ConnectionString
$server.ConnectionContext.StatementTimeout
$server.ConnectionContext.ConnectTimeout
$server.ConnectionContext.BatchSeparator



####
# Simple connects
####
Import-Module -Name .\dbatools.psm1 -Force
Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true
$server = Connect-DbaInstance -SqlInstance srv1\sql2016 -Debug
$server.ConnectionContext.ProcessID



$conStr = New-DbaConnectionString -SqlInstance srv1\sql2016 -Debug
$conStr = 'Data Source=srv1\sql2016;Integrated Security=True'
$server = Connect-DbaInstance -SqlInstance $conStr -Debug
$server.ConnectionContext.ProcessID



####
# Working with registered servers
####
Import-Module -Name .\dbatools.psm1 -Force
Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true
$regServer2016 = Get-DbaRegisteredServer -Group V2016
$regServer2016[0] | fl *
[DbaInstanceParameter]$testInstance = $regServer2016[0]
$testInstance.InputObject.ConnectionString
$server = $regServer2016[0] | Connect-DbaInstance -Debug -ConnectTimeout 35
$server.ConnectionContext.SqlConnectionObject.ConnectionTimeout
$server.ConnectionContext.ConnectionString
$server.ConnectionContext.ProcessID

$server = $regServer2016[0] | Connect-DbaInstance -Debug
$server.ConnectionContext.ProcessID

$serverX = Connect-DbaInstance -SqlInstance $server
$serverX.ConnectionContext.ProcessID
# Connection is reused

$serverX = Connect-DbaInstance -SqlInstance $server -ConnectTimeout 35 -Debug
$serverX.ConnectionContext.ProcessID
# Connection is not reused

$server.ConnectionContext.SqlConnectionObject.CurrentDatabase
Invoke-DbaQuery -SqlInstance $server -Query 'SELECT @@SPID' -as SingleValue -Debug
# Connection is reused

Invoke-DbaQuery -SqlInstance $server -Database tempdb -Query 'SELECT @@SPID' -as SingleValue -Debug
# Connection is not reused

$serverTempdb = Connect-DbaInstance -SqlInstance SRV1\SQl2016 -Database tempdb
Invoke-DbaQuery -SqlInstance $serverTempdb -Database tempdb -Query 'SELECT @@SPID' -as SingleValue -Debug
$serverTempdb.ConnectionContext.currentdatabase
$serverTempdb.ConnectionContext.SqlConnectionObject.database


####
# Changing database context on Azure
####
Import-Module -Name .\dbatools.psm1 -Force
$credentialUser1 = New-Object -TypeName System.Management.Automation.PSCredential('user1', ("P@ssw0rd" | ConvertTo-SecureString -AsPlainText -Force))
[DbaInstanceParameter]$instanceAzure = "sqlserver-db-dbatools.database.windows.net"
$connectionString = New-DbaConnectionString -SqlInstance $instanceAzure -SqlCredential $credentialUser1 -Database "database-db-dbatools"
$server = Connect-DbaInstance -SqlInstance $connectionString
$server.ConnectionContext.DatabaseName
$server.ConnectionContext.CurrentDatabase
$server.Query('SELECT db_name() as dbname').dbname
Invoke-DbaQuery -SqlInstance $server -Query 'SELECT db_name() as dbname' -As SingleValue
# They all return: database-db-dbatools

Invoke-DbaQuery -SqlInstance $server -Database 'test-dbatools' -Query 'SELECT db_name() as dbname' -As SingleValue -Debug
# Returns: test-dbatools

$server.ConnectionContext.DatabaseName
$server.ConnectionContext.CurrentDatabase
$server.Query('SELECT db_name() as dbname').dbname
# They all return: database-db-dbatools

##### New code path:
Import-Module -Name .\dbatools.psm1 -Force
Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true
$credentialUser1 = New-Object -TypeName System.Management.Automation.PSCredential('user1', ("P@ssw0rd" | ConvertTo-SecureString -AsPlainText -Force))
[DbaInstanceParameter]$instanceAzure = "sqlserver-db-dbatools.database.windows.net"
$connectionString = New-DbaConnectionString -SqlInstance $instanceAzure -SqlCredential $credentialUser1 -Database "database-db-dbatools"
$server = Connect-DbaInstance -SqlInstance $connectionString -Debug
$server.ConnectionContext.DatabaseName
$server.ConnectionContext.CurrentDatabase
$server.Query('SELECT db_name() as dbname').dbname
Invoke-DbaQuery -SqlInstance $server -Query 'SELECT db_name() as dbname' -As SingleValue
# They all but the first return: database-db-dbatools
# $server.ConnectionContext.DatabaseName is empty because server was build from connection string

Invoke-DbaQuery -SqlInstance $server -Database 'test-dbatools' -Query 'SELECT db_name() as dbname' -As SingleValue -Debug
# Returns: test-dbatools

$server.ConnectionContext.DatabaseName
$server.ConnectionContext.CurrentDatabase
$server.Query('SELECT db_name() as dbname').dbname
# They all but the first return: database-db-dbatools
$server.Query('SELECT @@SPID as spid').spid



Invoke-DbaQuery -SqlInstance $server -Query 'SELECT @@SPID as spid' -As SingleValue
Invoke-DbaQuery -SqlInstance $server -Database 'test-dbatools' -Query 'SELECT @@SPID as spid' -As SingleValue -Debug
