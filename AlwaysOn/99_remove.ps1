[CmdletBinding()]
param (
    [string]$DomainName = 'ORDIX',
    [string]$DomainController = 'DC',
    [string]$ClusterName = 'CLUSTER1',
    [SecureString]$AdminPassword = (ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force),
    [string]$SQLServerSourcesPath = '\\fs\Software\SQLServer\ISO',
    [string]$BackupPath = '\\fs\Backup'
)

$ErrorActionPreference = 'Stop'

Import-Module -Name PSFramework
Import-Module -Name dbatools

$PSDefaultParameterValues['*-Dba*:Confirm'] = $false

$administratorCredential = New-Object -TypeName PSCredential -ArgumentList "$DomainName\Admin", $AdminPassword

Write-PSFMessage -Level Host -Message 'Get Cluster Nodes'
$clusterNodes = Get-ClusterNode -Name $ClusterName

Write-PSFMessage -Level Host -Message 'Get SQL Server instances on cluster nodes'
$sqlInstances = Find-DbaInstance -ComputerName $clusterNodes.Name

Write-PSFMessage -Level Host -Message 'Get Availability Groups'
$ags = Get-DbaAvailabilityGroup -SqlInstance $sqlInstances.SqlInstance | Where-Object LocalReplicaRole -eq 'Primary'

foreach ($ag in $ags) {
    Write-PSFMessage -Level Host -Message "Remove Availability Group $($ag.AvailabilityGroup) to remove cluster resource"
    $ag | Remove-DbaAvailabilityGroup -Confirm:$false
    Get-ADComputer -Filter "Name -eq '$($ag.AvailabilityGroup)'" | Remove-ADComputer -Confirm:$false
}

foreach ($inst in $sqlInstances) {
    Write-PSFMessage -Level Host -Message "Remove SQL Server instance $($inst.SqlInstance)"

    # What information do we need?
    # * Version for Install-DbaInstance to select the correct setup.exe
    # * InstancePath for Remove-Item to remove all left over files
    try {
        # Try to get information from running instance
        $server = Connect-DbaInstance -SqlInstance $inst.SqlInstance
        $instanceVersion = ($server.GetSqlServerVersionName() -split ' ')[-1]
        if (-not $instanceVersion) { $instanceVersion = 2022 }
        $instancePath = $server.RootDirectory -replace 'MSSQL$', ''
    } catch {
        # Fallback to information about the service
        $service = Get-DbaService -ComputerName $inst.ComputerName -InstanceName $inst.InstanceName -Type Engine -EnableException
        $instanceVersion = switch ($service.BinaryPath -replace '^.*MSSQL(\d\d).*$', '$1') { 15 { 2019 } 14 { 2017 } 13 { 2016 } 12 { 2014 } 11 { 2012 } }
        $instancePath = $service.BinaryPath -replace '^"?(.*)MSSQL\\Binn\\sqlservr\.exe.*$', '$1'
    }
    $params = @{
        SqlInstance      = $inst.SqlInstance
        Version          = $instanceVersion
        Feature          = 'Engine'
        Configuration    = @{ ACTION = 'Uninstall' } 
        Path             = $SQLServerSourcesPath
        Restart          = $true
        Credential       = $administratorCredential
        Confirm          = $false
    }
    $result = Install-DbaInstance @params
    if (-not $result.Successful) {
        $result.Log | Set-Clipboard
        throw "Uninstall failed, see clipboard for details"
    }
    
    # Remove firewall rule
    Get-DbaFirewallRule -SqlInstance $inst.SqlInstance | Remove-DbaFirewallRule

    # Remove directory
    Invoke-Command -ComputerName $inst.ComputerName -ScriptBlock { 
        param($path)
        Remove-Item -Path $path -Recurse -Force
    } -ArgumentList $instancePath
}

foreach ($node in $clusterNodes) {
    Write-PSFMessage -Level Host -Message "Remove SQL Server base directory on $($node.Name)"
    Invoke-Command -ComputerName $node.Name -ScriptBlock { Remove-Item -Path 'C:\Program Files\Microsoft SQL Server' -Recurse -Force }
}

Write-PSFMessage -Level Host -Message "Remove backups from backup directory"
Get-ChildItem -Path $BackupPath | Where-Object -Property Name -Match -Value '_\d{12}.(bak|trn)$' | Remove-Item

Write-PSFMessage -Level Host -Message "Remove cluster"
Remove-Cluster -Cluster $ClusterName -Force
Get-ADComputer -Filter "Name -eq '$ClusterName'" | Remove-ADComputer -Confirm:$false
Invoke-Command -ComputerName $DomainController -ScriptBlock { Remove-SmbShare -Name "WindowsClusterQuorum_$using:ClusterName" -Force }
Invoke-Command -ComputerName $DomainController -ScriptBlock { Remove-Item -Path "C:\WindowsClusterQuorum_$using:ClusterName" -Recurse }
Invoke-Command -ComputerName $clusterNodes.Name -ScriptBlock { Remove-WindowsFeature -Name Failover-Clustering -IncludeManagementTools } | Format-Table

Write-PSFMessage -Level Host -Message 'Restart server'
Restart-Computer -ComputerName $clusterNodes.Name -Force


# Maybe needed:
# Enable-WSManCredSSP -Role Client -DelegateComputer $ClusterNodes -Force | Out-Null
# Invoke-Command -ComputerName $ClusterNodes -ScriptBlock { Enable-WSManCredSSP -Role Server -Force } | Out-Null

# Should be reset as well:
# Set-DbaPrivilege -ComputerName $ClusterNodes -Type IFI
