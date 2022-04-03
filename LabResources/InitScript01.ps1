$ErrorActionPreference = 'Stop'

Import-Module -Name ActiveDirectory
Import-Module -Name DnsServer

$pw = ConvertTo-SecureString -String 'P@ssw0rd' -AsPlainText -Force

$null = New-ADOrganizationalUnit -Name 'AdminComputer' -PassThru
$null = New-ADOrganizationalUnit -Name 'SqlComputer' -PassThru

$ouAdminUser = New-ADOrganizationalUnit -Name 'AdminUser' -PassThru
$ouSqlUser = New-ADOrganizationalUnit -Name 'SqlUser' -PassThru

New-ADUser -Name Admin -AccountPassword $pw -Enabled $true -Path $ouAdminUser.DistinguishedName

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

Add-ADGroupMember -Identity 'Domain Admins' -Members Admin
Add-ADGroupMember -Identity SQLServiceAccounts -Members SQLServer, SQLSrv1, SQLSrv2, SQLSrv3, SQLSrv4, SQLSrv5
Add-ADGroupMember -Identity SQLAdmins -Members SQLAdmin
Add-ADGroupMember -Identity SQLUsers -Members SQLUser1, SQLUser2, SQLUser3, SQLUser4, SQLUser5

Get-ChildItem -Path .\GPO\ | ForEach-Object -Process {
    $id = (Get-ChildItem -Path $_.FullName -Filter '{*').Name
    $null = New-GPO -Name $_.Name
    $null = Import-GPO -TargetName $_.Name -Path $_.FullName -BackupId $id
    $null = New-GPLink -Name $_.Name -Target (Get-ADRootDSE).defaultNamingContext
}

Move-Item -Path .\FileServer -Destination D:\
$smbShareAccessParam = @{
    AccountName = "$env:USERDOMAIN\$env:USERNAME", "$env:USERDOMAIN\Admin"
    AccessRight = 'Full'
    Force       = $true
}
$null = New-SmbShare -Path D:\FileServer -Name FileServer | Grant-SmbShareAccess @smbShareAccessParam
$null = New-SmbShare -Path D:\FileServer\Backup -Name Backup | Grant-SmbShareAccess @smbShareAccessParam
$null = New-SmbShare -Path D:\FileServer\SampleDatabases -Name SampleDatabases | Grant-SmbShareAccess @smbShareAccessParam
$null = New-SmbShare -Path D:\FileServer\Software -Name Software | Grant-SmbShareAccess @smbShareAccessParam
$null = Grant-SmbShareAccess -Name Backup -AccountName "$env:USERDOMAIN\SQLServiceAccounts" -AccessRight Change -Force

Add-DnsServerResourceRecordCName -ZoneName $env:USERDNSDOMAIN -HostNameAlias "$env:COMPUTERNAME.$env:USERDNSDOMAIN" -Name fs
