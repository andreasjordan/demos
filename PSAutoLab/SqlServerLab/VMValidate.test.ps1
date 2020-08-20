﻿#requires -version 5.1

#test if VM setup is complete

$LabData = Import-PowerShellDataFile -Path $PSScriptRoot\VMConfigurationData.psd1
$Secure = ConvertTo-SecureString -String "$($labdata.allnodes.labpassword)" -AsPlainText -Force
$Domain = $labdata.allnodes.domainname
$cred = New-Object PSCredential "$Domain\Administrator", $Secure
$wgcred = New-Object PSCredential  "administrator", $secure

#The prefix only changes the name of the VM not the guest computername
$prefix = $Labdata.NonNodeData.Lability.EnvironmentPrefix

#set error action preference to suppress all error messsages which would be normal while configurations are converging
#turn off progress bars
$prep = {
    $ProgressPreference = "SilentlyContinue"
    $errorActionPreference = 'SilentlyContinue'
}
#define an array to hold all of the PSSessions
$all = @()

Describe DOM1 {

    $VMName = "$($prefix)DOM1"
    Try {
        $dc = New-PSSession -VMName $VMName -Credential $cred -ErrorAction Stop
        $all += $dc
        Invoke-Command $prep -session $dc

        It "[DOM1] Should belong to the $domain domain" {
            $test = Invoke-Command {
                Get-CimInstance -ClassName win32_computersystem -property domain
            } -session $DC
            $test.domain | Should Be $domain
        }

        #test for features
        $feat = Invoke-Command { Get-WindowsFeature | Where-Object installed } -session $dc
        $needed = 'AD-Domain-Services', 'DNS', 'RSAT-AD-Tools',
        'RSAT-AD-PowerShell'
        foreach ($item in $needed) {
            It "[DOM1] Should have feature $item installed" {
                $feat.Name -contains $item | Should Be "True"
            }
        }

        It "[DOM1] Should have an IP address of 192.168.3.10" {
            $i = Invoke-Command -ScriptBlock { Get-NetIPAddress -interfacealias 'Ethernet' -AddressFamily IPv4 } -Session $dc
            $i.ipv4Address | Should be '192.168.3.10'
        }

        It "[DOM1] Should have a domain name of $domain" {
            $r = Invoke-Command {
                Try {
                    Get-ADDomain -ErrorAction Stop
                }
                Catch {
                    #ignore the error - Domain still spinning up
                }
            } -session $dc
            $r.dnsroot | Should Be $domain
        }

        $OUs = Invoke-Command {
            Try {
                Get-ADOrganizationalUnit -filter * -ErrorAction Stop
            }
            Catch {
                #ignore the error - Domain still spinning up
            }
        } -session $dc
        if ($OUS) {
            $needed = 'IT', 'Dev', 'Marketing', 'Sales', 'Accounting', 'JEA_Operators', 'Servers'
            foreach ($item in $needed) {
                It "[DOM1] Should have organizational unit $item" {
                    $OUs.name -contains $item | Should Be "True"
                }
            }
        } #if ous

        $groups = Invoke-Command {
            Try {
                Get-ADGroup -filter * -ErrorAction Stop
            }
            Catch {
                #ignore the error - Domain still spinning up
            }
        } -session $DC

        if ($groups) {
            $target = "IT", "Sales", "Marketing", "Accounting", "JEA Operators"
            foreach ($item in $target) {

                It "[DOM1] Should have a group called $item" {
                    $groups.Name -contains $item | Should Be "True"
                }
            }
        } #if groups

        $users = Invoke-Command {
            Try {
                Get-ADUser -filter * -ErrorAction Stop
            }
            Catch {
                #ignore the error - Domain still spinning up
            }
        } -session $dc
        if ($users) {
            It "[DOM1] Should have at least 15 user accounts" {
                $users.count | Should BeGreaterThan 15
            }

            $admins = Invoke-Command { Get-ADGroupMember "Domain Admins"-ErrorAction SilentlyContinue } -session $dc
            It "[DOM1] ArtD is a member of Domain Admins" {
                $admins.name -contains 'artd' | Should Be True
            }

            It "[DOM1] AprilS is a member of Domain Admins" {
                $admins.name -contains 'aprils' | Should Be True
            }
        } #if users

        $computer = Invoke-Command {
            Try {
                Get-ADComputer -filter * -ErrorAction SilentlyContinue
            }
            Catch {
                #ignore the error - Domain still spinning up
            }
        } -session $dc

        if ($Computer) {
            It "[DOM1] Should have a computer account for WIN10" {
                $computer.name -contains "Win10" | Should Be "True"
            }

            It "[DOM1] Should have a computer account for SRV1" {
                $computer.name -contains "SRV1" | Should Be "True"
            }

            It "[DOM1] Should have a computer account for SRV2" {
                $computer.name -contains "SRV2" | Should Be "True"
            }

            It "[DOM1] Should have a computer account for SRV3" {
                $computer.name -contains "SRV3" | Should Be "True"
            }
        } #if computer

        It "[DOM1] Should be running Windows Server 2016" {
            $test = Invoke-Command { Get-CimInstance -ClassName win32_operatingsystem -property caption } -session $dc
            $test.caption | Should BeLike '*2016*'
        }

        It "[DOM1] Should pass Test-DSCConfiguration" {
            Invoke-Command {Test-DscConfiguration -WarningAction SilentlyContinue } -session $dc | Should Be "True"
        }
    }
    Catch {
        It "[DOM1] Should allow a PSSession but got error: $($_.exception.message)" {
            $false | Should Be $True
        }
      }
} #DOM1


Describe SRV1 {

    $VMName = "$($prefix)SRV1"
    Try {
        $srv1 = New-PSSession -VMName $VMName -Credential $cred -ErrorAction Stop
        $all += $srv1
        Invoke-Command $prep -session $srv1

        It "[SRV1] Should belong to the $domain domain" {
            $test = Invoke-Command { Get-CimInstance -ClassName win32_computersystem -property domain } -session $SRV1
            $test.domain | Should Be $domain
        }

        It "[SRV1] Should have an IP address of 192.168.3.50" {
            $i = Invoke-Command -ScriptBlock { Get-NetIPAddress -interfacealias 'Ethernet' -AddressFamily IPv4 } -Session $SRV1
            $i.ipv4Address | Should be '192.168.3.50'
        }
        $dns = Invoke-Command { Get-DnsClientServerAddress -InterfaceAlias ethernet -AddressFamily IPv4 } -session $SRV1
        It "[SRV1] Should have a DNS server configuration of 192.168.3.10" {
            $dns.ServerAddresses -contains '192.168.3.10' | Should Be "True"
        }

        It "[SRV1] Should be running Windows Server 2016" {
            $test = Invoke-Command { Get-CimInstance -ClassName win32_operatingsystem -property caption } -session $srv1
            $test.caption | Should BeLike '*2016*'
        }

        It "[SRV1] Should pass Test-DSCConfiguration" {
            Invoke-Command { Test-DscConfiguration -WarningAction SilentlyContinue } -session $srv1 | Should Be "True"
        }
    }
    Catch {
        It "[SRV1] Should allow a PSSession but got error: $($_.exception.message)" {
            $false | Should Be $True
        }
      }
} #SRV1

Describe SRV2 {

    $VMName = "$($prefix)SRV2"
    Try {
        $SRV2 = New-PSSession -VMName $VMName -Credential $cred -ErrorAction Stop
        $all += $srv2
        Invoke-Command $prep -session $srv2

        It "[SRV2] Should belong to the $domain domain" {
            $test = Invoke-Command { Get-CimInstance -ClassName win32_computersystem -property domain } -session $SRV2
            $test.domain | Should Be $domain
        }

        It "[SRV2] Should have an IP address of 192.168.3.51" {
            $i = Invoke-Command -ScriptBlock { Get-NetIPAddress -interfacealias 'Ethernet' -AddressFamily IPv4 } -Session $SRV2
            $i.ipv4Address | Should be '192.168.3.51'
        }
        $dns = Invoke-Command { Get-DnsClientServerAddress -InterfaceAlias ethernet -AddressFamily IPv4 } -session $SRV2
        It "[SRV2] Should have a DNS server configuration of 192.168.3.10" {
            $dns.ServerAddresses -contains '192.168.3.10' | Should Be "True"
        }

        It "[SRV2] Should be running Windows Server 2016" {
            $test = Invoke-Command { Get-CimInstance -ClassName win32_operatingsystem -property caption } -session $srv2
            $test.caption | Should BeLike '*2016*'
        }

        It "[SRV2] Should pass Test-DSCConfiguration" {
            Invoke-Command {Test-DscConfiguration -WarningAction SilentlyContinue} -session $srv2 | Should Be "True"
        }
    }
    Catch {
        It "[SRV2] Should allow a PSSession but got error: $($_.exception.message)" {
            $false | Should Be $True
        }
     }
} #SRV2

Describe SRV3 {

    $VMName = "$($prefix)SRV3"
    Try {
        $SRV3 = New-PSSession -VMName $VMName -Credential $cred -ErrorAction Stop
        $all += $srv3
        Invoke-Command $prep -session $srv3

        It "[SRV3] Should belong to the $domain domain" {
            $test = Invoke-Command { Get-CimInstance -ClassName win32_computersystem -property domain } -session $SRV3
            $test.domain | Should Be $domain
        }

        It "[SRV3] Should have an IP address of 192.168.3.52" {
            $i = Invoke-Command -ScriptBlock { Get-NetIPAddress -interfacealias 'Ethernet' -AddressFamily IPv4 } -Session $SRV3
            $i.ipv4Address | Should be '192.168.3.52'
        }
        $dns = Invoke-Command { Get-DnsClientServerAddress -InterfaceAlias ethernet -AddressFamily IPv4 } -session $SRV3
        It "[SRV3] Should have a DNS server configuration of 192.168.3.10" {
            $dns.ServerAddresses -contains '192.168.3.10' | Should Be "True"
        }

        It "[SRV3] Should be running Windows Server 2019" {
            $test = Invoke-Command { Get-CimInstance -ClassName win32_operatingsystem -property caption } -session $SRV3
            $test.caption | Should BeLike '*2019*'
        }

        It "[SRV3] Should pass Test-DSCConfiguration" {
            Invoke-Command {Test-DscConfiguration -WarningAction SilentlyContinue} -session $SRV3 | Should Be "True"
        }
    }
    Catch {
        It "[SRV3] Should allow a PSSession but got error: $($_.exception.message)" {
            $false | Should Be $True
        }
     }
} #SRV3

Describe Win10 {

    $VMName = "$($prefix)Win10"

    Try {
        $cl = New-PSSession -VMName $VMName -Credential $cred -ErrorAction Stop
        $all += $cl
        Invoke-Command $prep -session $cl

        It "[WIN10] Should belong to the $Domain domain" {
            $test = Invoke-Command { Get-CimInstance -ClassName win32_computersystem -property domain } -session $cl
            $test.domain | Should Be $Domain
        }

        It "[WIN10] Should be running Windows 10 Enterprise" {
            $test = Invoke-Command { Get-CimInstance -ClassName win32_operatingsystem -property version, caption } -session $cl
            $test.caption | Should BeLike "*Enterprise*"
        }

        It "[Win10] Should have an IP address of 192.168.3.100" {
            $i = Invoke-Command -ScriptBlock { Get-NetIPAddress -interfacealias 'Ethernet' -AddressFamily IPv4 } -session $cl
            $i.ipv4Address | Should be '192.168.3.100'
        }

        $dns = Invoke-Command { Get-DnsClientServerAddress -InterfaceAlias ethernet -AddressFamily IPv4 } -session $cl
        It "[Win10] Should have a DNS server configuration of 192.168.3.10" {
            $dns.ServerAddresses -contains '192.168.3.10' | Should Be "True"
        }

        It "[Win10] Should have RSAT installed" {
            $pkg = Invoke-Command {Get-WindowsCapability -online -name *rsat*} -session $cl

            # write-host ($pkg | Select-object Name,Displayname,State | format-list | Out-String) -ForegroundColor cyan
            $pkg | Where-Object { $_.state -ne "installed"} | Should be $Null
        }

        It "[Win10] Should pass Test-DSCConfiguration" {
            Invoke-Command {Test-DscConfiguration -WarningAction SilentlyContinue} -session $cl | Should Be "True"
        }
    }
    Catch {
        It "[Win10] Should allow a PSSession but got error: $($_.exception.message)" {
            $false | Should Be $True
        }
       }
} #client

$all | Remove-PSSession
