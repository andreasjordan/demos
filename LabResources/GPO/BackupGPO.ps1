$ErrorActionPreference = 'Stop'
Import-Module -Name GroupPolicy

$backupPath = 'C:\GitHub\demos\LabResources\GPO'

$customGPOs = Get-GPO -All | Where-Object DisplayName -Like 'GPO_*'
# $customGPOs | Format-Table -Property Id, DisplayName

foreach ($gpo in $customGPOs) {
    # Set path for backup to include the name of the GPO
    $path = "$backupPath\$($gpo.DisplayName)"
    # Remove directory with content if it exists from a previous backup
    if (Test-Path -Path $path) { Remove-Item -Path $path -Recurse -Force }
    # Create directory for current backup
    $null = New-Item -ItemType Directory -Path $path
    # Backup the GPO
    $backup = Backup-GPO -Guid $gpo.Id -Path $path
    # Rename folder from Id to GpoId to have the same folder name in every backup to support export to GitHub
    "$path\{$($backup.Id.ToString().ToUpper())}  ->  {$($backup.GpoId.ToString().ToUpper())}"
    Get-Item -Path "$path\{$($backup.Id.ToString().ToUpper())}" | Rename-Item -NewName "{$($backup.GpoId.ToString().ToUpper())}"
    # Make all hidden files visable
    Get-ChildItem -Path $path -Recurse -Hidden | ForEach-Object -Process { $_.Attributes = “Archive” }
}

