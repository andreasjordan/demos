$ErrorActionPreference = 'Stop'
Import-Module -Name PSFramework    # Install-Module -Name PSFramework   # Update-Module -Name PSFramework
Import-Module -Name Az             # Install-Module -Name Az            # Update-Module -Name Az
. .\MyAzureLab.ps1

<#

This Skript will setup my lab with Azure virtual maschines.

It will connect to Azure with
* a given acount name (`$accountId`)
* a given subscription (`$subscriptionName`)

It will then create the following objects.

A [resource group](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-powershell) with
* a given name (`$resourceGroupName`)
* in a given location (`$location`)
* within a given subscription (`$subscription`)

A [key vault](https://docs.microsoft.com/en-us/azure/key-vault/general/basic-concepts) with
* the name "KeyVault<10 digit random number>"
* a self signed certificate named "<name of resource group>Certificate" to support connecting to the virtual maschines via WinRM

A [virtual network](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview) with
* the name "VirtualNetwork"
* the address prefix "10.0.0.0/16"
* a subnet with the name "Default" and the address prefix "10.0.0.0/24"
* the IP address "10.0.0.10" for the domain controller

A [network security group](https://docs.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview) with
* the name "NetworkSecurityGroup"
* rules to allow communication from my home address to the network for WinRM (Port 5986), RDP (Port 3389) and SQL (Port 1433)

A [proximity placement group](https://docs.microsoft.com/en-us/azure/virtual-machines/co-location) with
* the name "ProximityPlacementGroup"

An [availability set](https://docs.microsoft.com/en-us/azure/virtual-machines/availability-set-overview) with
* the name "AvailabilitySet"
* 1 fault domain
* 1 update domain
* inside of the proximity placement group

A set of [virtual maschines](https://docs.microsoft.com/en-us/azure/virtual-machines/):
* All with VM size "Standard_B2s"
* A domain controller with
  * the name "DC"
  * Windows Server 2016
  * AD DS configured for a given domain name (`$domainName`)
* A workstation with
  * the name "ADMIN"
  * Windows 10
  * to be the only maschine to RDP in and do the lab work from there
* Two windows servers with
  * the names "SRV01" and "SRV02"
  * Windows Server 2016
  * joined to the domain

#>

# Will be used with Connect-AzAccount
$privateAzureAccountParameters = @{
    AccountId    = '<mail address>'
    Subscription = '<subscription name>'
}

# Name of resource group and location
# Will be used by MyAzureLab commands
$resourceGroupName = 'FailoverCluster'
$location = 'West Europe'

# Name of the domain
# Will be used by MyAzureLab commands
$domainName = 'mydomain.azure'  # First part in upper cases will be used as NetBiosName

# Credential used for login to virtual maschines but password also for certificate.
# Will be used by MyAzureLab commands
$credential = [PSCredential]::new("<username>", ("<password>" | ConvertTo-SecureString -AsPlainText -Force))


# Part 1: Connecting...

Write-PSFMessage -Level Host -Message 'Connecting to Azure'
$account = Connect-AzAccount @privateAzureAccountParameters
Write-PSFMessage -Level Verbose -Message "Connected to Azure with account '$($account.Context.Account.Id)' and subscription '$($account.Context.Subscription.Name)' in tenant '$($account.Context.Tenant.Id)'"


# Part 2: Setting up main infrastructure ...

Write-PSFMessage -Level Host -Message 'Creating resource group'
$null = New-AzResourceGroup -Name $resourceGroupName -Location $location

Write-PSFMessage -Level Host -Message 'Creating key vault and certificate'
New-MyAzureLabKeyVault -EnableException -Verbose

Write-PSFMessage -Level Host -Message 'Creating network and security group'
New-MyAzureLabNetwork -EnableException -Verbose

Write-PSFMessage -Level Host -Message 'Creating proximity placement group'
$proximityPlacementGroup = New-AzProximityPlacementGroup -ResourceGroupName $resourceGroupName -Location $location -Name "ProximityPlacementGroup" -ProximityPlacementGroupType Standard

Write-PSFMessage -Level Host -Message 'Creating availability set'
$availabilitySetParam = @{
    Name                      = "AvailabilitySet"
    Sku                       = "aligned"
    PlatformFaultDomainCount  = 1
    PlatformUpdateDomainCount = 1
    ProximityPlacementGroupId = $proximityPlacementGroup.Id
}
$null = New-AzAvailabilitySet -ResourceGroupName $resourceGroupName -Location $location @availabilitySetParam


# Part 3: Setting up virtual maschines ...

Write-PSFMessage -Level Host -Message 'Creating virtual maschines'
$scriptBlock = { $null = Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools }
New-MyAzureLabVM -ComputerName DC -SourceImage WindowsServer2016 -EnableException -Verbose
New-MyAzureLabVM -ComputerName ADMIN -SourceImage Windows10 -EnableException -Verbose
New-MyAzureLabVM -ComputerName SRV01 -SourceImage WindowsServer2016 -ScriptBlock $scriptBlock -EnableException -Verbose
New-MyAzureLabVM -ComputerName SRV02 -SourceImage WindowsServer2016 -ScriptBlock $scriptBlock -EnableException -Verbose
Add-MyAzureLabSharedDisk -DiskSizeGB 10 -ComputerName SRV01, SRV02 -Lun 0 -DriveLetter Q -DriveLabel Quorum -Verbose


# Part 4: Setting up ADMIN maschine ...

<# Connect to ADMIN with RDP and execute this in a PowerShell:

Add-WindowsCapability -Online -Name Rsat.FailoverCluster.Management.Tools~~~~0.0.1.0
$result = Test-Cluster -Node SRV01, SRV02
&$result.FullName

#>

# In my case, the result is:
# WARNING: Storage - Validate SCSI-3 Persistent Reservation: The test reported failure..

