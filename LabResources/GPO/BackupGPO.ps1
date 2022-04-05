$ErrorActionPreference = 'Stop'
Import-Module -Name GroupPolicy

$backupPath = 'C:\GitHub\demos\LabResources\GPO'

$customGPOs = Get-GPO -All | Where-Object DisplayName -Like 'GPO_*'
foreach ($gpo in $customGPOs) {
    $path = "$backupPath\$($gpo.DisplayName)"
    if (Test-Path -Path $path) { Remove-Item -Path $path -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $path
    $backup = Backup-GPO -Guid $gpo.Id -Path $path
    Get-ChildItem -Path $path -Recurse -Hidden | ForEach-Object -Process { $_.Attributes = $_.Attributes -bxor [System.IO.FileAttributes]::Hidden }
}
