<#

This demo shows how to downgrade the database StackOverflowMini from version 2022 to an earlier version.

Get the database from here: https://github.com/BrentOzarULTD/Stack-Overflow-Database

This could also help you downgrade other databases, but changes may be required.

#>


Import-Module -Name dbatools

# Connect to the source database.
# You may have to add -SqlCredential if using integrated security is not possible.
$sourceDatabase = Get-DbaDatabase -SqlInstance SQL01\SQL2022 -Database StackOverflowMini -SqlCredential

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

# Loop through all the tables.
$copyResults = foreach ($table in $sourceDatabase.Tables) {
    # Get the CREATE TABLE script. The method also generated two SET commands so we join them all together.
    $query = $table.Script() -join "`n"

    # Run the CREATE TABLE script against the target database.
    Invoke-DbaQuery -SqlInstance $targetServer -Database $sourceDatabase.Name -Query $query

    # Refresh the SMO so that it knows the new table.
    $targetServer.Databases[$sourceDatabase.Name].Tables.Refresh()

    # Copy the data over to the target table.
    $table | Copy-DbaDbTableData -Destination $targetServer -DestinationDatabase $sourceDatabase.Name -Table $table.Name
}

# View the results to see how much data was copied and in what time.
$copyResults | Format-Table -Property SourceTable, RowsCopied, Elapsed
