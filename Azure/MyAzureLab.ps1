function New-MyAzureLabSession {
    [CmdletBinding()]
    Param(
        [string]$ComputerName,
        [string]$IPAddress,
        [PSCredential]$Credential,
        [int]$Timeout = 600,
        [switch]$EnableException
    )

    if ($ComputerName) {
        $IPAddress = (Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName -Name "$($ComputerName)_PublicIP").IpAddress
        Write-PSFMessage -Level Verbose -Message "Using IP address $IPAddress"
    }

    $psSessionParam = @{
        ConnectionUri  = "https://$($IPAddress):5986"
        Credential     = $Credential
        SessionOption  = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
        Authentication = "Negotiate"
    }

    $waitUntil = (Get-Date).AddSeconds($Timeout)

    Write-PSFMessage -Level Verbose -Message 'Creating PSSession'
    while ((Get-Date) -lt $waitUntil) {
        try {
            New-PSSession @psSessionParam
            break
        } catch {
            Write-PSFMessage -Level Verbose -Message "Failed with: $_"
            Start-Sleep -Seconds 15
        }
    }
    if ((Get-Date) -ge $waitUntil) {
        Stop-PSFFunction -Message 'Failed' -EnableException $EnableException
    }
}



function New-MyAzureLabKeyVault {
    # https://docs.microsoft.com/en-us/azure/virtual-machines/windows/winrm
    # https://docs.microsoft.com/en-us/azure/key-vault/certificates/tutorial-import-certificate

    [CmdletBinding()]
    Param(
        [switch]$EnableException
    )

    process {
        $keyVaultParam = @{
            VaultName                    = "KeyVault$(Get-Random -Minimum 1000000000 -Maximum 9999999999)"
            EnabledForDeployment         = $true
            EnabledForTemplateDeployment = $true
            WarningAction                = "SilentlyContinue"  # Suppress warning about future changes
        }
        $certificateName = "$($resourceGroupName)Certificate"
        $certificateFilename = "$env:TEMP\$certificateName.pfx"
        
        try {
            Write-PSFMessage -Level Verbose -Message 'Creating KeyVault'
            $null = New-AzKeyVault -ResourceGroupName $resourceGroupName -Location $location @keyVaultParam

            Write-PSFMessage -Level Verbose -Message 'Creating SelfSignedCertificate'
            $certificate = New-SelfSignedCertificate -DnsName $certificateName -CertStoreLocation Cert:\CurrentUser\My -KeySpec KeyExchange
    
            Write-PSFMessage -Level Verbose -Message 'Exporting PfxCertificate'
            $null = Export-PfxCertificate -Cert $certificate -FilePath $certificateFilename -Password $credential.Password
    
            Write-PSFMessage -Level Verbose -Message 'Importing KeyVaultCertificate'
            $null = Import-AzKeyVaultCertificate -VaultName $keyVaultParam.VaultName -Name $certificateName -FilePath $certificateFilename -Password $credential.Password
        } catch {
            if ($certificate) {
                Write-PSFMessage -Level Verbose -Message 'Removing certificate'
                Remove-Item -Path "Cert:\CurrentUser\My\$($certificate.Thumbprint)"
            }
            Stop-PSFFunction -Message 'Failed' -ErrorRecord $_ -EnableException $EnableException
        } finally {
            if (Test-Path -Path $certificateFilename) {
                Write-PSFMessage -Level Verbose -Message 'Removing exported PfxCertificate'
                Remove-Item -Path $certificateFilename
            }
        }
    }
}



function New-MyAzureLabNetwork {
    [CmdletBinding()]
    Param(
        [switch]$EnableException
    )

    process {
        # For better readability, common parameters are summarized in a hashtable for splatting.
        $rglP = @{
            ResourceGroupName = $resourceGroupName
            Location          = $location
        }

        try {
            Write-PSFMessage -Level Verbose -Message 'Getting home IP'
            $homeIP = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content
            Write-PSFMessage -Level Verbose -Message "Using '$homeIP' as home IP"
        } catch {
            Stop-PSFFunction -Message 'Failed to get home IP' -ErrorRecord $_ -EnableException $EnableException
            Write-PSFMessage -Level Warning 'Using 127.0.0.1 for now - you have to update the network security group to get access to the network'
            $homeIP = '127.0.0.1'
        }
        
        $virtualNetworkParam = @{
            Name          = "VirtualNetwork"
            AddressPrefix = "10.0.0.0/16"
        }
        $virtualNetworkSubnetConfigParam = @{
            Name          = "Default"
            AddressPrefix = "10.0.0.0/24"
            WarningAction = "SilentlyContinue"  # Suppress warning about future changes
        }
        $networkSecurityGroupParam = @{
            Name = "NetworkSecurityGroup"
        }
        $networkSecurityRules = @(
            @{
                Name                     = "AllowRdpFromHome"
                Protocol                 = "Tcp"
                Direction                = "Inbound"
                Priority                 = "1000"
                SourceAddressPrefix      = $homeIP
                SourcePortRange          = "*"
                DestinationAddressPrefix = "*"
                DestinationPortRange     = 3389
                Access                   = "Allow"
            },
            @{
                Name                     = "AllowSqlFromHome"
                Protocol                 = "Tcp"
                Direction                = "Inbound"
                Priority                 = "1001"
                SourceAddressPrefix      = $homeIP
                SourcePortRange          = "*"
                DestinationAddressPrefix = "*"
                DestinationPortRange     = 1433
                Access                   = "Allow"
            },
            @{
                Name                     = "AllowWinRmFromHome"
                Protocol                 = "Tcp"
                Direction                = "Inbound"
                Priority                 = "1002"
                SourceAddressPrefix      = $homeIP
                SourcePortRange          = "*"
                DestinationAddressPrefix = "*"
                DestinationPortRange     = 5986
                Access                   = "Allow"
            }
        )

        try {
            Write-PSFMessage -Level Verbose -Message 'Creating VirtualNetworkSubnetConfig'
            $virtualNetworkSubnetConfig = New-AzVirtualNetworkSubnetConfig @virtualNetworkSubnetConfigParam
            
            Write-PSFMessage -Level Verbose -Message 'Creating VirtualNetwork'
            $null = New-AzVirtualNetwork @rglP @virtualNetworkParam -Subnet $virtualNetworkSubnetConfig
            
            $securityRules = foreach ($networkSecurityRuleConfigParam in $networkSecurityRules) {
                Write-PSFMessage -Level Verbose -Message 'Creating NetworkSecurityRuleConfig'
                New-AzNetworkSecurityRuleConfig @networkSecurityRuleConfigParam
            }
            
            Write-PSFMessage -Level Verbose -Message 'Creating NetworkSecurityGroup'
            $null = New-AzNetworkSecurityGroup @rglP @networkSecurityGroupParam -SecurityRules $securityRules
        } catch {
            Stop-PSFFunction -Message 'Failed' -ErrorRecord $_ -EnableException $EnableException
        }
    }
}



function New-MyAzureLabVM {
    [CmdletBinding()]
    param (
        [string]$ComputerName,
        [ValidateSet('WindowsServer2016', 'WindowsServer2019', 'Windows10', 'SQLServer2017', 'SQLServer2019')]
        [string]$SourceImage,
        [ScriptBlock]$ScriptBlock,
        [switch]$EnableException
    )

    process {
        # For better readability, common parameters are summarized in a hashtable for splatting.
        $rglP = @{
            ResourceGroupName = $resourceGroupName
            Location          = $location
        }
        $domainCredential = [PSCredential]::new("$($credential.UserName)@$domainName", $credential.Password)

        try {
            Write-PSFMessage -Level Verbose -Message 'Getting key vault and certificate url'
            $keyVault = Get-AzKeyVault -ResourceGroupName $resourceGroupName -WarningAction SilentlyContinue
            $certificateUrl = (Get-AzKeyVaultSecret -VaultName $keyVault.VaultName -Name "$($resourceGroupName)Certificate").Id
    
            Write-PSFMessage -Level Verbose -Message 'Getting subnet, domain controller IP and network security group'
            $subnet = (Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName).Subnets[0]
            $dcPrivateIpAddress = $subnet.AddressPrefix[0].Split('/')[0] -replace '0$', '10'
            $networkSecurityGroup = Get-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName
    
            Write-PSFMessage -Level Verbose -Message 'Getting availability set'
            $availabilitySet = Get-AzAvailabilitySet -ResourceGroupName $resourceGroupName
        } catch {
            Stop-PSFFunction -Message 'Failed to get information' -ErrorRecord $_ -EnableException $EnableException
            return
        }

        $publicIpAddressParam = @{
            Name             = "$($ComputerName)_PublicIP"
            AllocationMethod = "Dynamic"
            WarningAction    = "SilentlyContinue"
        }
        $networkInterfaceParam = @{
            Name                   = "$($ComputerName)_Interface"
            SubnetId               = $subnet.Id
            NetworkSecurityGroupId = $networkSecurityGroup.Id
        }
        $vmConfigParam = @{
            VMName              = "$($ComputerName)_VM"
            VMSize              = "Standard_B2s"
            AvailabilitySetId   = $availabilitySet.Id
            PlatformFaultDomain = 0
        }
        $secretParam = @{
            SourceVaultId    = $keyVault.ResourceId
            CertificateStore = "My"
            CertificateUrl   = $certificateUrl
        }
        $operatingSystemParam = @{
            ComputerName        = $ComputerName
            Windows             = $true
            Credential          = $credential
            WinRMHttps          = $true
            WinRMCertificateUrl = $certificateUrl
            ProvisionVMAgent    = $true
        }
        if ($SourceImage -eq 'WindowsServer2016') {
            $sourceImageParam = @{
                PublisherName = "MicrosoftWindowsServer"   # Get-AzVMImagePublisher -Location $location | Where-Object PublisherName -like microsoft*
                Offer         = "WindowsServer"            # Get-AzVMImageOffer -Location $location -Publisher $sourceImageParam.PublisherName
                Skus          = "2016-Datacenter"          # Get-AzVMImageSku -Location $location -Publisher $sourceImageParam.PublisherName -Offer $sourceImageParam.Offer | Select Skus
                Version       = "latest"
            }
        } elseif ($SourceImage -eq 'WindowsServer2019') {
            $sourceImageParam = @{
                PublisherName = "MicrosoftWindowsServer"   # Get-AzVMImagePublisher -Location $location | Where-Object PublisherName -like microsoft*
                Offer         = "WindowsServer"            # Get-AzVMImageOffer -Location $location -Publisher $sourceImageParam.PublisherName
                Skus          = "2019-Datacenter"          # Get-AzVMImageSku -Location $location -Publisher $sourceImageParam.PublisherName -Offer $sourceImageParam.Offer | Select Skus
                Version       = "latest"
            }
        } elseif ($SourceImage -eq 'Windows10') {
            $sourceImageParam = @{
                PublisherName = "MicrosoftWindowsDesktop"  # Get-AzVMImagePublisher -Location $location | Where-Object PublisherName -like microsoft*
                Offer         = "Windows-10"               # Get-AzVMImageOffer -Location $location -Publisher $sourceImageParam.PublisherName
                Skus          = "win10-21h2-pro"           # Get-AzVMImageSku -Location $location -Publisher $sourceImageParam.PublisherName -Offer $sourceImageParam.Offer | Select Skus
                Version       = "latest"
            }
        } elseif ($SourceImage -eq 'SQLServer2017') {
            $sourceImageParam = @{
                PublisherName = "MicrosoftSQLServer"       # Get-AzVMImagePublisher -Location $location | Where-Object PublisherName -like microsoft*
                Offer         = "SQL2017-WS2016"           # Get-AzVMImageOffer -Location $location -Publisher $sourceImageParam.PublisherName
                Skus          = "SQLDEV"                   # Get-AzVMImageSku -Location $location -Publisher $sourceImageParam.PublisherName -Offer $sourceImageParam.Offer | Select Skus
                Version       = "latest"
            }
        } elseif ($SourceImage -eq 'SQLServer2019') {
            $sourceImageParam = @{
                PublisherName = "MicrosoftSQLServer"       # Get-AzVMImagePublisher -Location $location | Where-Object PublisherName -like microsoft*
                Offer         = "sql2019-ws2019"           # Get-AzVMImageOffer -Location $location -Publisher $sourceImageParam.PublisherName
                Skus          = "sqldev"                   # Get-AzVMImageSku -Location $location -Publisher $sourceImageParam.PublisherName -Offer $sourceImageParam.Offer | Select Skus
                Version       = "latest"
            }
        }
        $osDiskParam = @{
            Name         = "$($ComputerName)_DiskC.vhd"
            CreateOption = "FromImage"
        }
        $bootDiagnosticParam = @{
            Disable = $true
        }
        if ($ComputerName -eq 'DC') {
            $networkInterfaceParam.PrivateIpAddress = $dcPrivateIpAddress
        }

        try {
            Write-PSFMessage -Level Verbose -Message 'Creating PublicIpAddress'
            $publicIpAddress = New-AzPublicIpAddress @rglP @publicIpAddressParam

            Write-PSFMessage -Level Verbose -Message 'Creating NetworkInterface'
            $networkInterface = New-AzNetworkInterface @rglP @networkInterfaceParam -PublicIpAddressId $publicIpAddress.Id

            Write-PSFMessage -Level Verbose -Message 'Creating VMConfig'
            $vmConfig = New-AzVMConfig @vmConfigParam

            Write-PSFMessage -Level Verbose -Message 'Adding NetworkInterface'
            $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $networkInterface.Id

            Write-PSFMessage -Level Verbose -Message 'Setting OperatingSystem'
            $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig @operatingSystemParam

            Write-PSFMessage -Level Verbose -Message 'Setting SourceImage'
            $vmConfig = Set-AzVMSourceImage -VM $vmConfig @sourceImageParam

            Write-PSFMessage -Level Verbose -Message 'Setting OSDisk'
            $vmConfig = Set-AzVMOSDisk -VM $vmConfig @osDiskParam

            Write-PSFMessage -Level Verbose -Message 'Setting BootDiagnostic'
            $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig @bootDiagnosticParam

            Write-PSFMessage -Level Verbose -Message 'Adding Secret'
            $vmConfig = Add-AzVMSecret -VM $vmConfig @secretParam

            Write-PSFMessage -Level Verbose -Message 'Creating VM'
            $result = New-AzVM @rglP -VM $vmConfig
            Write-PSFMessage -Level Verbose -Message "Result: IsSuccessStatusCode = $($result.IsSuccessStatusCode), StatusCode = $($result.StatusCode), ReasonPhrase = $($result.ReasonPhrase)"

            Write-PSFMessage -Level Verbose -Message 'Creating PSSession'
            $session = New-MyAzureLabSession -ComputerName $ComputerName -Credential $credential -EnableException

            if ($ComputerName -eq 'DC') {
                Write-PSFMessage -Level Verbose -Message 'Creating Domain'
                Invoke-Command -Session $session -ArgumentList $domainName, $credential -ScriptBlock {
                    Param([string]$DomainName, [PSCredential]$Credential)
                    $null = Install-WindowsFeature -Name AD-Domain-Services -IncludeAllSubFeature -IncludeManagementTools
                    $forestParam = @{
                        DomainName                    = $DomainName
                        DomainNetbiosName             = $DomainName.Split('.')[0].ToUpper()
                        SafeModeAdministratorPassword = $Credential.Password
                        DomainMode                    = 'def'
                        ForestMode                    = 'WinThreshold'
                        InstallDns                    = $true
                        CreateDnsDelegation           = $false
                        SysvolPath                    = 'C:\Windows\SYSVOL'
                        DatabasePath                  = 'C:\Windows\NTDS'
                        LogPath                       = 'C:\Windows\NTDS'
                        Force                         = $true
                        WarningAction                 = 'SilentlyContinue'
                    }
                    $null = Install-ADDSForest @forestParam
                }
            } else {
                Write-PSFMessage -Level Verbose -Message 'Joining Domain'
                Invoke-Command -Session $session -ArgumentList $domainName, $dcPrivateIpAddress, $domainCredential -ScriptBlock {
                    Param([string]$DomainName, [string]$DomainControllerIP, [PSCredential]$DomainAdminCredential)
                    Set-DnsClientServerAddress -InterfaceIndex ((Get-NetIPConfiguration).InterfaceIndex) -ServerAddresses $DomainControllerIP
                    Add-Computer -DomainName $DomainName -Server "DC.$DomainName" -Credential $DomainAdminCredential -WarningAction SilentlyContinue
                    Restart-Computer -Force
                }
            }
            $session | Remove-PSSession

            Write-PSFMessage -Level Verbose -Message "Waitung for 2 Minutes"
            Start-Sleep -Seconds 120

            Write-PSFMessage -Level Verbose -Message 'Creating PSSession'
            $session = New-MyAzureLabSession -ComputerName $ComputerName -Credential $domainCredential -EnableException

            $fullComputerName = Invoke-Command -Session $session -ScriptBlock { "$env:COMPUTERNAME.$env:USERDOMAIN" }
            Write-PSFMessage -Level Verbose -Message "Full computer name is now '$fullComputerName'"

            if ($ScriptBlock) {
                Write-PSFMessage -Level Verbose -Message "Executing script block"
                Invoke-Command -Session $session -ScriptBlock $ScriptBlock
            }

            $session | Remove-PSSession
        } catch {
            Stop-PSFFunction -Message 'Failed' -ErrorRecord $_ -EnableException $EnableException
        }
    }
}



function Add-MyAzureLabSharedDisk {
    [CmdletBinding()]
    param (
        [int]$DiskSizeGB,
        [string[]]$ComputerName,
        [string]$DriveLetter,
        [string]$DriveLabel,
        [int]$Lun,
        [switch]$EnableException
    )

    process {
        $domainCredential = [PSCredential]::new("$($credential.UserName)@$domainName", $credential.Password)

        $diskConfigParam = @{
            Location       = $location
            DiskSizeGB     = $DiskSizeGB
            AccountType    = "Premium_LRS"
            CreateOption   = "Empty"
            MaxSharesCount = $ComputerName.Count
        }
        $diskParam = @{
            ResourceGroupName = $resourceGroupName
            DiskName          = "SharedDisk$DriveLetter"
        }
        $addDiskParam = @{
            Name          = "SharedDisk$DriveLetter"
            CreateOption  = "Attach"
            Caching       = "None"
            Lun           = $Lun
        }

        try {
            Write-PSFMessage -Level Verbose -Message 'Creating DiskConfig'
            $diskConfig = New-AzDiskConfig @diskConfigParam

            Write-PSFMessage -Level Verbose -Message 'Creating Disk'
            $disk = New-AzDisk @diskParam -Disk $diskConfig
    
            foreach($computer in $ComputerName) {
                Write-PSFMessage -Level Verbose -Message "Attaching Disk to $computer"

                Write-PSFMessage -Level Verbose -Message 'Getting VM'
                $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name "$($computer)_VM"

                Write-PSFMessage -Level Verbose -Message 'Adding VMDataDisk'
                $null = Add-AzVMDataDisk -VM $vm @addDiskParam -ManagedDiskId $disk.Id

                Write-PSFMessage -Level Verbose -Message 'Updating VM'
                $result = Update-AzVM -VM $vm -ResourceGroupName $resourceGroupName

                Write-PSFMessage -Level Verbose -Message "Result: IsSuccessStatusCode = $($result.IsSuccessStatusCode), StatusCode = $($result.StatusCode), ReasonPhrase = $($result.ReasonPhrase)"
            }

            Write-PSFMessage -Level Verbose -Message 'Creating PSSession'
            $session = New-MyAzureLabSession -ComputerName $ComputerName[0] -Credential $domainCredential -EnableException
            
            Write-PSFMessage -Level Verbose -Message 'Initializing and formating disk'
            Invoke-Command -Session $session -ArgumentList $DriveLetter, $DriveLabel -ScriptBlock {
                Param([string]$DriveLetter, [string]$NewFileSystemLabel)
                $disk = Get-Disk | Where-Object -Property PartitionStyle -EQ 'RAW'
                $disk | Initialize-Disk -PartitionStyle GPT
                $partition = $disk | New-Partition -UseMaximumSize -DriveLetter $DriveLetter
                $null = $partition | Format-Volume -FileSystem NTFS -NewFileSystemLabel $NewFileSystemLabel
            }

            $session | Remove-PSSession
        } catch {
            Stop-PSFFunction -Message 'Failed' -ErrorRecord $_ -EnableException $EnableException
        }
    }
}
