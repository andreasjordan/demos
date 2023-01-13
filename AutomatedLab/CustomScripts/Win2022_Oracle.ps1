$ErrorActionPreference = 'Continue'

Import-Module -Name AutomatedLab

$LabName = "WinOra"


<# Some commands that I use for importing, removing, stopping, starting or connecting to the lab:

Import-Lab -Name $LabName -NoValidation

Remove-Lab -Name $LabName -Confirm:$false; Get-NetNat -Name $LabName -ErrorAction SilentlyContinue | Remove-NetNat -Confirm:$false

Stop-VM -Name $LabName-*
Start-VM -Name $LabName-*

vmconnect.exe localhost $LabName-WIN-CL

#>


$LabNetworkBase = '192.168.111'
$LabDnsServer   = '1.1.1.1'

$LabAdminUser     = 'User'
$LabAdminPassword = 'Passw0rd!'

$MachineDefinition = @(
    @{
        Name            = 'WIN-CL'
        ResourceName    = "$LabName-WIN-CL"
        OperatingSystem = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
        Memory          = 4GB
        Processors      = 4
        Network         = $LabName
        IpAddress       = "$LabNetworkBase.10"
        Gateway         = "$LabNetworkBase.1"
        DnsServer1      =  $LabDnsServer
        TimeZone        = 'W. Europe Standard Time'
    }
    @{
        Name            = 'WIN-DB01'
        ResourceName    = "$LabName-WIN-DB01"
        OperatingSystem = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
        Memory          = 4GB
        Processors      = 4
        Network         = $LabName
        IpAddress       = "$LabNetworkBase.11"
        Gateway         = "$LabNetworkBase.1"
        DnsServer1      =  $LabDnsServer
        TimeZone        = 'W. Europe Standard Time'
    }
    @{
        Name            = 'WIN-DB02'
        ResourceName    = "$LabName-WIN-DB02"
        OperatingSystem = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
        Memory          = 4GB
        Processors      = 4
        Network         = $LabName
        IpAddress       = "$LabNetworkBase.12"
        Gateway         = "$LabNetworkBase.1"
        DnsServer1      =  $LabDnsServer
        TimeZone        = 'W. Europe Standard Time'
    }
)

$ChocolateyPackages = @(
    'notepadplusplus'
    '7zip'
)

$CopySoftware = @(
    "$labSources\CustomAssets\Software\OracleXE213_Win64.zip"          # Oracle Express for Windows from: https://www.oracle.com/database/technologies/xe-downloads.html
    "$labSources\CustomAssets\Software\WINDOWS.X64_193000_client.zip"  # Oracle Client 19c from: https://www.oracle.com/database/technologies/oracle19c-windows-downloads.html
)



New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV -VmPath $LabVmPath
Set-LabInstallationCredential -Username $LabAdminUser -Password $LabAdminPassword
Add-LabVirtualNetworkDefinition -Name $LabName -AddressSpace "$LabNetworkBase.0/24"
foreach ($md in $MachineDefinition) {
    Add-LabMachineDefinition @md
}
Install-Lab -NoValidation

# I use NetNat to provide internat to the virtual maschines
$null = New-NetNat -Name $LabName -InternalIPInterfaceAddressPrefix "$LabNetworkBase.0/24"


$allVMs = @( )
$clientVMs = @( )
$databaseVMs = @( )
$allVMs += Get-LabVM
$clientVMs += $allVMs | Where-Object Name -like "*-CL*"
$databaseVMs += $allVMs | Where-Object Name -like "*-DB*"


Invoke-LabCommand -ComputerName $allVMs.Name -ActivityName 'Disable Windows updates' -ScriptBlock { 
    # https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings
    Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -Name NoAutoUpdate -Value 1
}

Invoke-LabCommand -ComputerName $allVMs.Name -ActivityName 'Setting my favorite explorer settings' -ScriptBlock {
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name HideFileExt -Value 0
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name NavPaneShowAllFolders -Value 1
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name NavPaneExpandToCurrentFolder -Value 1
}

if ($HostEntries.Count -gt 0) {
    Invoke-LabCommand -ComputerName $allVMs.Name -ActivityName 'SetupHostEntries' -ArgumentList @(, $HostEntries) -ScriptBlock { 
        param($HostEntries)

        $HostEntries | Add-Content -Path C:\Windows\System32\drivers\etc\hosts
    }
}


foreach ($file in $CopySoftware) {
    Copy-LabFileItem -Path $file -ComputerName $allVMs.Name -DestinationFolderPath C:\Software
}


Invoke-LabCommand -ComputerName $databaseVMs.Name -ActivityName 'Installing Oracle Server' -ArgumentList $LabAdminPassword -ScriptBlock {
    param($Password)
    $rspContent = @(
        'INSTALLDIR=C:\oracle\product\21c\'
        "PASSWORD=$Password"
        'LISTENER_PORT=1521'
        'EMEXPRESS_PORT=5550'
        'CHAR_SET=AL32UTF8'
        'DB_DOMAIN='
    )
    $argumentList = @(
        '/s'
        '/v"RSP_FILE=C:\Software\OracleServerInstall.rsp"'
        '/v"/L*v C:\Software\OracleServerSetup.log"'
        '/v"/qn"'
    )
    Expand-Archive -Path C:\Software\OracleXE213_Win64.zip -DestinationPath C:\Software\OracleXE213_Win64
    $rspContent | Set-Content -Path C:\Software\OracleServerInstall.rsp
    Start-Process -FilePath C:\Software\OracleXE213_Win64\setup.exe -ArgumentList $argumentList -WorkingDirectory C:\Software -NoNewWindow -Wait
}

$numberOfOracleServices = Invoke-LabCommand -ComputerName $databaseVMs.Name -ActivityName 'Testing Oracle Server' -PassThru -ScriptBlock {
    (Get-Service | Where-Object Name -like Oracle*).Count
}

if ($numberOfOracleServices -lt 5) {
    Write-Warning -Message "We only have $numberOfOracleServices oracle services - so installation failed. Please rebuild the lab, will start removing the lab now..."
    Remove-Lab -Name $LabName -Confirm:$false
    Get-NetNat -Name $LabName -ErrorAction SilentlyContinue | Remove-NetNat -Confirm:$false
    break
}



<#

#------------------------------------------------------------------------------
#Name       : INSTALL_TYPE
#Datatype   : String
#Description: Installation type of the component.
#
#             The following choices are available. The value should contain
#             only one of these choices.
#               - Administrator
#               - Runtime
#               - InstantClient
#               - Custom
#
#Example    : INSTALL_TYPE = Administrator
#------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Name       : oracle.install.client.customComponents
# Datatype   : StringList
#
# This property is considered only if INSTALL_TYPE is set to "Custom"
#
# Description: List of Client Components you would like to install
#
#   The following choices are available. You may specify any
#   combination of these choices.  The components you choose should
#   be specified in the form "internal-component-name:version"
#   Below is a list of components you may specify to install.
#
# oracle.sqlj:19.0.0.0.0 -- "Oracle SQLJ"
# oracle.rdbms.util:19.0.0.0.0 -- "Oracle Database Utilities"
# oracle.javavm.client:19.0.0.0.0 -- "Oracle Java Client"
# oracle.sqlplus:19.0.0.0.0 -- "SQL*Plus"
# oracle.dbjava.jdbc:19.0.0.0.0 -- "Oracle JDBC/THIN Interfaces"
# oracle.ldap.client:19.0.0.0.0 -- "Oracle Internet Directory Client"
# oracle.rdbms.oci:19.0.0.0.0 -- "Oracle Call Interface (OCI)"
# oracle.precomp:19.0.0.0.0 -- "Oracle Programmer"
# oracle.xdk:19.0.0.0.0 -- "Oracle XML Development Kit"
# oracle.network.aso:19.0.0.0.0 -- "Oracle Advanced Security"
# oracle.oraolap.mgmt:19.0.0.0.0 -- "OLAP Analytic Workspace Manager and Worksheet"
# oracle.network.client:19.0.0.0.0 -- "Oracle Net"
# oracle.network.cman:19.0.0.0.0 -- "Oracle Connection Manager"
# oracle.network.listener:19.0.0.0.0 -- "Oracle Net Listener"
# oracle.ordim.client:19.0.0.0.0 -- "Oracle Multimedia Client Option"
# oracle.odbc:19.0.0.0.0 -- "Oracle ODBC Driver"
# oracle.has.client:19.0.0.0.0 -- "Oracle Clusterware High Availability API"
# oracle.dbdev:19.0.0.0.0 -- "Oracle SQL Developer"
# oracle.rdbms.scheduler:19.0.0.0.0 -- "Oracle Scheduler Agent" 
# oracle.ntoramts:19.0.0.0.0 -- "Oracle Services For Microsoft Transaction Server"
# oracle.ntoledb:19.0.0.0.0 -- "Oracle Provider for OLE DB"
# oracle.ntoledb.odp_net_2:19.0.0.0.0 -- "Oracle Data Provider for .NET"
# oracle.aspnet_2:19.0.0.0.0 -- "Oracle Providers for ASP.NET" 
#
# Example    : oracle.install.client.customComponents="oracle.precomp:19.0.0.0.0","oracle.oraolap.mgmt:19.0.0.0.0","oracle.rdbms.scheduler:19.0.0.0.0"
#-------------------------------------------------------------------------------


#>

Invoke-LabCommand -ComputerName $clientVMs.Name -ActivityName 'Installing Oracle Client' -ScriptBlock { 
    $rspContent = @(
        'ORACLE_BASE=C:\oracle'
        'ORACLE_HOME=C:\oracle\product\19.0.0\client_1'
        'oracle.install.responseFileVersion=/oracle/install/rspfmt_clientinstall_response_schema_v19.0.0'
        'oracle.install.IsBuiltInAccount=true'
        'oracle.install.client.installType=Custom'
        'oracle.install.client.customComponents=oracle.ntoledb.odp_net_2:19.0.0.0.0,oracle.sqlplus:19.0.0.0.0,oracle.rdbms.util:19.0.0.0.0'
    )
    $argumentList = @(
        '-silent'
        '-responseFile C:\Software\OracleClientInstall.rsp'
        '-noConsole'
    )
    Expand-Archive -Path C:\Software\WINDOWS.X64_193000_client.zip -DestinationPath C:\Software\WINDOWS.X64_193000_client
    $rspContent | Set-Content -Path C:\Software\OracleClientInstall.rsp
    Start-Process -FilePath C:\Software\WINDOWS.X64_193000_client\client\setup.exe -ArgumentList $argumentList -Wait
}


if ($ChocolateyPackages.Count -gt 0) {
    Invoke-LabCommand -ComputerName $allVMs.Name -ActivityName 'Installing chocolatey packages' -ArgumentList @(, $ChocolateyPackages) -ScriptBlock { 
        param($ChocolateyPackages)

        $ErrorActionPreference = 'Stop'

        $logPath = 'C:\DeployDebug\InstallChocolateyPackages.log'

        try {
            Invoke-Expression -Command ([System.Net.WebClient]::new().DownloadString('https://chocolatey.org/install.ps1')) *>$logPath
            $installResult = choco install $ChocolateyPackages --confirm --limitoutput --no-progress *>&1
            if ($installResult -match 'Warnings:') {
                Write-Warning -Message 'Chocolatey generated warnings'
            }
            $info = $installResult -match 'Chocolatey installed (\d+)/(\d+) packages' | Select-Object -First 1
            if ($info -match 'Chocolatey installed (\d+)/(\d+) packages') {
                if ($Matches[1] -ne $Matches[2]) {
                    Write-Warning -Message "Chocolatey only installed $($Matches[1]) of $($Matches[2]) packages"
                    $installResult | Add-Content -Path $logPath
                }
            } else {
                Write-Warning -Message "InstallResult: $installResult"
            }
        } catch {
            $message = "Setting up Chocolatey failed: $_"
            $message | Add-Content -Path $logPath
            Write-Warning -Message $message
        }
    }
}


if ($PowerShellModules.Count -gt 0) {
    Invoke-LabCommand -ComputerName $allVMs.Name -ActivityName 'Installing PowerShell modules' -ArgumentList @(, $PowerShellModules) -ScriptBlock { 
        param($PowerShellModules)

        $logPath = 'C:\DeployDebug\InstallPowerShellModules.log'

        $ErrorActionPreference = 'Stop'

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            if ((Get-PackageProvider -ListAvailable).Name -notcontains 'Nuget') {
                $null = Install-PackageProvider -Name Nuget -Force
                'Install-PackageProvider ok' | Add-Content -Path $logPath
            } else {
                'Install-PackageProvider not needed' | Add-Content -Path $logPath
            }
            if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                'Set-PSRepository ok' | Add-Content -Path $logPath
            } else {
                'Set-PSRepository not needed' | Add-Content -Path $logPath
            }
            foreach ($name in $PowerShellModules) {
                if (-not (Get-Module -Name $name -ListAvailable)) {
                    Install-Module -Name $name
                    "Install-Module $name ok" | Add-Content -Path $logPath
                } else {
                    "Install-Module $name not needed" | Add-Content -Path $logPath
                }
            }
        } catch {
            $message = "Setting up PowerShell failed: $_"
            $message | Add-Content -Path $logPath
            Write-Warning -Message $message
        }
    }
}

