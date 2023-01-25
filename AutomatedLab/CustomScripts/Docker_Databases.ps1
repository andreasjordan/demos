$ErrorActionPreference = 'Continue'

Import-Module -Name AutomatedLab
Import-Module -Name Posh-SSH

$LabName          = 'DockerDatabases'
$LabNetworkBase   = '192.168.123'

$LabAdminUser     = 'User'
$LabAdminPassword = 'Passw0rd!'

$MachineDefinition = @{
    Name            = $LabName
    OperatingSystem = 'CentOS-7'
    Processors      = 4
    Network         = $LabName
    IpAddress       = "$LabNetworkBase.10"
    Gateway         = "$LabNetworkBase.1"
    DnsServer1      = '1.1.1.1'
    TimeZone        = 'W. Europe Standard Time'
}

<# Some commands that I use for importing, removing, stopping, starting or connecting to the lab:

Import-Lab -Name $LabName -NoValidation

Remove-Lab -Name $LabName -Confirm:$false; Get-NetNat -Name $LabName -ErrorAction SilentlyContinue | Remove-NetNat -Confirm:$false

Stop-VM -Name $MachineDefinition.Name
Start-VM -Name $MachineDefinition.Name

#>

$password = $LabAdminPassword
$hostname = 'localhost'

$DatabaseDefinition = @(
    [PSCustomObject]@{
        ContainerName     = 'SQLServer'
        ContainerImage    = 'mcr.microsoft.com/mssql/server:2022-latest'
        ContainerMemoryGB = 2
        ContainerConfig   = "-p 1433:1433 -e MSSQL_SA_PASSWORD='$password' -e ACCEPT_EULA=Y -e MSSQL_PID=Express"
        Instance          = $hostname
        AdminPassword     = $password
        SqlQueries        = @(
            "CREATE LOGIN StackOverflow WITH PASSWORD = '$password', CHECK_POLICY = OFF"
            'CREATE DATABASE StackOverflow'
            'ALTER AUTHORIZATION ON DATABASE::StackOverflow TO StackOverflow'
        )
    }
    [PSCustomObject]@{
        ContainerName     = 'Oracle'
        ContainerImage    = 'container-registry.oracle.com/database/express:latest'
        ContainerMemoryGB = 3
        ContainerConfig   = "-p 1521:1521 -e ORACLE_PWD='$password' -e ORACLE_CHARACTERSET=AL32UTF8"
        Instance          = "$hostname/XEPDB1"
        AdminPassword     = $password
        SqlQueries        = @(
            'CREATE USER stackoverflow IDENTIFIED BY "{0}" DEFAULT TABLESPACE users QUOTA UNLIMITED ON users TEMPORARY TABLESPACE temp' -f $password
            'GRANT CREATE SESSION TO stackoverflow'
            'GRANT ALL PRIVILEGES TO stackoverflow'
            'CREATE USER geodemo IDENTIFIED BY "{0}" DEFAULT TABLESPACE users QUOTA UNLIMITED ON users TEMPORARY TABLESPACE temp' -f $password
            'GRANT CREATE SESSION TO geodemo'
            'GRANT ALL PRIVILEGES TO geodemo'
        )
    }
    [PSCustomObject]@{
        ContainerName     = 'MySQL'
        ContainerImage    = 'mysql:latest'
        ContainerMemoryGB = 1
        ContainerConfig   = "-p 3306:3306 -e MYSQL_ROOT_PASSWORD='$password'"
        Instance          = $hostname
        AdminPassword     = $password
        SqlQueries        = @(
            #'SET GLOBAL local_infile=1'
            'SET PERSIST local_infile=1'
            "CREATE USER 'stackoverflow'@'%' IDENTIFIED BY '$password'"
            'CREATE DATABASE stackoverflow'
            "GRANT ALL PRIVILEGES ON stackoverflow.* TO 'stackoverflow'@'%'"
        )
    }
    [PSCustomObject]@{
        ContainerName     = 'MariaDB'
        ContainerImage    = 'mariadb:latest'
        ContainerMemoryGB = 1
        ContainerConfig   = "-p 13306:3306 -e MARIADB_ROOT_PASSWORD='$password'"
        Instance          = "$($hostname):13306"
        AdminPassword     = $password
        SqlQueries        = @(
            "CREATE USER 'stackoverflow'@'%' IDENTIFIED BY '$password'"
            'CREATE DATABASE stackoverflow'
            "GRANT ALL PRIVILEGES ON stackoverflow.* TO 'stackoverflow'@'%'"
        )
    }
    [PSCustomObject]@{
        ContainerName     = 'PostgreSQL'
        ContainerImage    = 'postgres:latest'
        ContainerMemoryGB = 1
        ContainerConfig   = "-p 5432:5432 -e POSTGRES_PASSWORD='$password'"
        Instance          = $hostname
        AdminPassword     = $password
        SqlQueries        = @(
            "CREATE USER stackoverflow WITH PASSWORD '$password'"
            'CREATE DATABASE stackoverflow WITH OWNER stackoverflow'
        )
    }
    [PSCustomObject]@{
        ContainerName     = 'PostGIS'
        ContainerImage    = 'postgis/postgis'
        ContainerMemoryGB = 1
        ContainerConfig   = "-p 15432:5432 -e POSTGRES_PASSWORD='$password'"
        Instance          = "$($hostname):15432"
        AdminPassword     = $password
        SqlQueries        = @(
            "CREATE USER geodemo WITH PASSWORD '$password'"
            'CREATE DATABASE geodemo WITH OWNER geodemo'
            '\connect geodemo'
            'CREATE EXTENSION postgis'
        )
    }
)

# $DatabaseDefinition = $DatabaseDefinition | Where-Object ContainerName -in SQLServer, Oracle
$DatabaseDefinition = $DatabaseDefinition | Out-GridView -Title 'Select docker conatiners to start' -OutputMode Multiple


### End of configuration ###


$MachineDefinition.Memory = 2GB + ($DatabaseDefinition.ContainerMemoryGB | Measure-Object -Sum).Sum * 1GB

Set-PSFConfig -Module AutomatedLab -Name DoNotWaitForLinux -Value $true

New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV
Set-LabInstallationCredential -Username $LabAdminUser -Password $LabAdminPassword
Add-LabVirtualNetworkDefinition -Name $LabName -AddressSpace "$LabNetworkBase.0/24"
Add-LabMachineDefinition @MachineDefinition
Install-Lab -NoValidation

$null = New-NetNat -Name $LabName -InternalIPInterfaceAddressPrefix "$LabNetworkBase.0/24"

Start-LabVM -ComputerName $MachineDefinition.Name

# Now the linux maschine is started and will be installed automatically. We just have to wait...


Write-PSFMessage -Level Host -Message "Waiting until we can connect and open ssh and sftp session"
$rootCredential = [PSCredential]::new('root', (ConvertTo-SecureString -String $LabAdminPassword -AsPlainText -Force))
$linuxIp = $MachineDefinition.IpAddress
while ($true) {
    try {
        if (-not $sshSession) {
            $sshSession = New-SSHSession -ComputerName $linuxIp -Credential $rootCredential -Force -WarningAction SilentlyContinue -ErrorAction Stop
        }
        if (-not $sftpSession) {
            $sftpSession = New-SFTPSession -ComputerName $linuxIp -Credential $rootCredential -Force -WarningAction SilentlyContinue -ErrorAction Stop
        }
        break
    } catch {
        Write-PSFMessage -Level Host -Message "Still waiting ... [$($sshSession.Connected) / $($sftpSession.Connected)] ($_)"
        Start-Sleep -Seconds 60
    }
}


# As we do a lot of ssh commands via Invoke-SSHCommand from Posh-SSH lets use a wrapper to save some lines of code
function Invoke-MySSHCommand {
    param(
        [SSH.SshSession]$SSHSession,
        [string[]]$Command,
        [int]$TimeOut = 9999,
        [switch]$ShowOutput
    )
    $returnValue = $true
    foreach ($cmd in $Command) {
        while ($true) {
            try {
                $sshResult = Invoke-SSHCommand -SSHSession $SSHSession -Command $cmd -EnsureConnection -TimeOut $TimeOut -ShowStandardOutputStream:$ShowOutput -ShowErrorOutputStream:$ShowOutput -ErrorAction Stop
                break
            } catch {
                Write-PSFMessage -Level Host -Message "Command '$cmd' failed with $_"
                Start-Sleep -Seconds 10
            }
        }
        if ($sshResult.ExitStatus -gt 0) {
            Write-PSFMessage -Level Warning -Message "Command '$cmd' returned with ExitStatus $($sshResult.ExitStatus)"
            $returnValue = $false
            break
        }
    }
    return $returnValue
}

# To stop the execution if an ssh command failed we use this command in a pipeline after Invoke-MySSHCommand
function Stop-ExecutionOnFailure {
    param(
        [Parameter(ValueFromPipeline = $true)][boolean]$InputObject
    )
    if (-not $InputObject) {
        break
    }
}


Write-PSFMessage -Level Host -Message "Updating packages on Linux"
$sshCommands = @(
    'yum -y update'
)
Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands | Stop-ExecutionOnFailure

Write-PSFMessage -Level Host -Message "Installing docker on Linux"
$sshCommands = @(
    'yum install -y yum-utils'
    'yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo'
    'yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin'
    'systemctl enable --now docker'
)
Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands | Stop-ExecutionOnFailure

Write-PSFMessage -Level Host -Message "Installing 7zip on Linux"
$sshCommands = @(
    'yum install -y epel-release'
    'yum install -y p7zip'
)
Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands | Stop-ExecutionOnFailure

Write-PSFMessage -Level Host -Message "Installing PowerShell modules"
$sshCommands = @(
    "pwsh -c 'Set-PSRepository -Name PSGallery -InstallationPolicy Trusted'"
    "pwsh -c 'Install-Module -Name PSFramework'"
    "pwsh -c 'Install-Module -Name Microsoft.PowerShell.ConsoleGuiTools'"
)
Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands | Stop-ExecutionOnFailure

Write-PSFMessage -Level Host -Message "Copying and loading or pulling and saving docker images"
foreach ($db in $DatabaseDefinition) {
    $imagePath = "$labSources\CustomAssets\DockerImages\$($db.ContainerName).tar.gz"
    if (Test-Path -Path $imagePath) {
        Write-PSFMessage -Level Host -Message "Found saved image for $($db.ContainerName), will copy and load image"
        Set-SFTPItem -SFTPSession $sftpSession -Destination /tmp -Path $imagePath -ErrorAction Stop
        $sshCommands = @(
            "docker load -i /tmp/$($db.ContainerName).tar.gz"
            "rm /tmp/$($db.ContainerName).tar.gz"
        )
        Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands | Stop-ExecutionOnFailure
    } else {
        Write-PSFMessage -Level Host -Message "No saved image found for $($db.ContainerName), will pull and save image"
        $sshCommands = @(
            "docker pull $($db.ContainerImage)"
            "docker save -o /tmp/$($db.ContainerName).tar $($db.ContainerImage)"
            "gzip /tmp/$($db.ContainerName).tar"
        )
        Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands | Stop-ExecutionOnFailure
        Get-SFTPItem -SFTPSession $sftpSession -Path "/tmp/$($db.ContainerName).tar.gz" -Destination "$labSources\CustomAssets\DockerImages" -ErrorAction Stop
    }
}

Write-PSFMessage -Level Host -Message "Starting databases on docker"
foreach ($db in $DatabaseDefinition) {
    Write-PSFMessage -Level Host -Message "Starting docker container $($db.ContainerName)"
    $sshCommands = @(
        "docker run --name $($db.ContainerName) --memory=$($db.ContainerMemoryGB)g $($db.ContainerConfig) --detach --restart always $($db.ContainerImage)"
    )
    Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands | Stop-ExecutionOnFailure
}

Write-PSFMessage -Level Host -Message "Downloading PowerShell-for-DBAs"
$sshCommands = @(
    'curl -sL https://github.com/andreasjordan/PowerShell-for-DBAs/tarball/main | tar zx --transform "s,^[^/]+,PowerShell-for-DBAs,x"'
)
Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands | Stop-ExecutionOnFailure

Write-PSFMessage -Level Host -Message "Copying database definition information to Linux"
$DatabaseDefinition | ConvertTo-Json | Set-Content -Path "$labSources\tmp_DatabaseDefinition.json"
Set-SFTPItem -SFTPSession $sftpSession -Destination /tmp -Path "$labSources\tmp_DatabaseDefinition.json" -ErrorAction Stop
Remove-Item -Path "$labSources\tmp_DatabaseDefinition.json"

Write-PSFMessage -Level Host -Message "Creating sample databases"
$sshCommands = @(
    'pwsh ./PowerShell-for-DBAs/PowerShell/01_SetupSampleDatabases.ps1'
)
Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands -ShowOutput | Stop-ExecutionOnFailure

Write-PSFMessage -Level Host -Message "Creating sample schemas"
$sshCommands = @(
    'pwsh ./PowerShell-for-DBAs/PowerShell/02_SetupSampleSchemas.ps1'
)
Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands -ShowOutput | Stop-ExecutionOnFailure

Write-PSFMessage -Level Host -Message "Importing sample data from JSON"
$sshCommands = @(
    'pwsh ./PowerShell-for-DBAs/PowerShell/03_ImportSampleDataFromJson.ps1'
)
Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands -ShowOutput | Stop-ExecutionOnFailure

Write-PSFMessage -Level Host -Message "Importing sample data from Stackexchange"
$sshCommands = @(
    'pwsh ./PowerShell-for-DBAs/PowerShell/04_ImportSampleDataFromStackexchange.ps1'
)
Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands -ShowOutput | Stop-ExecutionOnFailure

Write-PSFMessage -Level Host -Message "Importing sample geographic data"
$sshCommands = @(
    'pwsh ./PowerShell-for-DBAs/PowerShell/05_ImportSampleGeographicData.ps1'
)
Invoke-MySSHCommand -SSHSession $sshSession -Command $sshCommands -ShowOutput | Stop-ExecutionOnFailure

Write-PSFMessage -Level Host -Message "finished"

<#

Logging:

11:11:23|00:00:00|00:00:00.000| Initialization
11:11:23|00:00:00|00:00:00.167| - Host operating system version: 'Microsoft Windows 10 Pro, 10.0.19045.0'
11:11:23|00:00:00|00:00:00.175| - Creating new lab definition with name 'DockerDatabases'
11:11:23|00:00:00|00:00:00.190| - Location of lab definition files will be 'C:\ProgramData\AutomatedLab/Labs/DockerDatabases'
11:11:24|00:00:00|00:00:00.817| - Location of LabSources folder is 'C:\AutomatedLab-Sources'
11:11:24|00:00:00|00:00:00.000| - Auto-adding ISO files
11:11:24|00:00:01|00:00:00.508|   - Added 'C:\AutomatedLab-Sources\ISOs\2022_x64_EN_Eval.iso'
11:11:24|00:00:01|00:00:00.523|   - Added 'C:\AutomatedLab-Sources\ISOs\CentOS-7-x86_64-DVD-2207-02.iso'
11:11:25|00:00:01|00:00:00.532|   - Done
11:11:25|00:00:01|00:00:00.555| - Path for VMs specified as 'C:\AutomatedLab-VMs'
11:11:25|00:00:01|00:00:00.000| - Adding Hyper-V machine definition 'DockerDatabases'
11:11:27|00:00:04|00:00:02.080|   - Done
11:11:28|00:00:04|00:00:02.556| Estimated (additional) local drive space needed for all machines: 2 GB
11:11:28|00:00:04|00:00:02.600| Location of Hyper-V machines will be 'C:\AutomatedLab-VMs'
11:11:28|00:00:04|00:00:02.901| Done
11:11:29|00:00:05|00:00:03.644| Lab 'DockerDatabases' hosted on 'HyperV' imported with 1 machines
11:11:29|00:00:06|00:00:00.000| Creating virtual networks
11:11:29|00:00:06|00:00:00.000| - Creating Hyper-V virtual network 'DockerDatabases'
11:11:33|00:00:10|00:00:04.061|   - Done
11:11:34|00:00:10|00:00:04.157| - Done
11:11:34|00:00:10|00:00:04.232| done
11:11:34|00:00:10|00:00:00.000| Creating Additional Disks
11:11:34|00:00:10|00:00:00.142| - Done
11:11:34|00:00:10|00:00:00.000| Creating VMs
11:11:34|00:00:10|00:00:00.187| - The hosts file has been added 1 records. Clean them up using 'Remove-Lab' or manually if needed
11:11:34|00:00:10|00:00:00.000| - Waiting for all machines to finish installing
11:11:34|00:00:10|00:00:00.000|   - Creating HyperV machine 'DockerDatabases'....
11:11:45|00:00:21|00:00:10.469|     - Done
11:11:45|00:00:21|00:00:10.475|   - Done
11:11:45|00:00:21|00:00:10.777| - Done
11:11:45|00:00:22|00:00:00.000| Starting remaining machines
11:11:45|00:00:22|00:00:00.022| - Waiting for machines to start up...Done
11:11:46|00:00:22|00:00:00.000| Installing RDS certificates of lab machines
11:11:46|00:00:22|00:00:00.034| - Done
11:11:48|00:00:25|00:00:02.688| .
[11:11:48][Docker_Databases.ps1] Waiting until we can connect and open ssh and sftp session
[11:11:58][Docker_Databases.ps1] Still waiting ... [ / ] (Connection failed to establish within 10000 milliseconds.)
[11:13:09][Docker_Databases.ps1] Still waiting ... [ / ] (Connection failed to establish within 10000 milliseconds.)
[11:14:11][Docker_Databases.ps1] Still waiting ... [ / ] (Es konnte keine Verbindung hergestellt werden, da der Zielcomputer die Verbindung verweigerte)
[11:15:13][Docker_Databases.ps1] Still waiting ... [ / ] (Es konnte keine Verbindung hergestellt werden, da der Zielcomputer die Verbindung verweigerte)
[11:16:15][Docker_Databases.ps1] Still waiting ... [ / ] (Es konnte keine Verbindung hergestellt werden, da der Zielcomputer die Verbindung verweigerte)
[11:17:15][Docker_Databases.ps1] Updating packages on Linux
[11:18:28][Docker_Databases.ps1] Installing docker on Linux
[11:19:00][Docker_Databases.ps1] Installing 7zip on Linux
[11:19:10][Docker_Databases.ps1] Installing PowerShell modules
[11:19:30][Docker_Databases.ps1] Copying and loading or pulling and saving docker images
[11:19:30][Docker_Databases.ps1] Found saved image for SQLServer, will copy and load image
[11:20:05][Docker_Databases.ps1] Found saved image for Oracle, will copy and load image
[11:23:54][Docker_Databases.ps1] Found saved image for MySQL, will copy and load image
[11:24:06][Docker_Databases.ps1] Found saved image for MariaDB, will copy and load image
[11:24:16][Docker_Databases.ps1] Found saved image for PostgreSQL, will copy and load image
[11:24:26][Docker_Databases.ps1] Found saved image for PostGIS, will copy and load image
[11:24:37][Docker_Databases.ps1] Starting databases on docker
[11:24:37][Docker_Databases.ps1] Starting docker container SQLServer
[11:24:38][Docker_Databases.ps1] Starting docker container Oracle
[11:24:39][Docker_Databases.ps1] Starting docker container MySQL
[11:24:39][Docker_Databases.ps1] Starting docker container MariaDB
[11:24:39][Docker_Databases.ps1] Starting docker container PostgreSQL
[11:24:40][Docker_Databases.ps1] Starting docker container PostGIS
[11:24:41][Docker_Databases.ps1] Downloading PowerShell-for-DBAs
[11:24:42][Docker_Databases.ps1] Copying database definition information to Linux
[11:24:42][Docker_Databases.ps1] Creating sample databases
[09:24:47][01_SetupSampleDatabases.ps1] Waiting for connection to SQL Server
[09:25:18][01_SetupSampleDatabases.ps1] Creating sample database and user on SQL Server finished
[09:25:20][01_SetupSampleDatabases.ps1] Waiting for connection to Oracle
[09:25:20][01_SetupSampleDatabases.ps1] Creating sample users on Oracle finished
[09:25:27][01_SetupSampleDatabases.ps1] Waiting for connection to MySQL
[09:25:27][01_SetupSampleDatabases.ps1] Creating sample database and user on MySQL finished
[09:25:27][01_SetupSampleDatabases.ps1] Waiting for connection to MariaDB
[09:25:27][01_SetupSampleDatabases.ps1] Creating sample database and user on MariaDB finished
[09:25:31][01_SetupSampleDatabases.ps1] Waiting for connection to PostgreSQL
[09:25:31][01_SetupSampleDatabases.ps1] Creating sample database and user on PostgreSQL finished
[09:25:31][01_SetupSampleDatabases.ps1] Waiting for connection to PostGIS
[09:25:31][01_SetupSampleDatabases.ps1] Creating sample database and user on PostGIS finished
[11:25:31][Docker_Databases.ps1] Creating sample schemas
[09:25:33][02_SetupSampleSchemas.ps1] Creating sample schema on SQL Server finished
[09:25:34][02_SetupSampleSchemas.ps1] Creating sample schema on Oracle finished
[09:25:34][02_SetupSampleSchemas.ps1] Creating sample schema on MySQL finished
[09:25:35][02_SetupSampleSchemas.ps1] Creating sample schema on MariaDB finished
[09:25:35][02_SetupSampleSchemas.ps1] Creating sample schema on PostgreSQL finished
[09:25:35][02_SetupSampleSchemas.ps1] Creating sample schema on PostGIS finished
[11:25:34][Docker_Databases.ps1] Importing sample data from JSON
[09:25:40][03_ImportSampleDataFromJson.ps1] Importing sample data to SQL Server finished in 3.0137833 seconds
[09:25:46][03_ImportSampleDataFromJson.ps1] Importing sample data to Oracle finished in 5.2271296 seconds
[09:25:48][03_ImportSampleDataFromJson.ps1] Importing sample data to MySQL finished in 2.2646515 seconds
[09:25:50][03_ImportSampleDataFromJson.ps1] Importing sample data to MariaDB finished in 1.801707 seconds
[09:26:14][03_ImportSampleDataFromJson.ps1] Importing sample data to PostgreSQL finished in 23.9747867 seconds
[11:26:13][Docker_Databases.ps1] Importing sample data from Stackexchange
[09:26:20][04_ImportSampleDataFromStackexchange.ps1] Dowload sample data finished in 4.0068473 seconds
[09:26:25][04_ImportSampleDataFromStackexchange.ps1] Importing sample data to SQL Server finished in 5.9283759 seconds
[09:26:34][04_ImportSampleDataFromStackexchange.ps1] Importing sample data to Oracle finished in 8.6976567 seconds
[09:26:41][04_ImportSampleDataFromStackexchange.ps1] Importing sample data to MySQL finished in 6.5348029 seconds
[09:26:46][04_ImportSampleDataFromStackexchange.ps1] Importing sample data to MariaDB finished in 5.244922 seconds
[09:27:40][04_ImportSampleDataFromStackexchange.ps1] Importing sample data to PostgreSQL finished in 54.2771984 seconds
[11:27:40][Docker_Databases.ps1] Importing sample geographic data
[09:27:52][05_ImportSampleGeographicData.ps1] Importing sample geographic data to Oracle finished in 4.8504032 seconds
[09:27:54][05_ImportSampleGeographicData.ps1] Importing sample geographic data to PostGIS finished in 2.638402 seconds
[11:27:54][Docker_Databases.ps1] finished

#>