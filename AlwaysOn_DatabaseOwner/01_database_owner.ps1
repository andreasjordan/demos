$ErrorActionPreference = 'Stop'

Import-Module -Name dbatools

$SqlInstances = 'SRV1', 'SRV2'
$BackupPath = '\\WIN10\SQLServerBackups'
$DatabaseName = 'Test01'
$AvailabilityGroupName = 'AdventureSQL'


# We need three logins with sysadmin role, one for creating the database, one for restoring the database and one for as the new owner

$credAdmin1 = Get-Credential -Message 'SQL Admin 1' -UserName admin1
$credAdmin2 = Get-Credential -Message 'SQL Admin 2' -UserName admin2
$credAdmin3 = Get-Credential -Message 'SQL Admin 2' -UserName admin3


# Take care that we have mixed authentication mode

$server = Connect-DbaInstance -SqlInstance $SqlInstances
foreach ($srv in $server) {
    if ($srv.LoginMode -ne 'Mixed') {
        $srv.LoginMode = 'Mixed'
        $srv.Alter()
        $null = Restart-DbaService -ComputerName $srv.ComputerName -InstanceName $srv.DbaInstanceName -Type Engine -Force
    }
}


# Take care the the first instance is the primary of the availability group

if ((Get-DbaAvailabilityGroup -SqlInstance $server[0] -AvailabilityGroup $AvailabilityGroupName).LocalReplicaRole -ne 'Primary') { 
    $null = Invoke-DbaAgFailover -SqlInstance $server[0] -AvailabilityGroup $AvailabilityGroupName -Confirm:$false
}


# Create logins, add them to sysadmin and create a connection with that login

$loginAdmin1 = New-DbaLogin -SqlInstance $server[0] -Login $credAdmin1.UserName -SecurePassword $credAdmin1.Password 
$null = New-DbaLogin -SqlInstance $server[1] -Login $credAdmin1.UserName -SecurePassword $credAdmin1.Password -Sid $loginAdmin1.Sid
$null = Set-DbaLogin -SqlInstance $server -Login $credAdmin1.UserName -AddRole sysadmin
$serverAdmin1 = Connect-DbaInstance -SqlInstance $SqlInstances -SqlCredential $credAdmin1

$loginAdmin2 = New-DbaLogin -SqlInstance $server[0] -Login $credAdmin2.UserName -SecurePassword $credAdmin2.Password 
$null = New-DbaLogin -SqlInstance $server[1] -Login $credAdmin2.UserName -SecurePassword $credAdmin2.Password -Sid $loginAdmin2.Sid
$null = Set-DbaLogin -SqlInstance $server -Login $credAdmin2.UserName -AddRole sysadmin
$serverAdmin2 = Connect-DbaInstance -SqlInstance $SqlInstances -SqlCredential $credAdmin2

$loginAdmin3 = New-DbaLogin -SqlInstance $server[0] -Login $credAdmin3.UserName -SecurePassword $credAdmin3.Password 
$null = New-DbaLogin -SqlInstance $server[1] -Login $credAdmin3.UserName -SecurePassword $credAdmin3.Password -Sid $loginAdmin3.Sid
$null = Set-DbaLogin -SqlInstance $server -Login $credAdmin3.UserName -AddRole sysadmin
$serverAdmin3 = Connect-DbaInstance -SqlInstance $SqlInstances -SqlCredential $credAdmin3


# Create the database as admin1 and create the first backups

$null = New-DbaDatabase -SqlInstance $serverAdmin1[0] -Name $DatabaseName
$fullBackup = Backup-DbaDatabase -SqlInstance $serverAdmin1[0] -Database $DatabaseName -Path $BackupPath -Type Full
$logBackup = Backup-DbaDatabase -SqlInstance $serverAdmin1[0] -Database $DatabaseName -Path $BackupPath -Type Log


# Restore the database as admin2 and add the database to the availability group

$null = $fullBackup | Restore-DbaDatabase -SqlInstance $serverAdmin2[1] -NoRecovery 
$null = $logBackup | Restore-DbaDatabase -SqlInstance $serverAdmin2[1] -NoRecovery -Continue
$null = Add-DbaAgDatabase -SqlInstance $serverAdmin2[0] -AvailabilityGroup $AvailabilityGroupName -Database $DatabaseName -Secondary $serverAdmin2[1] -SeedingMode Automatic


# Get information about the database

Get-DbaAgDatabase -SqlInstance $server -AvailabilityGroup $AvailabilityGroupName -Database $DatabaseName | Format-Table -Property SqlInstance, Name, SynchronizationState
Get-DbaDatabase -SqlInstance $server -Database $DatabaseName | Format-Table -Property SqlInstance, Name, Owner

<#

SqlInstance Name   SynchronizationState
----------- ----   --------------------
SRV1        Test01         Synchronized
SRV2        Test01         Synchronized


SqlInstance Name   Owner 
----------- ----   ----- 
SRV1        Test01 admin1
SRV2        Test01 admin2

#>

# Result: Owner is different


# Change the owner of the database which is only possible at the primary instance

$null = Set-DbaDbOwner -SqlInstance $server[0] -Database $DatabaseName -TargetLogin $credAdmin3.UserName
Get-DbaDatabase -SqlInstance $server -Database $DatabaseName | Format-Table -Property SqlInstance, Name, Owner         # Ups, not updated - but maybe its only the SMO...
Get-DbaDatabase -SqlInstance $SqlInstances -Database $DatabaseName | Format-Table -Property SqlInstance, Name, Owner   # Yes, that's a bug...
# Let's refresh the SMO (like hitting F5 in SSMS):
$server[0].Databases[$DatabaseName].Refresh()
Get-DbaDatabase -SqlInstance $server -Database $DatabaseName | Format-Table -Property SqlInstance, Name, Owner         # Ok, now the correct info is there

<#

SqlInstance Name   Owner 
----------- ----   ----- 
SRV1        Test01 admin3
SRV2        Test01 admin2

#>

# Result: The owner is not changed at the secondary instance. So this info is not part of the database but part of the instance

# Here is where the info is stored

$server.Query("SELECT @@SERVERNAME AS server_name, db.name AS database_name, sp.name AS owner_name FROM sys.databases db JOIN sys.server_principals sp ON db.owner_sid = sp.sid WHERE db.name = '$DatabaseName'")

<#

server_name database_name owner_name
----------- ------------- ----------
SRV1        Test01        admin3    
SRV2        Test01        admin2    

#>


# How to change the owner on the secondary? Fail over, change owner, fail back

$null = Invoke-DbaAgFailover -SqlInstance $server[1] -AvailabilityGroup $AvailabilityGroupName -Confirm:$false
$null = Set-DbaDbOwner -SqlInstance $server[1] -Database $DatabaseName -TargetLogin $credAdmin3.UserName          # Ups, SMO is not up to date again...
$null = Set-DbaDbOwner -SqlInstance $SqlInstances[1] -Database $DatabaseName -TargetLogin $credAdmin3.UserName    # That works
$null = Invoke-DbaAgFailover -SqlInstance $server[0] -AvailabilityGroup $AvailabilityGroupName -Confirm:$false


# Let's see the result (and use new SMOs to get up to date data)

Get-DbaAgReplica -SqlInstance $SqlInstances[0] -AvailabilityGroup $AvailabilityGroupName | Format-Table -Property Name, AvailabilityGroup, Role
Get-DbaDatabase -SqlInstance $SqlInstances -Database $DatabaseName | Format-Table -Property SqlInstance, Name, Owner

<#

Name AvailabilityGroup      Role
---- -----------------      ----
SRV1 AdventureSQL        Primary
SRV2 AdventureSQL      Secondary


SqlInstance Name   Owner 
----------- ----   ----- 
SRV1        Test01 admin3
SRV2        Test01 admin3

#>


# Cleanup

$null = Remove-DbaAgDatabase -SqlInstance $SqlInstances[0] -Database $DatabaseName -AvailabilityGroup $AvailabilityGroupName -Confirm:$false
$null = Remove-DbaDatabase -SqlInstance $SqlInstances -Database $DatabaseName -Confirm:$false
$null = Remove-DbaLogin -SqlInstance $SqlInstances -Login $credAdmin1.UserName, $credAdmin2.UserName, $credAdmin3.UserName -Force
Remove-DbaDbBackupRestoreHistory -SqlInstance $SqlInstances -Database $DatabaseName -Confirm:$false
Get-ChildItem -Path $BackupPath -Filter ($DatabaseName + '*') | Remove-Item
