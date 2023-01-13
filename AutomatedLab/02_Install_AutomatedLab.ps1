$ErrorActionPreference = 'Stop'

# Setup PSGallery as a trusted source for PowerShell modules:
#############################################################

# Maybe needed for older systems that don't use TLS 1.2:
# [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$null = Install-PackageProvider -Name Nuget -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted


# Install and configure the PowerShell module AutomatedLab:
###########################################################

Install-Module -Name AutomatedLab -AllowClobber -SkipPublisherCheck -Force
Install-Module -Name Posh-SSH

[Environment]::SetEnvironmentVariable('AUTOMATEDLAB_TELEMETRY_OPTIN', 'false', 'Machine')
$env:AUTOMATEDLAB_TELEMETRY_OPTIN = 'false'

Set-PSFConfig -Module AutomatedLab -Name LabSourcesLocation -Description 'Location of lab sources folder' -Validation string -Value 'C:\AutomatedLab-Sources' -PassThru | Register-PSFConfig
Set-PSFConfig -Module AutomatedLab -Name VmPath             -Description 'Location of lab vm folder'      -Validation string -Value 'C:\AutomatedLab-VMs'     -PassThru | Register-PSFConfig

Import-Module -Name AutomatedLab

New-LabSourcesFolder

Enable-LabHostRemoting -Force


# Download some operating system ISOs:
######################################

$isoList = @(
    @{
        Uri     = 'https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso'
        OutFile = "$labSources\ISOs\2022_x64_EN_Eval.iso"
    }
<#
    @{
        Uri     = 'https://software-download.microsoft.com/download/sg/17763.253.190108-0006.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso'
        OutFile = "$labSources\ISOs\2019_x64_EN_Eval.iso"
    }
    @{
        Uri     = 'https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66751/22621.525.220925-0207.ni_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso'
        OutFile = "$labSources\ISOs\WIN11_x64_ENT_22H2_EN_Eval.iso"
    }
    @{
        Uri     = 'https://software-download.microsoft.com/download/sg/444969d5-f34g-4e03-ac9d-1f9786c69161/19044.1288.211006-0501.21h2_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso'
        OutFile = "$labSources\ISOs\WIN10_x64_ENT_21H2_EN_Eval.iso"
    }
#>
    @{
        Uri     = 'https://mirror1.hs-esslingen.de/pub/Mirrors/centos/7.9.2009/isos/x86_64/CentOS-7-x86_64-DVD-2207-02.iso'
        OutFile = "$labSources\ISOs\CentOS-7-x86_64-DVD-2207-02.iso"
    }
<#
    @{
        Uri     = 'https://mirror1.hs-esslingen.de/pub/Mirrors/centos-stream/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-dvd1.iso'
        OutFile = "$labSources\ISOs\CentOS-Stream-9-latest-x86_64-dvd1.iso"
    }
    @{
        Uri     = 'https://download.opensuse.org/distribution/leap/15.2/iso/openSUSE-Leap-15.2-DVD-x86_64.iso'
        OutFile = "$labSources\ISOs\openSUSE-Leap-15.2-DVD-x86_64.iso"
    }
#>
)
# You can find more windows operating systems here: https://github.com/VirtualEngine/Lability/blob/dev/Config/Media.json
# The link for Windows 11 is from here: https://github.com/VirtualEngine/Lability/pull/415/files

foreach ($iso in $isoList) {
    if (-not (Test-Path -Path $iso.OutFile)) {
        Invoke-WebRequest -Uri $iso.Uri -OutFile $iso.OutFile -UseBasicParsing
    }
}

Get-LabAvailableOperatingSystem | Sort-Object OperatingSystemName

<#

OperatingSystemName                                            Idx Version         PublishedDate       IsoPath                                           
-------------------                                            --- -------         -------------       -------                                           
CentOS Stream 9                                                0   9.0             12.12.2022 11:04:22 C:\AutomatedLab-Sources\ISOs\CentOS-Stream-9-latest-x86_64-...
CentOS-7                                                       0   7.0             26.07.2022 16:40:33 C:\AutomatedLab-Sources\ISOs\CentOS-7-x86_64-DVD-2207-02.iso
openSUSE Leap 15.2                                             0   15.0            09.06.2020 17:18:51 C:\AutomatedLab-Sources\ISOs\openSUSE-Leap-15.2-DVD-x86_64.iso
Windows 10 Enterprise Evaluation                               1   10.0.19041.1288 06.10.2021 15:07:52 C:\AutomatedLab-Sources\ISOs\WIN10_x64_ENT_21H2_EN_Eval.iso 
Windows 11 Enterprise Evaluation                               1   10.0.22621.525  25.09.2022 03:47:56 C:\AutomatedLab-Sources\ISOs\WIN11_x64_ENT_22H2_EN_Eval.iso 
Windows Server 2019 Datacenter Evaluation                      3   10.0.17763.253  08.01.2019 02:26:26 C:\AutomatedLab-Sources\ISOs\2019_x64_EN_Eval.iso           
Windows Server 2019 Datacenter Evaluation (Desktop Experience) 4   10.0.17763.253  08.01.2019 02:27:56 C:\AutomatedLab-Sources\ISOs\2019_x64_EN_Eval.iso           
Windows Server 2019 Standard Evaluation                        1   10.0.17763.253  08.01.2019 02:29:22 C:\AutomatedLab-Sources\ISOs\2019_x64_EN_Eval.iso           
Windows Server 2019 Standard Evaluation (Desktop Experience)   2   10.0.17763.253  08.01.2019 02:27:51 C:\AutomatedLab-Sources\ISOs\2019_x64_EN_Eval.iso           
Windows Server 2022 Datacenter Evaluation                      3   10.0.20348.587  03.03.2022 05:03:12 C:\AutomatedLab-Sources\ISOs\2022_x64_EN_Eval.iso           
Windows Server 2022 Datacenter Evaluation (Desktop Experience) 4   10.0.20348.587  03.03.2022 05:10:29 C:\AutomatedLab-Sources\ISOs\2022_x64_EN_Eval.iso           
Windows Server 2022 Standard Evaluation                        1   10.0.20348.587  03.03.2022 05:02:13 C:\AutomatedLab-Sources\ISOs\2022_x64_EN_Eval.iso           
Windows Server 2022 Standard Evaluation (Desktop Experience)   2   10.0.20348.587  03.03.2022 05:08:50 C:\AutomatedLab-Sources\ISOs\2022_x64_EN_Eval.iso           

#>
