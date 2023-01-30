<#

This demo shows how to downgrade the database StackOverflowMini from version 2022 to an earlier version.

Get the database from here: https://github.com/BrentOzarULTD/Stack-Overflow-Database

This could also help you downgrade other databases, but changes may be required.

#>


Import-Module -Name dbatools

# Connect to the source database.
# You may have to add -SqlCredential if using integrated security is not possible.
$sourceDatabase = Get-DbaDatabase -SqlInstance SQL01\SQL2022 -Database StackOverflowMini

# Connect to the target instance.
# You may have to add -SqlCredential if using integrated security is not possible.
$targetServer = Connect-DbaInstance -SqlInstance SQL01\SQL2019

# Define the parameters for the target database based on the source database.
$targetDatabaseParams = @{
    SqlInstance     = $targetServer
    Name            = $sourceDatabase.Name
    Collation       = $sourceDatabase.Collation
    PrimaryFilesize = $sourceDatabase.FileGroups['PRIMARY'].Files[0].Size / 1024
}

# Create the new database on the target instance.
$null = New-DbaDatabase @targetDatabaseParams

# Copy all the tables including the data.
$transferParams = @{
    SqlInstance            = $sourceDatabase.Parent
    DestinationSqlInstance = $targetServer
    Database               = $sourceDatabase.Name
    CopyAll                = 'Tables'
}
Invoke-DbaDbTransfer @transferParams
