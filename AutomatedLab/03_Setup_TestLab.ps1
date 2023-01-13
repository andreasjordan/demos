$ErrorActionPreference = 'Continue'

Import-Module -Name AutomatedLab
Import-Module -Name Posh-SSH

$LabName          = 'TestLab'
$LabNetworkBase   = '192.168.123'

$LabAdminUser     = 'User'
$LabAdminPassword = 'Passw0rd!'

# If you disable the following line, only Windows and Linux will be deployed (which is a faster test)
$LabDomainName    = 'testlab.local'

# If you disable the following line, we try to retrieve the currently used dns server address 
#$LabDnsServer = '1.1.1.1'


$MachineDefinitionDefaults = @{
    Processors = 2
    Memory     = 2GB
    Network    = $LabName
    Gateway    = "$LabNetworkBase.1"
    TimeZone   = 'W. Europe Standard Time'
}

$MachineDefinition = @(
    @{
        Name            = 'DC'
        OperatingSystem = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
        IpAddress       = "$LabNetworkBase.10"
        Roles           = 'RootDC'
    }
    @{
        Name            = 'Windows'
        OperatingSystem = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
        IpAddress       = "$LabNetworkBase.20"
    }
    @{
        Name            = 'Linux'
        OperatingSystem = 'CentOS-7'
        IpAddress       = "$LabNetworkBase.30"
    }
)


$ChocolateyPackages = @(
    'powershell-core'
    'notepadplusplus'
    '7zip'
    'vscode'
    'vscode-powershell'
    'googlechrome'
)

$PowerShellModules = @(
    'PSFramework'
    'ImportExcel'
    'Posh-SSH'
    'dbatools'
)

$DockerRunCommands = @(
#    "docker run --name SQLServer  --memory=2g -p 1433:1433 -e MSSQL_SA_PASSWORD='$LabAdminPassword' -e ACCEPT_EULA=Y -e MSSQL_PID=Express --detach --restart always mcr.microsoft.com/mssql/server:2019-latest"
#    "docker run --name Oracle     --memory=3g -p 1521:1521 -e ORACLE_PWD='$LabAdminPassword' -e ORACLE_CHARACTERSET=AL32UTF8 --detach --restart always container-registry.oracle.com/database/express:latest"
    "docker run --name MySQL      --memory=1g -p 3306:3306 -e MYSQL_ROOT_PASSWORD='$LabAdminPassword' --detach --restart always mysql:latest"
# As an alternative for MySQL:
#    "docker run --name MariaDB    --memory=1g -p 3306:3306 -e MARIADB_ROOT_PASSWORD='$LabAdminPassword' --detach --restart always mariadb:latest"
#    "docker run --name PostgreSQL --memory=1g -p 5432:5432 -e POSTGRES_PASSWORD='$LabAdminPassword' --detach --restart always postgres:latest"
# As an alternative for PostgreSQL:
#    "docker run --name PostGIS    --memory=1g -p 5432:5432 -e POSTGRES_PASSWORD='$LabAdminPassword' --detach --restart always postgres:latest"
)


### End of configuration ###


Set-PSFConfig -Module AutomatedLab -Name DoNotWaitForLinux -Value $true

New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV
Set-LabInstallationCredential -Username $LabAdminUser -Password $LabAdminPassword
if ($LabDomainName) {
    Add-LabDomainDefinition -Name $LabDomainName -AdminUser $LabAdminUser -AdminPassword $LabAdminPassword
    $MachineDefinitionDefaults.DomainName = $LabDomainName
} else {
    $MachineDefinition = $MachineDefinition | Where-Object Roles -NotContains RootDC
    if ($LabDnsServer) {
        $dnsServer1 = $LabDnsServer
    } else {
        $dnsServer1 = Get-NetAdapter | 
            Where-Object { $_.Status -eq 'Up' -and $_.Name -notlike 'vEthernet*' } |
            Get-DnsClientServerAddress -AddressFamily IPv4 | 
            Select-Object -ExpandProperty ServerAddresses -First 1
    }
    $MachineDefinitionDefaults.DnsServer1 = $dnsServer1
}
Add-LabVirtualNetworkDefinition -Name $LabName -AddressSpace "$LabNetworkBase.0/24"
foreach ($md in $MachineDefinition) {
    # $md = $MachineDefinition[0]
    $lmd = @{ }
    foreach ($key in $MachineDefinitionDefaults.Keys) {
        $lmd.$key = $MachineDefinitionDefaults.$key
    }
    foreach ($key in $md.Keys) {
        $lmd.$key = $md.$key
    }
    $lmd.ResourceName = "$LabName-$($md.Name)"
    Add-LabMachineDefinition @lmd
}
Install-Lab -NoValidation

$null = New-NetNat -Name $LabName -InternalIPInterfaceAddressPrefix "$LabNetworkBase.0/24"

Start-LabVM -ComputerName Linux

Invoke-LabCommand -ComputerName (Get-LabVM) -ActivityName 'Disable Windows updates' -ScriptBlock { 
    # https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings
    Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -Name NoAutoUpdate -Value 1
}

Invoke-LabCommand -ComputerName (Get-LabVM) -ActivityName 'Setting my favorite explorer settings' -ScriptBlock {
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name HideFileExt -Value 0
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name NavPaneShowAllFolders -Value 1
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name NavPaneExpandToCurrentFolder -Value 1
}

$pingSucceeded = Invoke-LabCommand -ComputerName Windows -ActivityName 'Testing internet access' -PassThru -ScriptBlock { 
    (Test-NetConnection -ComputerName www.google.de -WarningAction SilentlyContinue).PingSucceeded
}

if (-not $pingSucceeded) {
    Write-Warning -Message "We don't have internet access, but let's wait for 30 seconds and try again"
    Start-Sleep -Seconds 30
    $pingSucceeded = Invoke-LabCommand -ComputerName Windows -ActivityName 'Testing internet access' -PassThru -ScriptBlock { 
        (Test-NetConnection -ComputerName www.google.de -WarningAction SilentlyContinue).PingSucceeded
    }
    if (-not $pingSucceeded) {
        Write-Warning -Message "We don't have internet access, so stopping here"
        break
    }
}

Invoke-LabCommand -ComputerName Windows -ActivityName 'Installing chocolatey packages' -ArgumentList @(, $ChocolateyPackages) -ScriptBlock { 
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

Invoke-LabCommand -ComputerName Windows -ActivityName 'Installing PowerShell modules' -ArgumentList @(, $PowerShellModules) -ScriptBlock { 
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

Invoke-LabCommand -ComputerName Windows -ActivityName 'Downloading PowerShell-for-DBAs' -ScriptBlock { 
    $logPath = 'C:\DeployDebug\InstallPowerShell-for-DBAs.log'

    $ErrorActionPreference = 'Stop'

    try {
        $null = New-Item -Path C:\GitHub -ItemType Directory

        Invoke-WebRequest -Uri https://github.com/andreasjordan/PowerShell-for-DBAs/archive/refs/heads/main.zip -OutFile C:\GitHub\main.zip -UseBasicParsing
        Expand-Archive -Path C:\GitHub\main.zip -DestinationPath C:\GitHub
        Rename-Item C:\GitHub\PowerShell-for-DBAs-main -NewName PowerShell-for-DBAs
        Remove-Item C:\GitHub\main.zip

        $null = New-Item -Path C:\NuGet -ItemType Directory
        foreach ($package in 'Oracle.ManagedDataAccess', 'Oracle.ManagedDataAccess.Core', 'MySql.Data', 'Npgsql', 'Microsoft.Extensions.Logging.Abstractions') {
            Invoke-WebRequest -Uri https://www.nuget.org/api/v2/package/$package -OutFile C:\NuGet\package.zip -UseBasicParsing
            Expand-Archive -Path C:\NuGet\package.zip -DestinationPath C:\NuGet\$package
            Remove-Item -Path C:\NuGet\package.zip
        }
    } catch {
        $message = "Setting up files for PowerShell-for-DBAs failed: $_"
        $message | Add-Content -Path $logPath
        Write-Warning -Message $message
    }
}

Write-PSFMessage -Level Host -Message "Setup of Windows finished, now we wait for Linux to be reachable"
$rootCredential = [PSCredential]::new('root', (ConvertTo-SecureString -String $LabAdminPassword -AsPlainText -Force))
$linuxIp = ($MachineDefinition | Where-Object Name -eq Linux).IpAddress
while ($true) {
    try {
        $sshSession = New-SSHSession -ComputerName $linuxIp -Credential $rootCredential -Force -WarningAction SilentlyContinue -ErrorAction Stop
        break
    } catch {
        Start-Sleep -Seconds 10
    }
}

Write-PSFMessage -Level Host -Message "Installing docker on Linux"
$sshCommands = @(
    'yum -y update'
    'yum install -y yum-utils'
    'yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo'
    'yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin'
    'systemctl enable --now docker'
)
foreach ($cmd in $sshCommands) {
    $sshResult = Invoke-SSHCommand -SSHSession $sshSession -Command $cmd -TimeOut 600
    if ($sshResult.ExitStatus -gt 0) {
        Write-PSFMessage -Level Warning -Message "Command '$cmd' returned with ExitStatus $($sshResult.ExitStatus)"
        break
    }
}

Write-PSFMessage -Level Host -Message "Starting databases on docker"
foreach ($cmd in $DockerRunCommands) {
    $containerName = $cmd -replace '^.*--name ([^ ]+).*$', '$1'
    Write-PSFMessage -Level Host -Message "Starting docker container $containerName"
    $null = Invoke-SSHCommand -SSHSession $sshSession -Command $cmd -TimeOut 36000
}

Write-PSFMessage -Level Host -Message "finished"


break


vmconnect.exe localhost $LabName-Windows

Remove-Lab -Name $LabName -Confirm:$false ; Get-NetNat -Name $LabName -ErrorAction SilentlyContinue | Remove-NetNat -Confirm:$false

