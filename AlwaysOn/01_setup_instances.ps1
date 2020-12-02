[CmdletBinding()]
param (
    [string]$DomainName = 'COMPANY',
    [string]$DomainController = 'DOM1',
    [string[]]$ClusterNodes = @('SRV1', 'SRV2'),
    [string[]]$SqlInstances = @('SRV1', 'SRV2'),
    [string]$ClusterName = 'SQLCluster',
    [string]$ClusterIP = '192.168.3.70',
    [string]$SQLServerServiceAccount = 'SQLServer',
    [SecureString]$AdminPassword = (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force),
    [SecureString]$SqlPassword = (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force),
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

$administratorCredential = New-Object -TypeName PSCredential -ArgumentList "$DomainName\Administrator", $AdminPassword
$sqlServerCredential = New-Object -TypeName PSCredential -ArgumentList "$DomainName\$SQLServerServiceAccount", $SqlPassword

if ( $null -eq (Get-ADUser -Filter "Name -eq '$SQLServerServiceAccount'") ) {
    Write-LocalHost -Message 'Creating user for SQL Server service account and grant access to backup share'
    New-ADUser -Name $SQLServerServiceAccount -AccountPassword $sqlServerCredential.Password -PasswordNeverExpires:$true -Enabled:$true
    $null = Grant-SmbShareAccess -Name SQLServerBackups -AccountName "$DomainName\$SQLServerServiceAccount" -AccessRight Full -Force
}

Write-LocalHost -Message 'Import module dbatools'
Import-Module -Name dbatools -MinimumVersion 1.0.131

Write-LocalHost -Message 'Change powerplan of cluster nodes to high performance'
Set-DbaPowerPlan -ComputerName $ClusterNodes | Format-Table

Write-LocalHost -Message 'Install SQL Server instances on cluster nodes'
$installResult = Install-DbaInstance -SqlInstance $SqlInstances -Version 2017 -Feature Engine `
    -EngineCredential $sqlServerCredential -AgentCredential $sqlServerCredential `
    -Path $SQLServerSourcesPath -UpdateSourcePath $SQLServerPatchesPath -Authentication Credssp -Credential $administratorCredential -Confirm:$false
$installResult | Format-Table

Write-LocalHost -Message 'Grant instant file initialization rights to SQL Server service account on cluster nodes'
Set-DbaPrivilege -ComputerName $ClusterNodes -Type IFI

Write-LocalHost -Message 'Configure SQL Server instances: MaxMemory / MaxDop / CostThresholdForParallelism'
Set-DbaMaxMemory -SqlInstance $SqlInstances -Max 2048 | Format-Table
Set-DbaMaxDop -SqlInstance $SqlInstances | Format-Table
Set-DbaSpConfigure -SqlInstance $SqlInstances -Name CostThresholdForParallelism -Value 50 | Format-Table

Write-LocalHost -Message 'Restore and configure demo database'
Restore-DbaDatabase -SqlInstance $SqlInstances[0] -Path "$BackupPath\AdventureWorks2017.bak" -DatabaseName $DatabaseName | Out-Null
$Database = Get-DbaDatabase -SqlInstance $SqlInstances[0] -Database $DatabaseName
$Database.RecoveryModel = 'Full'
$Database.Alter()
$null = Backup-DbaDatabase -SqlInstance $SqlInstances[0] -Database $DatabaseName

Write-LocalHost -Message 'finished'
