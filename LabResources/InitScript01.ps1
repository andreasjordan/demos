$ErrorActionPreference = 'Stop'

Import-Module -Name ActiveDirectory
Import-Module -Name DnsServer

$pw = ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force

$ouAdminComputer = New-ADOrganizationalUnit -Name 'AdminComputer' -PassThru
$ouAdminUser = New-ADOrganizationalUnit -Name 'AdminUser' -PassThru
$ouSqlComputer = New-ADOrganizationalUnit -Name 'SqlComputer' -PassThru
$ouSqlUser = New-ADOrganizationalUnit -Name 'SqlUser' -PassThru

New-ADUser -Name SQLServer -AccountPassword $pw -Enabled $true -Path $ouSqlUser.DistinguishedName
New-ADUser -Name SQLSrv1 -AccountPassword $pw -Enabled $true -Path $ouSqlUser.DistinguishedName
New-ADUser -Name SQLSrv2 -AccountPassword $pw -Enabled $true -Path $ouSqlUser.DistinguishedName
New-ADUser -Name SQLSrv3 -AccountPassword $pw -Enabled $true -Path $ouSqlUser.DistinguishedName
New-ADUser -Name SQLSrv4 -AccountPassword $pw -Enabled $true -Path $ouSqlUser.DistinguishedName
New-ADUser -Name SQLSrv5 -AccountPassword $pw -Enabled $true -Path $ouSqlUser.DistinguishedName
New-ADUser -Name SQLAdmin -AccountPassword $pw -Enabled $true -Path $ouSqlUser.DistinguishedName
New-ADUser -Name SQLUser1 -AccountPassword $pw -Enabled $true -Path $ouSqlUser.DistinguishedName
New-ADUser -Name SQLUser2 -AccountPassword $pw -Enabled $true -Path $ouSqlUser.DistinguishedName
New-ADUser -Name SQLUser3 -AccountPassword $pw -Enabled $true -Path $ouSqlUser.DistinguishedName
New-ADUser -Name SQLUser4 -AccountPassword $pw -Enabled $true -Path $ouSqlUser.DistinguishedName
New-ADUser -Name SQLUser5 -AccountPassword $pw -Enabled $true -Path $ouSqlUser.DistinguishedName

New-ADGroup -Name SQLServiceAccounts -GroupCategory Security -GroupScope Global -Path $ouSqlUser.DistinguishedName
New-ADGroup -Name SQLAdmins -GroupCategory Security -GroupScope Global -Path $ouSqlUser.DistinguishedName
New-ADGroup -Name SQLUsers -GroupCategory Security -GroupScope Global -Path $ouSqlUser.DistinguishedName

Add-ADGroupMember -Identity SQLServiceAccounts -Members SQLServer, SQLSrv1, SQLSrv2, SQLSrv3, SQLSrv4, SQLSrv5
Add-ADGroupMember -Identity SQLAdmins -Members SQLAdmin
Add-ADGroupMember -Identity SQLUsers -Members SQLUser1, SQLUser2, SQLUser3, SQLUser4, SQLUser5


<#
$session = New-PSSession -ComputerName dc
Invoke-Command -Session $session -ScriptBlock { Get-Disk | Where-Object IsOffline | Set-Disk -IsOffline $false }
Invoke-Command -Session $session -ScriptBlock { Get-Disk | Where-Object IsReadOnly | Set-Disk -IsReadOnly $false }
Invoke-Command -Session $session -ScriptBlock { $null = New-SmbShare -Path D:\FileServer -Name FileServer | Grant-SmbShareAccess -AccountName "ORDIX\Admin" -AccessRight Full -Force }
Invoke-Command -Session $session -ScriptBlock { $null = New-SmbShare -Path D:\FileServer\Backup -Name Backup | Grant-SmbShareAccess -AccountName "ORDIX\Admin" -AccessRight Full -Force }
Invoke-Command -Session $session -ScriptBlock { $null = New-SmbShare -Path D:\FileServer\ORDIX -Name ORDIX | Grant-SmbShareAccess -AccountName "ORDIX\Admin" -AccessRight Full -Force }
Invoke-Command -Session $session -ScriptBlock { $null = New-SmbShare -Path D:\FileServer\SampleDatabases -Name SampleDatabases | Grant-SmbShareAccess -AccountName "ORDIX\Admin" -AccessRight Full -Force }
Invoke-Command -Session $session -ScriptBlock { $null = New-SmbShare -Path D:\FileServer\Software -Name Software | Grant-SmbShareAccess -AccountName "ORDIX\Admin" -AccessRight Full -Force }
Invoke-Command -Session $session -ScriptBlock { $null = Grant-SmbShareAccess -Name Backup -AccountName "ORDIX\SQLServiceAccounts" -AccessRight Change -Force }

Add-DnsServerResourceRecordCName -ComputerName dc -ZoneName ordix.local -HostNameAlias dc.ordix.local -Name fs
#>

Get-ChildItem -Path .\GPO\ | ForEach-Object -Process {
    $id = (Get-ChildItem -Path $_.FullName).Name
    $null = New-GPO -Name $_.Name
    $null = Import-GPO -TargetName $_.Name -Path $_.FullName -BackupId $id
    $null = New-GPLink -Name $_.Name -Target (Get-ADRootDSE).defaultNamingContext
}
