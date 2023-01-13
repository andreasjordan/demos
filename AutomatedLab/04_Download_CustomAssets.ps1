$ErrorActionPreference = 'Stop'

Import-Module -Name AutomatedLab

# Download the GitHub repository and move CustomAssets and CustomScripts to LabSources directory:
#################################################################################################

$tmpFolder = Join-Path -Path $env:TEMP -ChildPath (New-Guid).Guid
$null = New-Item -Path $tmpFolder -ItemType Directory
$uri = 'https://github.com/andreasjordan/demos/archive/refs/heads/master.zip'
Invoke-WebRequest -Uri $uri -OutFile "$tmpFolder\master.zip" -UseBasicParsing
Expand-Archive -Path "$tmpFolder\master.zip" -DestinationPath $tmpFolder
Move-Item -Path "$tmpFolder\demos-master\AutomatedLab\CustomAssets" -Destination $labSources
Move-Item -Path "$tmpFolder\demos-master\AutomatedLab\CustomScripts" -Destination $labSources
Remove-Item -Path $tmpFolder -Recurse -Force
