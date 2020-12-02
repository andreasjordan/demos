[CmdletBinding()]
param (
    [string[]]$ClusterNodes = @('SRV1', 'SRV2'),
    [string[]]$InstanceNames = @('MSSQLSERVER', 'SQL2017', 'SQL2016', 'SQL2014'),
    [string[]]$SqlVersions = @('2019', '2017', '2016', '2014'),
    [PSCredential]$AdministratorCredential = (New-Object -TypeName PSCredential -ArgumentList "COMPANY\Administrator", (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force)),
    [PSCredential]$SqlServerCredential = (New-Object -TypeName PSCredential -ArgumentList "COMPANY\SQLServer", (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force)),
    [string]$SQLServerSourcesPath = '\\WIN10\SQLServerSources',
    [string]$SQLServerPatchesPath = '\\WIN10\SQLServerPatches',
    [string]$BackupPath = '\\WIN10\SQLServerBackups',
    [string]$DatabaseName = 'AdventureWorks'
)

function Write-LocalWarning {
    param (
        [string]$Message
    )
    Write-Warning -Message ('{0}: {1}' -f (Get-Date), $Message)
}

function Write-LocalHost {
    param (
        [string]$Message,
        [string]$ForegroundColor = 'Yellow'
    )
    Microsoft.PowerShell.Utility\Write-Host -Object ('{0}: {1}' -f (Get-Date), $Message) -ForegroundColor $ForegroundColor
}

function Write-LocalVerbose {
    param (
        [string]$Message
    )
    Write-Verbose -Message ('{0}: {1}' -f (Get-Date), $Message)
}

$ErrorActionPreference = 'Stop'

$instances = @() 
foreach ( $nr in 0 .. ($InstanceNames.Count - 1) ) { 
    $instances += [PSCustomObject]@{
        InstanceName = $InstanceNames[$nr]
        SqlVersion = $SqlVersions[$nr]
    }
}

$SQLServerServiceAccountName = ($SqlServerCredential.UserName -split '\\')[1]
if ( $null -eq (Get-ADUser -Filter "Name -eq '$SQLServerServiceAccountName'") ) {
    Write-LocalHost -Message 'Creating user for SQL Server service account and grant access to backup share'
    New-ADUser -Name $SQLServerServiceAccountName -AccountPassword $sqlServerCredential.Password -PasswordNeverExpires:$true -Enabled:$true
    $null = Grant-SmbShareAccess -Name SQLServerBackups -AccountName $SqlServerCredential.UserName -AccessRight Full -Force
}

Write-LocalHost -Message 'Import module dbatools'
Import-Module -Name dbatools -MinimumVersion 1.0.124

Write-LocalHost -Message 'Change powerplan of cluster nodes to high performance'
Set-DbaPowerPlan -ComputerName $ClusterNodes | Format-Table

foreach ( $instance in $instances ) {
    $sqlInstances = @();
    foreach ( $node in $ClusterNodes ) {
        $sqlInstances += "$node\$($instance.InstanceName)"
    }

    Write-LocalHost -Message "Install SQL Server $($instance.SqlVersion) instances on cluster nodes"
    $installResult = Install-DbaInstance -SqlInstance $sqlInstances -Version $instance.SqlVersion -Feature Engine `
        -EngineCredential $SqlServerCredential -AgentCredential $SqlServerCredential `
        -Path $SQLServerSourcesPath -UpdateSourcePath $SQLServerPatchesPath -Authentication Credssp -Credential $AdministratorCredential -Confirm:$false
    $installResult | Format-Table
    if ( $installResult.Notes -match 'restart' ) {
        Write-LocalHost -Message 'Restarting cluster nodes'
        Restart-Computer -ComputerName $ClusterNodes
        Start-Sleep -Seconds 120
    }

    Write-LocalHost -Message 'Configure SQL Server instances: MaxMemory / MaxDop / CostThresholdForParallelism'
    Set-DbaMaxMemory -SqlInstance $sqlInstances -Max 2048 | Format-Table
    Set-DbaMaxDop -SqlInstance $sqlInstances | Format-Table
    Set-DbaSpConfigure -SqlInstance $sqlInstances -Name CostThresholdForParallelism -Value 50 | Format-Table

    Write-LocalHost -Message 'Restore and configure demo database'
    $dbUpgradeNeeded = $false
    $dbVersion = $instance.SqlVersion
    if ( $dbVersion -eq '2019' ) {
        $dbVersion = '2017'
        $dbUpgradeNeeded = $true
    }
    Restore-DbaDatabase -SqlInstance $sqlInstances[0] -Path "$BackupPath\AdventureWorks$dbVersion.bak" -DatabaseName $DatabaseName | Out-Null
    $Database = Get-DbaDatabase -SqlInstance $sqlInstances[0] -Database $DatabaseName
    $Database.RecoveryModel = 'Full'
    $Database.Alter()
    if ( $dbUpgradeNeeded ) {
        Write-LocalHost -Message "Upgrade demo database"
        Invoke-DbaDbUpgrade -SqlInstance $sqlInstances[0] -Database $DatabaseName | Format-Table
    }
    $null = Backup-DbaDatabase -SqlInstance $sqlInstances[0] -Database $DatabaseName
}

Write-LocalHost -Message 'Grant instant file initialization rights to SQL Server service account on cluster nodes'
Set-DbaPrivilege -ComputerName $ClusterNodes -Type IFI

Write-LocalHost -Message 'finished'
