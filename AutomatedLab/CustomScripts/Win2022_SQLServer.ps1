$ErrorActionPreference = 'Continue'

Import-Module -Name AutomatedLab

$LabName        = "WinSql"
$LabNetworkBase = '192.168.113'
$LabDnsServer   = '1.1.1.1'

$LabAdminUser     = 'User'
$LabAdminPassword = 'Passw0rd!'

$MachineDefinition = @{
    Name            = 'SQLServer'
    OperatingSystem = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
    Memory          = 4GB
    Processors      = 4
    Network         = $LabName
    IpAddress       = "$LabNetworkBase.10"
    Gateway         = "$LabNetworkBase.1"
    DnsServer1      =  $LabDnsServer
    TimeZone        = 'W. Europe Standard Time'
}

$CopySoftware = @(
    "$labSources\CustomAssets\Software\SQLEXPR_x64_ENU.exe"              # SQL Server Express from: https://www.microsoft.com/en-US/download/details.aspx?id=101064
    "$labSources\CustomAssets\Software\SQLServer2019-KB5017593-x64.exe"  # SQL Server 2019 CU 18
)


<# Some commands that I use for importing, removing, stopping, starting or connecting to the lab:

Import-Lab -Name $LabName -NoValidation

Remove-Lab -Name $LabName -Confirm:$false; Get-NetNat -Name $LabName -ErrorAction SilentlyContinue | Remove-NetNat -Confirm:$false

Stop-VM -Name $MachineDefinition.Name
Start-VM -Name $MachineDefinition.Name

#>


### End of configuration ###


New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV
Set-LabInstallationCredential -Username $LabAdminUser -Password $LabAdminPassword
Add-LabVirtualNetworkDefinition -Name $LabName -AddressSpace "$LabNetworkBase.0/24"
Add-LabMachineDefinition @MachineDefinition
Install-Lab -NoValidation

$null = New-NetNat -Name $LabName -InternalIPInterfaceAddressPrefix "$LabNetworkBase.0/24"

Invoke-LabCommand -ComputerName $MachineDefinition.Name -ActivityName 'Disable Windows updates' -ScriptBlock { 
    # https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings
    Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -Name NoAutoUpdate -Value 1
}

Invoke-LabCommand -ComputerName $MachineDefinition.Name -ActivityName 'Setting my favorite explorer settings' -ScriptBlock {
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name HideFileExt -Value 0
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name NavPaneShowAllFolders -Value 1
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name NavPaneExpandToCurrentFolder -Value 1
}

foreach ($file in $CopySoftware) {
    Copy-LabFileItem -Path $file -ComputerName $MachineDefinition.Name -DestinationFolderPath C:\Software
}

Invoke-LabCommand -ComputerName $MachineDefinition.Name -ActivityName 'Installing SQL Server' -ArgumentList $LabAdminPassword -ScriptBlock {
    param($Password)
    $argumentList = @(
        '/x:C:\Software\SQLEXPR_x64_ENU'
        '/q'
        '/IACCEPTSQLSERVERLICENSETERMS'
        '/ACTION=INSTALL'
        '/UpdateEnabled=True'
        '/UpdateSource=C:\Software'
        '/FEATURES=SQL'
        '/INSTANCENAME=SQLEXPRESS'
        '/SECURITYMODE=SQL'
        "/SAPWD=$Password"
        '/TCPENABLED=1'
        '/SQLSVCINSTANTFILEINIT=True'
    )
    Start-Process -FilePath C:\Software\SQLEXPR_x64_ENU.exe -ArgumentList $argumentList -Wait
}

