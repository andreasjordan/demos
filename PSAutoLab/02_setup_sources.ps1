[CmdletBinding()]
param (
    [string]$AutoLabConfiguration = 'PowerShellLab',
    [string]$Computername = 'WIN10',
    [string]$SQLServerISO = '*sql_server_2017*.iso',
    [string[]]$SQLServerPatches = 'SQLServer2017-KB*-x64.exe',
    [string[]]$SQLServerBackups = ('AdventureWorks2017.bak', 'StackOverflow2010.zip')
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
Write-LocalHost -Message 'Starting'
Import-Module -Name PSAutoLab

Push-Location -Path ((Get-PSAutoLabSetting).AutoLab + '\Configurations\' + $AutoLabConfiguration)

Write-LocalHost -Message 'Configuring client'
$vmConfigurationData = Import-PowerShellDataFile -Path .\VMConfigurationData.psd1
$vmName = $vmConfigurationData.NonNodeData.Lability.EnvironmentPrefix + $Computername
$vmDomain = $vmConfigurationData.AllNodes.DomainName
$vmCredential = New-Object -TypeName PSCredential -ArgumentList "$vmDomain\Administrator", (ConvertTo-SecureString -String $vmConfigurationData.AllNodes.LabPassword -AsPlainText -Force)
$vmSession = New-PSSession -VMName $vmName -Credential $vmCredential
$resourcePath = (Get-PSAutoLabSetting).AutoLab + '\Resources\'

if ( $SQLServerISO ) {
    Write-LocalHost -Message 'Configuring SQLServerISO'
    Add-VMDvdDrive -VMName $vmName -Path (Get-Item -Path ($resourcePath + $SQLServerISO)).FullName
    Invoke-Command -Session $vmSession -ScriptBlock { 
        New-SmbShare -Path D:\ -Name SQLServerSources | Out-Null
        Grant-SmbShareAccess -Name SQLServerSources -AccountName "$using:vmDomain\Administrator" -AccessRight Full -Force | Out-Null     
    }
}

if ( $SQLServerPatches ) {
    Write-LocalHost -Message 'Configuring SQLServerPatches'
    Invoke-Command -Session $vmSession -ScriptBlock { 
        New-Item -Path C:\SQLServerPatches -ItemType Directory | Out-Null
        New-SmbShare -Path C:\SQLServerPatches -Name SQLServerPatches | Out-Null
        Grant-SmbShareAccess -Name SQLServerPatches -AccountName "$using:vmDomain\Administrator" -AccessRight Full -Force | Out-Null     
    }
    foreach ( $patch in $SQLServerPatches ) {
        Copy-Item -Path ($resourcePath + $patch) -Destination C:\SQLServerPatches -ToSession $vmSession
    }
}

if ( $SQLServerBackups ) {
    Write-LocalHost -Message 'Configuring SQLServerBackups'
    Invoke-Command -Session $vmSession -ScriptBlock { 
        New-Item -Path C:\SQLServerBackups -ItemType Directory | Out-Null
        New-SmbShare -Path C:\SQLServerBackups -Name SQLServerBackups | Out-Null
        Grant-SmbShareAccess -Name SQLServerBackups -AccountName "$using:vmDomain\Administrator" -AccessRight Full -Force | Out-Null 
    }
    foreach ( $backup in $SQLServerBackups ) {
        Copy-Item -Path ($resourcePath + $backup) -Destination C:\SQLServerBackups -ToSession $vmSession
    }
}

Write-LocalHost -Message 'Finished'
