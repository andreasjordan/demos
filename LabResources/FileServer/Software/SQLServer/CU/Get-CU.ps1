[CmdletBinding()]
param (
    [ValidateSet('2019', '2017', '2016', '2014')]
    [string[]]$Version = @('2019', '2017'),
    [int]$Last = 1,
    [string]$Path = '.',
    [switch]$UpdateBuildReference = $true
)

function Get-CU {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('2019', '2017', '2016', '2014')]
        [string]$Version,
        [regex]$BuildBaseRegex,
        [int]$Last = 1,
        [string[]]$Exclude,
        [string]$Path = '.'
    )
    if ($null -eq $BuildBaseRegex) {
        $BuildBaseRegex = switch ($Version) {
            '2019' { '^15' }
            '2017' { '^14' }
            '2016' { '^13.0.5' }  # Based on SP2
            '2014' { '^12.0.6' }  # Based on SP3
        }
    }
    if ($Version -eq '2019') { 
        $Exclude += 'CU7'  # CU7 is not available any more
    }
    $buildrefFile = Join-Path -Path (Get-DbatoolsConfigValue -Name 'Path.DbatoolsData') -ChildPath "dbatools-buildref-index.json"
    $buildrefData = (Get-Content -Path $buildrefFile -Raw | ConvertFrom-Json).Data
    $cuData = $buildrefData | 
        Where-Object -FilterScript { $_.Version -match $BuildBaseRegex -and $_.CU -ne $null -and $_.CU -notin $Exclude } |
        Sort-Object -Property KBList |
        Select-Object -Last $Last
    foreach ($cu in $cuData) {
        $kbNr = $cu.KBList
        $cuName = $cu.CU
        $filePath = Join-Path -Path $Path -ChildPath "SQLServer$Version-KB$kbNr-$cuName-x64.exe"
        if (-not (Test-Path -Path $filePath)) {
            Write-Progress -Activity "Downloading Cumulative Updates for SQL Server" -Status "Downloading KB $kbNr for SQL Server $Version to $filePath"
            Save-DbaKbUpdate -Name $kbNr -FilePath $filePath
        }
    }
}

Write-Progress -Activity "Downloading Cumulative Updates for SQL Server" -Status "Importing dbatools"
Import-Module -Name dbatools

if ($UpdateBuildReference) {
    Write-Progress -Activity "Downloading Cumulative Updates for SQL Server" -Status "Updating build reference"
    Update-DbaBuildReference
}

foreach ($ver in $Version) {
    Get-CU -Version $ver -Last $Last -Path $Path
}

Write-Progress -Activity "Downloading Cumulative Updates for SQL Server" -Completed


<# Other usage examples:

Get-CU -Version 2019 -Path 'C:\SQLServerPatches'
Get-CU -Version 2017 -Path 'C:\SQLServerPatches' -Last 5
Get-CU -Version 2016 -Path 'C:\SQLServerPatches' -Last 5
Get-CU -Version 2014 -Path 'C:\SQLServerPatches'
# KB4583462 - Security update for SQL Server 2014 SP3 CU4: January 12, 2021
Save-DbaKbUpdate -Name 4583462 -FilePath 'C:\SQLServerPatches\SQLServer2014-KB4583462-CU4-Security-x64.exe'
# KB4583465 - Security update for SQL Server 2012 SP4 GDR: January 12, 2021
Save-DbaKbUpdate -Name 4583465 -FilePath 'C:\SQLServerPatches\SQLServer2012-KB4583465-GDR-Security-x64.exe'
# Check for new versions at: https://sqlserverbuilds.blogspot.com/
# KB5003830 - New CU that is not yet known by dbatools
Save-DbaKbUpdate -Name 5003830 -FilePath 'C:\SQLServerPatches\SQLServer2017-KB5003830-CU25-x64.exe'

#>
