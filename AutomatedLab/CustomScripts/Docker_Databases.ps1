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

$DatabaseDefinition = @(
    [PSCustomObject]@{
        ContainerName     = 'SQLServer'
        ContainerImage    = 'mcr.microsoft.com/mssql/server:2019-latest'
        ContainerMemoryGB = 2
        ContainerConfig   = "-p 1433:1433 -e MSSQL_SA_PASSWORD='$LabAdminPassword' -e ACCEPT_EULA=Y -e MSSQL_PID=Express"
        ImagePath         = "$labSources\CustomAssets\DockerImages\sqlserver.tar.gz"
        Instance          = 'localhost'
        AdminPassword     = $LabAdminPassword
        SqlQueries        = @(
            "CREATE LOGIN StackOverflow WITH PASSWORD = '$LabAdminPassword', CHECK_POLICY = OFF"
            'CREATE DATABASE StackOverflow'
            'ALTER AUTHORIZATION ON DATABASE::StackOverflow TO StackOverflow'
        )
    }
    [PSCustomObject]@{
        ContainerName     = 'Oracle'
        ContainerImage    = 'container-registry.oracle.com/database/express:latest'
        ContainerMemoryGB = 3
        ContainerConfig   = "-p 1521:1521 -e ORACLE_PWD='$LabAdminPassword' -e ORACLE_CHARACTERSET=AL32UTF8"
        ImagePath         = "$labSources\CustomAssets\DockerImages\oracle.tar.gz"
        Instance          = 'localhost/XEPDB1'
        AdminPassword     = $LabAdminPassword
        SqlQueries        = @(
            'CREATE USER stackoverflow IDENTIFIED BY "{0}" DEFAULT TABLESPACE users QUOTA UNLIMITED ON users TEMPORARY TABLESPACE temp' -f $LabAdminPassword
            'GRANT CREATE SESSION TO stackoverflow'
            'GRANT ALL PRIVILEGES TO stackoverflow'
            'CREATE USER geodemo IDENTIFIED BY "{0}" DEFAULT TABLESPACE users QUOTA UNLIMITED ON users TEMPORARY TABLESPACE temp' -f $LabAdminPassword
            'GRANT CREATE SESSION TO geodemo'
            'GRANT ALL PRIVILEGES TO geodemo'
        )
    }
    [PSCustomObject]@{
        ContainerName     = 'MySQL'
        ContainerImage    = 'mysql:latest'
        ContainerMemoryGB = 1
        ContainerConfig   = "-p 3306:3306 -e MYSQL_ROOT_PASSWORD='$LabAdminPassword'"
        ImagePath         = "$labSources\CustomAssets\DockerImages\mysql.tar.gz"
        Instance          = 'localhost'
        AdminPassword     = $LabAdminPassword
        SqlQueries        = @(
            "CREATE USER 'stackoverflow'@'%' IDENTIFIED BY '$LabAdminPassword'"
            'CREATE DATABASE stackoverflow'
            "GRANT ALL PRIVILEGES ON stackoverflow.* TO 'stackoverflow'@'%'"
        )
    }
    [PSCustomObject]@{
        ContainerName     = 'MariaDB'
        ContainerImage    = 'mariadb:10.9'
        # Reason for 10.9: https://stackoverflow.com/questions/74060289/mysqlconnection-open-system-invalidcastexception-object-cannot-be-cast-from-d
        ContainerMemoryGB = 1
        ContainerConfig   = "-p 13306:3306 -e MARIADB_ROOT_PASSWORD='$LabAdminPassword'"
        ImagePath         = "$labSources\CustomAssets\DockerImages\mariadb.tar.gz"
        Instance          = 'localhost:13306'
        AdminPassword     = $LabAdminPassword
        SqlQueries        = @(
            "CREATE USER 'stackoverflow'@'%' IDENTIFIED BY '$LabAdminPassword'"
            'CREATE DATABASE stackoverflow'
            "GRANT ALL PRIVILEGES ON stackoverflow.* TO 'stackoverflow'@'%'"
        )
    }
    [PSCustomObject]@{
        ContainerName     = 'PostgreSQL'
        ContainerImage    = 'postgres:latest'
        ContainerMemoryGB = 1
        ContainerConfig   = "-p 5432:5432 -e POSTGRES_PASSWORD='$LabAdminPassword'"
        ImagePath         = "$labSources\CustomAssets\DockerImages\postgresql.tar.gz"
        Instance          = 'localhost'
        AdminPassword     = $LabAdminPassword
        SqlQueries        = @(
            "CREATE USER stackoverflow WITH PASSWORD '$LabAdminPassword'"
            'CREATE DATABASE stackoverflow WITH OWNER stackoverflow'
        )
    }
    [PSCustomObject]@{
        ContainerName     = 'PostGIS'
        ContainerImage    = 'postgis/postgis'
        ContainerMemoryGB = 1
        ContainerConfig   = "-p 15432:5432 -e POSTGRES_PASSWORD='$LabAdminPassword'"
        ImagePath         = "$labSources\CustomAssets\DockerImages\postgis.tar.gz"
        Instance          = 'localhost:15432'
        AdminPassword     = $LabAdminPassword
        SqlQueries        = @(
            "CREATE USER geodemo WITH PASSWORD '$LabAdminPassword'"
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

$rootCredential = [PSCredential]::new('root', (ConvertTo-SecureString -String $LabAdminPassword -AsPlainText -Force))
$linuxIp = $MachineDefinition.IpAddress
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

Write-PSFMessage -Level Host -Message "Copying and importing docker images"
$sftpSession = New-SFTPSession -ComputerName $linuxIp -Credential $rootCredential -Force -WarningAction SilentlyContinue
$imageFiles = Get-Item -Path $DatabaseDefinition.ImagePath
foreach ($imageFile in $imageFiles) { 
    # $imageFile = $imageFiles
    Set-SFTPItem -SFTPSession $sftpSession -Destination /tmp -Path $imageFile.FullName
    $cmd = "docker load -i /tmp/$($imageFile.Name)"
    $sshResult = Invoke-SSHCommand -SSHSession $sshSession -Command $cmd -TimeOut 600 # -ShowStandardOutputStream -ShowErrorOutputStream
    $cmd = "rm /tmp/$($imageFile.Name)"
    $sshResult = Invoke-SSHCommand -SSHSession $sshSession -Command $cmd -TimeOut 600 # -ShowStandardOutputStream -ShowErrorOutputStream
}

Write-PSFMessage -Level Host -Message "Starting databases on docker"
foreach ($db in $DatabaseDefinition) {
    # $db = $DatabaseDefinition[0]
    Write-PSFMessage -Level Host -Message "Starting docker container $($db.ContainerName)"
    $cmd = "docker run --name $($db.ContainerName) --memory=$($db.ContainerMemoryGB)g $($db.ContainerConfig) --detach --restart always $($db.ContainerImage)"
    $null = Invoke-SSHCommand -SSHSession $sshSession -Command $cmd -TimeOut 36000
}

Write-PSFMessage -Level Host -Message "Installing PowerShell-for-DBAs and sample databases"
$DatabaseDefinition | ConvertTo-Json | Set-Content -Path "$labSources\tmp_DatabaseDefinition.json"
Set-SFTPItem -SFTPSession $sftpSession -Destination /tmp -Path "$labSources\tmp_DatabaseDefinition.json"
Remove-Item -Path "$labSources\tmp_DatabaseDefinition.json"
$sshCommands = @(
    'curl -sL https://github.com/andreasjordan/PowerShell-for-DBAs/tarball/main | tar zx --transform "s,^[^/]+,PowerShell-for-DBAs,x"'
    'cd ./PowerShell-for-DBAs/PowerShell && pwsh ./SetupServerWithDocker2.ps1'
)
foreach ($cmd in $sshCommands) {
    $sshResult = Invoke-SSHCommand -SSHSession $sshSession -Command $cmd -TimeOut 6000 -ShowStandardOutputStream -ShowErrorOutputStream
    if ($sshResult.ExitStatus -gt 0) {
        Write-PSFMessage -Level Warning -Message "Command '$cmd' returned with ExitStatus $($sshResult.ExitStatus)"
        break
    }
}

Write-PSFMessage -Level Host -Message "finished"

