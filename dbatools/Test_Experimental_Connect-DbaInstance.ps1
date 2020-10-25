# Tests for the new Connect-DbaInstance
Import-Module -Name .\dbatools.psm1 -Force
Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true


# Setup the instances

$instanceNameLocal = 'SRV1\SQL2016'
$instanceNameAzure = 'sqlserver-db-dbatools.database.windows.net'

[DbaInstanceParameter]$instanceLocal = $instanceNameLocal
[DbaInstanceParameter]$instanceAzure = $instanceNameAzure


# Setup the databases

$databaseNameLocal1 = 'TestDB1'
$databaseNameLocal2 = 'TestDB2'

$databaseNameAzure1 = 'database-db-dbatools'
$databaseNameAzure2 = 'test-dbatools'


# Setup the credentials

# Get-Credential -Message 'Local SQL Login' -UserName LocalSql | Export-Clixml -Path C:\Credentials\LocalSql.xml
$credentialLocalSql = Import-Clixml -Path C:\Credentials\LocalSql.xml

# Get-ADUser -Filter { Name -eq 'SQLServer' }
# Get-Credential -Message 'Local AD User' -UserName SQLServer@Company.Pri | Export-Clixml -Path C:\Credentials\LocalAdUser.xml
$credentialLocalAdUser = Import-Clixml -Path C:\Credentials\LocalAdUser.xml

# Get-Credential -Message 'Azure SQL Admin' | Export-Clixml -Path C:\Credentials\AzureSqlAdmin.xml
$credentialAzureAdmin = Import-Clixml -Path C:\Credentials\AzureSqlAdmin.xml

# Get-Credential -Message 'Azure SQL User' -UserName user1 | Export-Clixml -Path C:\Credentials\AzureSqlUser.xml
$credentialAzureSqlUser = Import-Clixml -Path C:\Credentials\AzureSqlUser.xml

# Get-Credential -Message 'Azure AD User' | Export-Clixml -Path C:\Credentials\AzureAdUser.xml
$credentialAzureAdUser = Import-Clixml -Path C:\Credentials\AzureAdUser.xml
[string]$tenant = Get-Content -Path C:\Credentials\Tenant.txt


# Setup local test databases

$server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceLocal
if ($server.LoginMode -ne 'Mixed') {
    $server.LoginMode = 'Mixed'
    $server.Alter()
    $null = Restart-DbaService -ComputerName $instanceLocal.ComputerName -InstanceName $instanceLocal.InstanceName
}
try { $server.Query("DROP DATABASE $databaseNameLocal1") } catch {}
try { $server.Query("DROP DATABASE $databaseNameLocal2") } catch {}
$null = Get-DbaLogin -SqlInstance $server -Login $credentialLocalSql.UserName | Remove-DbaLogin -Force
$server.Query("CREATE DATABASE $databaseNameLocal1")
$server.Query("CREATE DATABASE $databaseNameLocal2")
$server.Query("CREATE TABLE $databaseNameLocal1.dbo.TestTable(a int)")
$server.Query("CREATE TABLE $databaseNameLocal2.dbo.TestTable(a int)")
$server.Query("INSERT INTO $databaseNameLocal1.dbo.TestTable VALUES (1)")
$server.Query("INSERT INTO $databaseNameLocal2.dbo.TestTable VALUES (2)")
$null = New-DbaLogin -SqlInstance $server -Login $credentialLocalSql.UserName -SecurePassword $credentialLocalSql.Password
$null = New-DbaDbUser -SqlInstance $server -Database $databaseNameLocal1 -Username $credentialLocalSql.UserName -Login $credentialLocalSql.UserName
$null = New-DbaDbUser -SqlInstance $server -Database $databaseNameLocal2 -Username $credentialLocalSql.UserName -Login $credentialLocalSql.UserName
Add-DbaDbRoleMember -SqlInstance $server -Database $databaseNameLocal1 -Role db_owner -User $credentialLocalSql.UserName -Confirm:$false
Add-DbaDbRoleMember -SqlInstance $server -Database $databaseNameLocal2 -Role db_owner -User $credentialLocalSql.UserName -Confirm:$false



# Let's start with the central part: Test connection pooling with different methods of creating the smo server object

######
# Local database with integrated security
######

'Test 1:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameLocal
    $server.ConnectionContext.ProcessID
}
# connection pooling works

'Test 2:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameLocal
    $server.ConnectionContext.ApplicationName = 'Test'
    $server.ConnectionContext.ProcessID
}
# connection pooling works

'Test 3:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameLocal
    $server.ConnectionContext.NonPooledConnection = $false  # This doesn't help
    $server.ConnectionContext.ConnectionString = "Data Source=$instanceNameLocal;Integrated Security=True;MultipleActiveResultSets=False;Encrypt=False;TrustServerCertificate=False;Application Name=Test"
    $server.ConnectionContext.ProcessID
}
# connection pooling does NOT work

'Test 4:'
1..5 | ForEach-Object -Process {
    $connInfo = New-Object Microsoft.SqlServer.Management.Common.SqlConnectionInfo $instanceNameLocal
    $connInfo.ApplicationName = 'Test'
    $srvConn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $connInfo
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $srvConn
    $server.ConnectionContext.ProcessID
}
# connection pooling works


######
# Local database with different AD user
######

'Test 1:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameLocal
    $server.ConnectionContext.ConnectAsUser = $true
    $server.ConnectionContext.ConnectAsUserName = $credentialLocalAdUser.UserName
    $server.ConnectionContext.ConnectAsUserPassword = $credentialLocalAdUser.GetNetworkCredential().Password
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling works

'Test 2:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameLocal
    $server.ConnectionContext.ConnectAsUser = $true
    $server.ConnectionContext.ConnectAsUserName = $credentialLocalAdUser.UserName
    $server.ConnectionContext.ConnectAsUserPassword = $credentialLocalAdUser.GetNetworkCredential().Password
    $server.ConnectionContext.ApplicationName = 'Test'
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling works

'Test 3:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameLocal
    $server.ConnectionContext.ConnectAsUser = $true
    $server.ConnectionContext.ConnectAsUserName = $credentialLocalAdUser.UserName
    $server.ConnectionContext.ConnectAsUserPassword = $credentialLocalAdUser.GetNetworkCredential().Password
    $server.ConnectionContext.NonPooledConnection = $false  # This doesn't help
    $server.ConnectionContext.ConnectionString = "Data Source=$instanceNameLocal;Integrated Security=True;MultipleActiveResultSets=False;Encrypt=False;TrustServerCertificate=False;Application Name=Test"
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling does NOT work
# wrong security context because setting the connection string overrides the ConnectAsUser* properties

'Test 4:'
1..5 | ForEach-Object -Process {
    $connInfo = New-Object Microsoft.SqlServer.Management.Common.SqlConnectionInfo $instanceNameLocal
    $connInfo.ApplicationName = 'Test'
    $srvConn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $connInfo
    $srvConn.ConnectAsUser = $true
    $srvConn.ConnectAsUserName = $credentialLocalAdUser.UserName
    $srvConn.ConnectAsUserPassword = $credentialLocalAdUser.GetNetworkCredential().Password
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $srvConn
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling works


######
# Local database with SQL login
######

'Test 1:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameLocal
    $server.ConnectionContext.LoginSecure = $false
    $server.ConnectionContext.Login = $credentialLocalSql.UserName
    $server.ConnectionContext.Password = $credentialLocalSql.GetNetworkCredential().Password
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling works

'Test 2:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameLocal
    $server.ConnectionContext.LoginSecure = $false
    $server.ConnectionContext.Login = $credentialLocalSql.UserName
    $server.ConnectionContext.Password = $credentialLocalSql.GetNetworkCredential().Password
    $server.ConnectionContext.ApplicationName = 'Test'
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling works

'Test 3:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameLocal
    $server.ConnectionContext.NonPooledConnection = $false  # This doesn't help
    $server.ConnectionContext.ConnectionString = "Data Source=$instanceNameLocal;User ID=$($credentialLocalSql.UserName);Password=$($credentialLocalSql.GetNetworkCredential().Password);MultipleActiveResultSets=False;Encrypt=False;TrustServerCertificate=False;Application Name=Test"
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling does NOT work

'Test 4:'
1..5 | ForEach-Object -Process {
    $connInfo = New-Object Microsoft.SqlServer.Management.Common.SqlConnectionInfo $instanceNameLocal
    $connInfo.UserName = $credentialLocalSql.UserName
    $connInfo.SecurePassword = $credentialLocalSql.Password
    $connInfo.ApplicationName = 'Test'
    $srvConn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $connInfo
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $srvConn
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling works


######
# Azure Database with SQL login
######

'Test 1:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameAzure
    $server.ConnectionContext.LoginSecure = $false
    $server.ConnectionContext.Login = $credentialAzureSqlUser.UserName
    $server.ConnectionContext.Password = $credentialAzureSqlUser.GetNetworkCredential().Password
    $server.ConnectionContext.DatabaseName = $databaseNameAzure1
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling works

'Test 2:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameAzure
    $server.ConnectionContext.LoginSecure = $false
    $server.ConnectionContext.Login = $credentialAzureSqlUser.UserName
    $server.ConnectionContext.Password = $credentialAzureSqlUser.GetNetworkCredential().Password
    $server.ConnectionContext.DatabaseName = $databaseNameAzure1
    $server.ConnectionContext.ApplicationName = 'Test'
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling works

'Test 3:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameAzure
    $server.ConnectionContext.NonPooledConnection = $false  # This doesn't help
    $server.ConnectionContext.ConnectionString = "Data Source=$instanceNameAzure;Initial Catalog=$databaseNameAzure1;User ID=$($credentialAzureSqlUser.UserName);Password=$($credentialAzureSqlUser.GetNetworkCredential().Password);MultipleActiveResultSets=False;Encrypt=False;TrustServerCertificate=False;Application Name=Test"
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling does NOT work

'Test 4:'
1..5 | ForEach-Object -Process {
    $connInfo = New-Object Microsoft.SqlServer.Management.Common.SqlConnectionInfo $instanceNameAzure
    $connInfo.UserName = $credentialAzureSqlUser.UserName
    $connInfo.SecurePassword = $credentialAzureSqlUser.Password
    $connInfo.DatabaseName = $databaseNameAzure1
    $connInfo.ApplicationName = 'Test'
    $srvConn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $connInfo
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $srvConn
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling works


######
# Azure Database with AD login
######

'Test 1:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameAzure
    $server.ConnectionContext.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword
    $server.ConnectionContext.LoginSecure = $false
    $server.ConnectionContext.Login = $credentialAzureAdUser.UserName
    $server.ConnectionContext.Password = $credentialAzureAdUser.GetNetworkCredential().Password
    $server.ConnectionContext.DatabaseName = $databaseNameAzure1
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling works

'Test 2:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameAzure
    $server.ConnectionContext.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword
    $server.ConnectionContext.LoginSecure = $false
    $server.ConnectionContext.Login = $credentialAzureAdUser.UserName
    $server.ConnectionContext.Password = $credentialAzureAdUser.GetNetworkCredential().Password
    $server.ConnectionContext.DatabaseName = $databaseNameAzure1
    $server.ConnectionContext.ApplicationName = 'Test'
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling works

'Test 3:'
1..5 | ForEach-Object -Process {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instanceNameAzure
    $server.ConnectionContext.NonPooledConnection = $false  # This doesn't help
    $server.ConnectionContext.ConnectionString = "Data Source=$instanceNameAzure;Initial Catalog=$databaseNameAzure1;Authentication=Active Directory Password;User ID=$($credentialAzureAdUser.UserName);Password=$($credentialAzureAdUser.GetNetworkCredential().Password);MultipleActiveResultSets=False;Encrypt=False;TrustServerCertificate=False;Application Name=Test"
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling does NOT work

'Test 4:'
1..5 | ForEach-Object -Process {
    $connInfo = New-Object Microsoft.SqlServer.Management.Common.SqlConnectionInfo $instanceNameAzure
    $connInfo.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword
    $connInfo.UserName = $credentialAzureAdUser.UserName
    $connInfo.SecurePassword = $credentialAzureAdUser.Password
    $connInfo.DatabaseName = $databaseNameAzure2
    $connInfo.ApplicationName = 'Test'
    $srvConn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $connInfo
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $srvConn
    $server.ConnectionContext.ProcessID
}
$server.ConnectionContext.TrueLogin
# connection pooling works

$server = Connect-DbaInstance -SqlInstance $instanceNameAzure -SqlCredential $credentialAzureAdUser -Database $databaseNameAzure1 -Debug


#####
# Summary of authentification when using SqlConnectionInfo -> ServerConnection -> Server
#####

# Local database with integrated security:
# Do nothing

# Local database with different AD user:
# configure ServerConnection.ConnectAsUser = $true / ServerConnection.ConnectAsUserName = $cred.UserName / ServerConnection.ConnectAsUserPassword = $cred.GetNetworkCredential().Password

# Local database with SQL login:
# configure SqlConnectionInfo.UserName = $cred.UserName / SqlConnectionInfo.SecurePassword = $cred.Password

# Azure Database with SQL login:
# configure SqlConnectionInfo.UserName = $cred.UserName / SqlConnectionInfo.SecurePassword = $cred.Password

# Azure Database with AD login:
# configure SqlConnectionInfo.UserName = $cred.UserName / SqlConnectionInfo.SecurePassword = $cred.Password / SqlConnectionInfo.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword


#####
# test all authentification with dbatools
#####
Import-Module -Name .\dbatools.psm1 -Force
Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true

$server = Connect-DbaInstance -SqlInstance $instanceNameLocal -Debug
$server | Format-Table -Property ComputerName, DbaInstanceName, ConnectedAs, IsAzure

$server = Connect-DbaInstance -SqlInstance $instanceNameLocal -SqlCredential $credentialLocalAdUser -Debug
$server | Format-Table -Property ComputerName, DbaInstanceName, ConnectedAs, IsAzure

$server = Connect-DbaInstance -SqlInstance $instanceNameLocal -SqlCredential $credentialLocalSql -Debug
$server | Format-Table -Property ComputerName, DbaInstanceName, ConnectedAs, IsAzure

$server = Connect-DbaInstance -SqlInstance $instanceNameAzure -SqlCredential $credentialAzureSqlUser -Database $databaseNameAzure1 -Debug
$server | Format-Table -Property ComputerName, DbaInstanceName, ConnectedAs, IsAzure

$server = Connect-DbaInstance -SqlInstance $instanceNameAzure -SqlCredential $credentialAzureAdUser -Database $databaseNameAzure1 -Debug
$server | Format-Table -Property ComputerName, DbaInstanceName, ConnectedAs, IsAzure


























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
    $server = Connect-DbaInstance -SqlInstance $instanceName -Database master
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

$server.ConnectionContext.SqlConnectionObject

$server.ConnectionContext

$server2 = Connect-DbaInstance -SqlInstance $server
$server2.ConnectionContext.ProcessID
$server2.ConnectionContext.CurrentDatabase
$server3 = Connect-DbaInstance -SqlInstance $server -Database tempdb
$server3.ConnectionContext.ProcessID
$server3.ConnectionContext.CurrentDatabase

####
# Work in Azure
####
Import-Module -Name .\dbatools.psm1 -Force
Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true

$credentialUser1 = New-Object -TypeName System.Management.Automation.PSCredential('user1', ("P@ssw0rd" | ConvertTo-SecureString -AsPlainText -Force))
[DbaInstanceParameter]$instanceAzure = "sqlserver-db-dbatools.database.windows.net"
$Database1 = 'database-db-dbatools'
$Database2 = 'test-dbatools'
$server1 = Connect-DbaInstance -SqlInstance $instanceAzure -SqlCredential $credentialUser1 -Database $Database1 -Debug
Invoke-DbaQuery -SqlInstance $server1 -Query 'SELECT @@SPID' -As SingleValue -Debug
Invoke-DbaQuery -SqlInstance $server1 -Database $Database2 -Query 'SELECT @@SPID' -As SingleValue -Debug

'Test 1:'
$server1 = Connect-DbaInstance -SqlInstance $instanceAzure -SqlCredential $credentialUser1 -Database $Database1
$server2 = Connect-DbaInstance -SqlInstance $instanceAzure -SqlCredential $credentialUser1 -Database $Database2
$sql = "SELECT CAST(@@SPID AS VARCHAR) + '   ' + (SELECT CAST(COUNT(*) AS VARCHAR) FROM sys.dm_exec_sessions) + '   ' + DB_NAME() + '   ' + (SELECT CAST(MAX(a) AS VARCHAR) FROM dbo.Test)"
1..3 | ForEach-Object -Process {
    Invoke-DbaQuery -SqlInstance $server1 -Query $sql -As SingleValue
    Invoke-DbaQuery -SqlInstance $server2 -Query $sql -As SingleValue
    Invoke-DbaQuery -SqlInstance $server1 -Database $Database2 -Query $sql -As SingleValue
    Invoke-DbaQuery -SqlInstance $server2 -Database $Database1 -Query $sql -As SingleValue
}

1..102 | ForEach-Object -Process {
    Invoke-DbaQuery -SqlInstance $instanceAzure -SqlCredential $credentialUser1 -Database $Database1 -Query "SELECT @@SPID" -As SingleValue
}


Invoke-DbaQuery -SqlInstance $server1 -Query 'SELECT CAST(MAX(a) AS VARCHAR) FROM dbo.Test' -As SingleValue


Invoke-DbaQuery -SqlInstance $server1 -Query 'SELECT COUNT(*) FROM sys.dm_exec_sessions' | ogv




$connectionString = New-DbaConnectionString -SqlInstance $instanceAzure -SqlCredential $credentialUser1 -Database "database-db-dbatools" -Debug
$server = Connect-DbaInstance -SqlInstance $connectionString -Debug

$credentialAzAdUser = Get-Credential -Message 'Enter credential of a Azure AD account that has access to the Azure database'
[DbaInstanceParameter]$instanceAzure = "mdoserver.database.windows.net"
$connectionString = New-DbaConnectionString -SqlInstance $instanceAzure -SqlCredential $credentialAzAdUser -Database "mdodb" -Debug
$server = Connect-DbaInstance -SqlInstance $connectionString -Debug

$server = Connect-DbaInstance -SqlInstance $instanceAzure -SqlCredential $credentialAzAdUser -Database "mdodb" -Debug
$server.ConnectionContext.ProcessID


######
# Connection objects
######

$server = Connect-DbaInstance -SqlInstance $instanceName
$conn = $server.ConnectionContext.SqlConnectionObject

$server1 = Connect-DbaInstance -SqlInstance $conn
$server2 = Connect-DbaInstance -SqlInstance $conn
$server3 = Connect-DbaInstance -SqlInstance $conn

$server1.ConnectionContext.ProcessID
$server2.ConnectionContext.ProcessID
$server3.ConnectionContext.ProcessID

# Connection pooling does work - we have only one connections



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
$regServer2016[0] | gm
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



$regServer2016 = Get-DbaRegisteredServer -Group V2016

$server1 = Connect-DbaInstance -SqlInstance $regServer2016[0]
$server2 = Connect-DbaInstance -SqlInstance $regServer2016[0]
$server3 = Connect-DbaInstance -SqlInstance $regServer2016[0]

$server1.ConnectionContext.ProcessID
$server2.ConnectionContext.ProcessID
$server3.ConnectionContext.ProcessID

# Connection pooling does not work - we have three different connections



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
