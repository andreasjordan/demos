[CmdletBinding()]
param (
    [string]$DomainName = 'ORDIX',
    [string]$DomainController = 'DC',
    [string[]]$ClusterNodes = @('SQL01', 'SQL02'),
    [string]$ClusterName = 'CLUSTER1',
    [string]$ClusterIP = '192.168.3.70'
)

$ErrorActionPreference = 'Stop'

Import-Module -Name PSFramework

try {

Write-PSFMessage -Level Host -Message 'Install cluster feature on each node'
Invoke-Command -ComputerName $ClusterNodes -ScriptBlock { Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools } | Format-Table

Write-PSFMessage -Level Host -Message 'Run cluster test and display result in web browser'
$clusterTest = Test-Cluster -Node $ClusterNodes
& $clusterTest.FullName

Write-PSFMessage -Level Host -Message 'Create the cluster'
$cluster = New-Cluster -Name $ClusterName -Node $ClusterNodes -StaticAddress $ClusterIP

Write-PSFMessage -Level Host -Message 'Create a share as cluster quorum and configure the cluster'
Invoke-Command -ComputerName $DomainController -ScriptBlock { 
    $null = New-Item -Path "C:\WindowsClusterQuorum_$using:ClusterName" -ItemType Directory
    $null = New-SmbShare -Path "C:\WindowsClusterQuorum_$using:ClusterName" -Name "WindowsClusterQuorum_$using:ClusterName"
    $null = Grant-SmbShareAccess -Name "WindowsClusterQuorum_$using:ClusterName" -AccountName "$using:DomainName\$using:ClusterName$" -AccessRight Full -Force
}
$cluster | Set-ClusterQuorum -NodeAndFileShareMajority "\\$DomainController\WindowsClusterQuorum_$ClusterName" | Format-List

Write-PSFMessage -Level Host -Message 'Grant necessary rights to the computer account of the cluster'
$adComputerGUID = [GUID]::new('bf967a86-0de6-11d0-a285-00aa003049e2')
$adClusterComputer = Get-ADComputer -Filter "Name -eq '$ClusterName'"
$adClusterIdentity = [System.Security.Principal.SecurityIdentifier]::new($adClusterComputer.SID)
$adClusterOU = [ADSI]([ADSI]"LDAP://$($adClusterComputer.DistinguishedName)").Parent
$accessRule1 = [System.DirectoryServices.ActiveDirectoryAccessRule]::new($adClusterIdentity, "ReadProperty", "Allow", [GUID]::Empty, "All", [GUID]::Empty)
$accessRule2 = [System.DirectoryServices.ActiveDirectoryAccessRule]::new($adClusterIdentity, "CreateChild", "Allow", $adComputerGUID, "All", [GUID]::Empty)
$adClusterOU.psbase.ObjectSecurity.AddAccessRule($accessRule1)
$adClusterOU.psbase.ObjectSecurity.AddAccessRule($accessRule2)
$adClusterOU.psbase.CommitChanges()

Write-PSFMessage -Level Host -Message 'finished'

} catch { Write-PSFMessage -Level Warning -Message 'failed' -ErrorRecord $_ }
