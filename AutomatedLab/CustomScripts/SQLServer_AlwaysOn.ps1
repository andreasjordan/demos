$ErrorActionPreference = 'Continue'

Import-Module -Name AutomatedLab

$LabName          = 'AlwaysOn'
$LabNetworkBase   = '192.168.3'

$LabAdminUser     = 'Admin'
$LabAdminPassword = 'P@ssw0rd'

$LabDomainName    = 'ordix.local'
$LabDnsServer     = '1.1.1.1'

$MachineDefinitionDefaults = @{
    Processors = 2
    Memory     = 2GB
    Network    = $LabName
    Gateway    = "$LabNetworkBase.1"
    DomainName = $LabDomainName
    TimeZone   = 'W. Europe Standard Time'
}

$MachineDefinition = @(
    @{
        Name            = 'DC'
        OperatingSystem = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
        IpAddress       = "$LabNetworkBase.10"
        DnsServer1      = $LabDnsServer
        Roles           = 'RootDC'
    }
    @{
        Name            = 'ADMIN01'
        OperatingSystem = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
        IpAddress       = "$LabNetworkBase.20"
    }
    @{
        Name            = 'SQL01'
        OperatingSystem = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
        IpAddress       = "$LabNetworkBase.31"
    }
    @{
        Name            = 'SQL02'
        OperatingSystem = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
        IpAddress       = "$LabNetworkBase.32"
    }
    @{
        Name            = 'SQL03'
        OperatingSystem = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
        IpAddress       = "$LabNetworkBase.33"
    }
)

<# Some commands that I use for importing, removing, stopping, starting or connecting to the lab:

Import-Lab -Name $LabName -NoValidation

Remove-Lab -Name $LabName -Confirm:$false; Get-NetNat -Name $LabName -ErrorAction SilentlyContinue | Remove-NetNat -Confirm:$false

Stop-LabVM -All
Start-LabVM -ComputerName DC -Wait ; Start-LabVM -All

vmconnect.exe localhost $LabName-ADMIN01

#>

$FileServerFolder = @(
    @{
        Path  = 'FileServer'
        Share = @{
            Name   = 'FileServer'
            Access = @{
                AccountName = $LabAdminUser
                AccessRight = 'Full'
            }
        }
    }
    @{
        Path  = 'FileServer\Software'
        Share = @{
            Name   = 'Software'
            Access = @{
                AccountName = $LabAdminUser
                AccessRight = 'Full'
            }
        }
    }
    @{
        Path  = 'FileServer\Software\SQLServer'
    }
    @{
        Path  = 'FileServer\Software\SQLServer\ISO'
    }
    @{
        Path      = 'FileServer\Software\SQLServer\ISO\SQLServer2022'
        ExpandISO = "$labSources\CustomAssets\FileServerISOs\enu_sql_server_2022_developer_edition_x64_dvd_7cacf733.iso"
    }
    @{
        Path      = 'FileServer\Software\SQLServer\ISO\SQLServer2019'
        ExpandISO = "$labSources\CustomAssets\FileServerISOs\en_sql_server_2019_developer_x64_dvd_e5ade34a.iso"
    }
    @{
        Path      = 'FileServer\Software\SQLServer\ISO\SQLServer2017'
        ExpandISO = "$labSources\CustomAssets\FileServerISOs\en_sql_server_2017_developer_x64_dvd_11296168.iso"
    }
    @{
        Path         = 'FileServer\Software\SQLServer\CU'
        DownloadFile = @{
            Name = 'Get-CU.ps1'
            Url  = 'https://raw.githubusercontent.com/andreasjordan/demos/master/dbatools/Get-CU.ps1'
        }
    }
    @{
        Path     = 'FileServer\SampleDatabases'
        CopyFile = @(
            "$labSources\CustomAssets\SampleDatabases\*.bak"
        )
        Share = @{
            Name   = 'SampleDatabases'
            Access = @{
                AccountName = $LabAdminUser
                AccessRight = 'Full'
            }
        }
    }
    @{
        Path  = 'FileServer\Backup'
        Share = @{
            Name   = 'Backup'
            Access = @(
                @{
                    AccountName = $LabAdminUser
                    AccessRight = 'Full'
                }
                @{
                    AccountName = 'SQLServiceAccounts'
                    AccessRight = 'Change'
                }
            )
        }
    }
)

$ChocolateyPackages = @(
    'powershell-core'
    'notepadplusplus'
    '7zip'
    'vscode'
    'vscode-powershell'
    'googlechrome'
    'sql-server-management-studio'
)

$PowerShellModules = @(
    'PSFramework'
    'dbatools'
)



### End of configuration ###


New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV
Set-LabInstallationCredential -Username $LabAdminUser -Password $LabAdminPassword
Add-LabDomainDefinition -Name $LabDomainName -AdminUser $LabAdminUser -AdminPassword $LabAdminPassword
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

Invoke-LabCommand -ComputerName (Get-LabVM) -ActivityName 'Disable Windows updates' -ScriptBlock { 
    # https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings
    Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -Name NoAutoUpdate -Value 1
}

# Configure the AD including GPOs
Invoke-LabCommand -ComputerName DC -ActivityName 'PrepareDomain' -DependencyFolderPath $labSources\CustomAssets\GPOs -ArgumentList $LabAdminPassword -ScriptBlock {
    param ($Password)

    Start-Transcript -Path C:\DeployDebug\PrepareDomain.log

    Import-Module -Name ActiveDirectory
    Import-Module -Name GroupPolicy

    $adminComputerOU = New-ADOrganizationalUnit -Name AdminComputer -ProtectedFromAccidentalDeletion:$false -PassThru
    $adminUserOU = New-ADOrganizationalUnit -Name AdminUser -ProtectedFromAccidentalDeletion:$false -PassThru
    $sqlComputerOU = New-ADOrganizationalUnit -Name SqlComputer -ProtectedFromAccidentalDeletion:$false -PassThru
    $sqlUserOU = New-ADOrganizationalUnit -Name SqlUser -ProtectedFromAccidentalDeletion:$false -PassThru

    Get-ADComputer -Filter 'Name -like "ADMIN*"' | Move-ADObject -TargetPath $adminComputerOU.DistinguishedName
    Get-ADComputer -Filter 'Name -like "SQL*"' | Move-ADObject -TargetPath $sqlComputerOU.DistinguishedName

    $accountPassword = (ConvertTo-SecureString -String $Password -AsPlainText -Force)
    New-ADUser -Name SQLServer -AccountPassword $accountPassword -Enabled $true -Path $sqlUserOU.DistinguishedName
    New-ADUser -Name SQLSrv1 -AccountPassword $accountPassword -Enabled $true -Path $sqlUserOU.DistinguishedName
    New-ADUser -Name SQLSrv2 -AccountPassword $accountPassword -Enabled $true -Path $sqlUserOU.DistinguishedName
    New-ADUser -Name SQLSrv3 -AccountPassword $accountPassword -Enabled $true -Path $sqlUserOU.DistinguishedName
    New-ADUser -Name SQLSrv4 -AccountPassword $accountPassword -Enabled $true -Path $sqlUserOU.DistinguishedName
    New-ADUser -Name SQLSrv5 -AccountPassword $accountPassword -Enabled $true -Path $sqlUserOU.DistinguishedName
    New-ADUser -Name SQLAdmin -AccountPassword $accountPassword -Enabled $true -Path $sqlUserOU.DistinguishedName
    New-ADUser -Name SQLUser1 -AccountPassword $accountPassword -Enabled $true -Path $sqlUserOU.DistinguishedName
    New-ADUser -Name SQLUser2 -AccountPassword $accountPassword -Enabled $true -Path $sqlUserOU.DistinguishedName
    New-ADUser -Name SQLUser3 -AccountPassword $accountPassword -Enabled $true -Path $sqlUserOU.DistinguishedName
    New-ADUser -Name SQLUser4 -AccountPassword $accountPassword -Enabled $true -Path $sqlUserOU.DistinguishedName
    New-ADUser -Name SQLUser5 -AccountPassword $accountPassword -Enabled $true -Path $sqlUserOU.DistinguishedName

    New-ADGroup -Name SQLServiceAccounts -GroupCategory Security -GroupScope Global -Path $sqlUserOU.DistinguishedName
    New-ADGroup -Name SQLAdmins -GroupCategory Security -GroupScope Global -Path $sqlUserOU.DistinguishedName
    New-ADGroup -Name SQLUsers -GroupCategory Security -GroupScope Global -Path $sqlUserOU.DistinguishedName

    Add-ADGroupMember -Identity SQLServiceAccounts -Members SQLServer, SQLSrv1, SQLSrv2, SQLSrv3, SQLSrv4, SQLSrv5
    Add-ADGroupMember -Identity SQLAdmins -Members SQLAdmin
    Add-ADGroupMember -Identity SQLUsers -Members SQLUser1, SQLUser2, SQLUser3, SQLUser4, SQLUser5

    $target = (Get-ADDomain).DistinguishedName
    foreach ($gpo in Get-ChildItem -Path C:\GPOs -Directory) {
        $name = $gpo.Name
        $path = $gpo.FullName
        $backupId = (Get-ChildItem -Path $path -Directory).Name
        $null = New-GPO -Name $name
        $null = Import-GPO -TargetName $name -Path $path -BackupId $backupId
        $null = New-GPLink -Name $name -Target $target
    }

    Stop-Transcript
}


foreach ($folder in $FileServerFolder) {
    # $folder = $fileServerConfig.Folder[0]

    Invoke-LabCommand -ComputerName DC -ActivityName 'PrepareFileserver' -ArgumentList "C:\$($folder.Path)" -ScriptBlock { param($Path) $null = New-Item -Path $Path -ItemType Directory }

    if ($folder.ExpandISO) {
        $isoImage = Mount-LabIsoImage -ComputerName DC -IsoPath $folder.ExpandISO -PassThru
        Invoke-LabCommand -ComputerName DC -ActivityName 'PrepareFileserver' -ArgumentList "C:\$($folder.Path)", $isoImage.DriveLetter -ScriptBlock { param($Path, $DriveLetter) $null = New-Item -Path $Path -ItemType Directory -Force ; Copy-Item -Path "$DriveLetter\*" -Destination $Path -Recurse }
        Dismount-LabIsoImage -ComputerName DC 
    }

    foreach ($file in $folder.DownloadFile) {
        Invoke-LabCommand -ComputerName DC -ActivityName 'PrepareFileserver' -ArgumentList $file.Url, "C:\$($folder.Path)\$($file.Name)" -ScriptBlock { param($Uri, $OutFile) Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing }
    }

    foreach ($file in $folder.CopyFile) {
        Copy-LabFileItem -ComputerName DC -Path $file -DestinationFolderPath "C:\$($folder.Path)"
    }

    if ($folder.CopyFolder) {
        Copy-LabFileItem -ComputerName DC -Path "$($folder.CopyFolder)\*" -DestinationFolderPath "C:\$($folder.Path)" -Recurse
    }

    if ($folder.Share) {
        Invoke-LabCommand -ComputerName DC -ActivityName 'PrepareFileserver' -ArgumentList $folder.Path, $folder.Share -ScriptBlock { 
            param($Path, $Share)
            $domainName = (Get-ADDomain).NetBIOSName
            $null = New-SmbShare -Path "C:\$Path" -Name $Share.Name
            foreach ($access in $Share.Access) {
                $null = Grant-SmbShareAccess -Name $Share.Name -AccountName "$domainName\$($access.AccountName)" -AccessRight $($access.AccessRight) -Force
            }
        }
    }
}

Invoke-LabCommand -ComputerName DC -ActivityName 'PrepareFileserver' -ScriptBlock {
    $dnsRoot = (Get-ADDomain).DNSRoot
    Add-DnsServerResourceRecordCName -ComputerName dc -ZoneName $dnsRoot -HostNameAlias dc.$dnsRoot -Name fs
}

Install-LabWindowsFeature -ComputerName ADMIN01 -FeatureName RSAT -IncludeAllSubFeature
Restart-LabVM -ComputerName ADMIN01 -Wait
Start-Sleep -Seconds 30

$pingSucceeded = Invoke-LabCommand -ComputerName ADMIN01 -ActivityName 'Testing internet access' -PassThru -ScriptBlock { 
    (Test-NetConnection -ComputerName www.google.de -WarningAction SilentlyContinue).PingSucceeded
}

if (-not $pingSucceeded) {
    Write-Warning -Message "We don't have internet access, but let's wait for 30 seconds and try again"
    Start-Sleep -Seconds 30
    $pingSucceeded = Invoke-LabCommand -ComputerName ADMIN01 -ActivityName 'Testing internet access' -PassThru -ScriptBlock { 
        (Test-NetConnection -ComputerName www.google.de -WarningAction SilentlyContinue).PingSucceeded
    }
    if (-not $pingSucceeded) {
        Write-Warning -Message "We don't have internet access, so stopping here"
        break
    }
}

Invoke-LabCommand -ComputerName ADMIN01 -ActivityName 'Installing chocolatey packages' -ArgumentList @(, $ChocolateyPackages) -ScriptBlock { 
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

Invoke-LabCommand -ComputerName ADMIN01 -ActivityName 'Installing PowerShell modules' -ArgumentList @(, $PowerShellModules) -ScriptBlock { 
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

        # Configure dbatools to suppress the message during import and to accept self-signed certificates:
        Import-Module -Name dbatools *> $null
        Set-DbatoolsConfig -FullName Import.EncryptionMessageCheck -Value $false -Register
        Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register
    } catch {
        $message = "Setting up PowerShell failed: $_"
        $message | Add-Content -Path $logPath
        Write-Warning -Message $message
    }
}



Stop-LabVM -All
Start-Sleep -Seconds 10
Checkpoint-VM -Name $LabName-* -SnapshotName Level0
Start-LabVM -ComputerName DC -Wait ; Start-LabVM -All
Start-Sleep -Seconds 30


Invoke-LabCommand -ComputerName ADMIN01 -ActivityName 'Downloading demo repository' -ScriptBlock { 
    $logPath = 'C:\DeployDebug\DownloadDemos.log'

    $ErrorActionPreference = 'Stop'

    try {
        $null = New-Item -Path C:\GitHub -ItemType Directory

        Invoke-WebRequest -Uri https://github.com/andreasjordan/demos/archive/refs/heads/master.zip -OutFile C:\GitHub\master.zip -UseBasicParsing
        Expand-Archive -Path C:\GitHub\master.zip -DestinationPath C:\GitHub
        Rename-Item C:\GitHub\demos-master -NewName demos
        Remove-Item C:\GitHub\master.zip
    } catch {
        $message = "Downloading demo repository failed: $_"
        $message | Add-Content -Path $logPath
        Write-Warning -Message $message
    }
}

Invoke-LabCommand -ComputerName ADMIN01 -ActivityName 'Downloading SQL Server CUs' -ScriptBlock { 
    $logPath = 'C:\DeployDebug\DownloadCUs.log'

    $ErrorActionPreference = 'Stop'

    try {
        Set-Location -Path \\fs\Software\SQLServer\CU
        .\Get-CU.ps1
    } catch {
        $message = "Downloading SQL Server CUs failed: $_"
        $message | Add-Content -Path $logPath
        Write-Warning -Message $message
    }
}

Invoke-LabCommand -ComputerName ADMIN01 -ActivityName 'Setting up CredSSP' -ScriptBlock { 
    $logPath = 'C:\DeployDebug\SetupCredSSP.log'

    $ErrorActionPreference = 'Stop'

    try {
        Get-ADComputer -Filter 'Name -like "SQL*"' |
            ForEach-Object -Process { 
                $null = Enable-WSManCredSSP -Role Client -DelegateComputer $_.Name -Force
                $null = Enable-WSManCredSSP -Role Client -DelegateComputer $_.DNSHostName -Force
            }
    } catch {
        $message = "Setting up CredSSP failed: $_"
        $message | Add-Content -Path $logPath
        Write-Warning -Message $message
    }
}

Invoke-LabCommand -ComputerName ADMIN01 -ActivityName 'Setting up Cluster' -PassThru -ScriptBlock { 
    $logPath = 'C:\DeployDebug\SetupCluster.log'

    $ErrorActionPreference = 'Stop'

    try {
        C:\GitHub\demos\AlwaysOn\00_setup_cluster.ps1
    } catch {
        $message = "Setting up Cluster failed: $_"
        $message | Add-Content -Path $logPath
        Write-Warning -Message $message
    }
}

Invoke-LabCommand -ComputerName ADMIN01 -ActivityName 'Setting up SQL Server instances' -PassThru -ScriptBlock { 
    $logPath = 'C:\DeployDebug\SetupInstances.log'

    $ErrorActionPreference = 'Stop'

    try {
        C:\GitHub\demos\AlwaysOn\01_setup_instances.ps1
        C:\GitHub\demos\AlwaysOn\01_setup_instances_SQL2017.ps1
    } catch {
        $message = "Setting up SQL Server instances failed: $_"
        $message | Add-Content -Path $logPath
        Write-Warning -Message $message
    }
}

Invoke-LabCommand -ComputerName ADMIN01 -ActivityName 'Setting up SQL Server Availability Groups' -PassThru -ScriptBlock { 
    $logPath = 'C:\DeployDebug\SetupAG.log'

    $ErrorActionPreference = 'Stop'

    try {
        C:\GitHub\demos\AlwaysOn\02_setup_availability_group.ps1
        C:\GitHub\demos\AlwaysOn\02_setup_availability_group_SQL2017.ps1
    } catch {
        $message = "Setting up SQL Server Availability Groups failed: $_"
        $message | Add-Content -Path $logPath
        Write-Warning -Message $message
    }
}

Invoke-LabCommand -ComputerName ADMIN01 -ActivityName 'Setting up SQL03' -PassThru -ScriptBlock { 
    $logPath = 'C:\DeployDebug\SetupSQL03.log'

    $ErrorActionPreference = 'Stop'

    try {
        C:\GitHub\demos\AlwaysOn\03_add_SQL03_to_Cluster_and_AvailabilityGroup.ps1
    } catch {
        $message = "Setting up SQL03 failed: $_"
        $message | Add-Content -Path $logPath
        Write-Warning -Message $message
    }
}

Write-PSFMessage -Level Host -Message "finished"

vmconnect.exe localhost $LabName-ADMIN01



break



Stop-LabVM -All
Start-Sleep -Seconds 10
Get-VMSnapshot -VMName $LabName-* -Name Level0 | Restore-VMSnapshot -Confirm:$false
Start-LabVM -ComputerName DC -Wait ; Start-LabVM -All
Start-Sleep -Seconds 30



Invoke-LabCommand -ComputerName ADMIN01 -ActivityName 'Create script for a test with PowerShell 7.3 and dbatools 2.0.0-prerelease' -ScriptBlock { 
@'
Get-ADComputer -Filter 'Name -like "SQL*"' |
    ForEach-Object -Process { 
        $null = Enable-WSManCredSSP -Role Client -DelegateComputer $_.Name -Force
        $null = Enable-WSManCredSSP -Role Client -DelegateComputer $_.DNSHostName -Force
    }

Install-Module -Name dbatools -AllowPrerelease -Force
Set-DbatoolsConfig -Name Import.EncryptionMessageCheck -Value $false -PassThru | Register-DbatoolsConfig
Set-DbatoolsConfig -Name sql.connection.trustcert -Value $true -PassThru | Register-DbatoolsConfig
Import-Module -Name dbatools -MinimumVersion 2.0.0

Set-Location -Path \\fs\Software\SQLServer\CU
.\Get-CU.ps1

$null = New-Item -Path C:\GitHub -ItemType Directory
Invoke-WebRequest -Uri https://github.com/andreasjordan/demos/archive/refs/heads/master.zip -OutFile C:\GitHub\master.zip -UseBasicParsing
Expand-Archive -Path C:\GitHub\master.zip -DestinationPath C:\GitHub
Rename-Item C:\GitHub\demos-master -NewName demos
Remove-Item C:\GitHub\master.zip

C:\GitHub\demos\AlwaysOn\00_setup_cluster.ps1

C:\GitHub\demos\AlwaysOn\01_setup_instances.ps1
C:\GitHub\demos\AlwaysOn\01_setup_instances_SQL2017.ps1

C:\GitHub\demos\AlwaysOn\02_setup_availability_group.ps1
C:\GitHub\demos\AlwaysOn\02_setup_availability_group_SQL2017.ps1

C:\GitHub\demos\AlwaysOn\03_add_SQL03_to_Cluster_and_AvailabilityGroup.ps1
'@ | Set-Content -Path C:\test.ps1
}


# Open PowerShell 7 inside of ADMIN01 and run "C:\test.ps1"

