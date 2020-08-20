[CmdletBinding()]
param (
    [string]$AutoLabConfiguration = 'SqlServerLab',
    [string]$Computername = 'WIN10',
    [string[]]$SQLServerIsoFiles = '*sql_server_201?*.iso',
    [string[]]$SQLServerPatches = 'SQLServer201?-KB*-x64.exe',
    [string[]]$SQLServerBackups = ('AdventureWorks201?.bak', 'StackOverflow2010.zip')
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

if ( $SQLServerIsoFiles ) {
    Write-LocalHost -Message 'Configuring SQLServerIsoFiles'

    Invoke-Command -Session $vmSession -ScriptBlock { 
        $null = New-Item -Path C:\SQLServerSources -ItemType Directory
        $null = New-SmbShare -Path C:\SQLServerSources -Name SQLServerSources
        Grant-SmbShareAccess -Name SQLServerSources -AccountName "$using:vmDomain\Administrator" -AccessRight Full -Force | Out-Null     
    }

    foreach ( $isoFile in $SQLServerIsoFiles ) {
        foreach ( $iso in Get-Item -Path ($resourcePath + $isoFile) ) {
            $isoPath = $iso.FullName
            $isoVersion = $iso.Name -replace '.*_sql_server_(\d{4})_.*', '$1'
            Write-LocalHost -Message "Starting version $isoVersion"
            Add-VMDvdDrive -VMName $vmName -Path $isoPath
            Invoke-Command -Session $vmSession -ScriptBlock { 
                $sourcesPath = "C:\SQLServerSources\SQLServer$using:isoVersion"
                $null = New-Item -Path $sourcesPath -ItemType Directory
                Copy-Item -Path D:\* -Destination $sourcesPath -Recurse
            }
            Get-VMDvdDrive -VMName $vmName | Remove-VMDvdDrive
            Write-LocalHost -Message "Finished version $isoVersion"
        }
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
