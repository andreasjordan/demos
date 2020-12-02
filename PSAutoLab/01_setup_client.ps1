[CmdletBinding()]
param (
    [string]$AutoLabConfiguration = 'SqlServerLab',
    [string]$Computername = 'WIN10',
    [string]$CustomScript = 'ORDIX_special_settings.ps1'
)

$ErrorActionPreference = 'Stop'
Import-Module -Name PSAutoLab

Push-Location -Path ((Get-PSAutoLabSetting).AutoLab + '\Configurations\' + $AutoLabConfiguration)

$vmConfigurationData = Import-PowerShellDataFile -Path .\VMConfigurationData.psd1
$vmName = $vmConfigurationData.NonNodeData.Lability.EnvironmentPrefix + $Computername
$vmDomain = $vmConfigurationData.AllNodes.DomainName
$vmCredential = New-Object -TypeName PSCredential -ArgumentList "$vmDomain\Administrator", (ConvertTo-SecureString -String $vmConfigurationData.AllNodes.LabPassword -AsPlainText -Force)
$vmSession = New-PSSession -VMName $vmName -Credential $vmCredential

$psCode = @'
$ErrorActionPreference = 'Stop'

# configure package manager and repository for PowerShell and install favorite modules
Install-PackageProvider -Name Nuget -Force | Out-Null
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name dbatools

# install package manager Chocolatey and install favorite programs
Invoke-Expression -Command ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
choco install 7zip -y
choco install notepadplusplus -y
choco install tortoisesvn -y
choco install git -y
#choco install github-desktop -y
choco install vscode -y
choco install vscode-powershell -y
choco install googlechrome -y
choco install sql-server-management-studio -y
#choco install azure-data-studio -y
#choco install powerbi -y --ignore-checksums

# set my favorite explorer settings
Push-Location -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced
Set-ItemProperty -Path . -Name HideFileExt -Value 0
New-ItemProperty -Path . -Name NavPaneExpandToCurrentFolder -Value 1 -PropertyType DWord | Out-Null
New-ItemProperty -Path . -Name NavPaneShowAllFolders  -Value 1 -PropertyType DWord | Out-Null
Stop-Process -ProcessName explorer
Pop-Location

'@

$customScriptPath = (Get-PSAutoLabSetting).AutoLab + '\Resources\' + $CustomScript
if ( Test-Path -Path $customScriptPath -PathType Leaf ) {
    $psCode += Get-Content -Path $customScriptPath -Raw
}

Invoke-Command -Session $vmSession -ScriptBlock { $using:psCode | Set-Content -Path C:\setup_client.ps1 }
